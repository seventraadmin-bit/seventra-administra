// Bug real reportado por Marlon (Etapa 15): un descuento automático de
// Inventario bajaba el `totalAPagar` pero la sección Fiscal/No fiscal
// conservaba el neto ANTERIOR al descuento — `montoFiscal +
// montoNoFiscal != totalAPagar`. Causa raíz: `generar()` fijaba
// `montoFiscal` contra `importeBase + bonoPropuesto`, ANTES de restar
// `descuentosInventario`; `ActualizarNominaDesdePersonalUseCase` tenía
// el mismo defecto (calculaba `nuevoTotal` sin el descuento); y
// `actualizarMovimientos` (editar préstamo/bono/tiempo extra/faltas/
// otros descuentos) ni siquiera tocaba Fiscal/No fiscal. Los tres se
// centralizaron en `NominaRepositoryImpl._resolverDistribucionFiscal`,
// que siempre resuelve contra el `totalAPagar` FINAL.
//
// Invariante dura verificada en cada prueba:
//   montoFiscal + montoNoFiscal == totalAPagar
// después de CUALQUIER combinación de percepciones/deducciones,
// incluidos descuentos de Inventario, bonos, tiempo extra, préstamos,
// faltas y otros descuentos.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late ActualizarRenglonNominaUseCase actualizarRenglon;
  late ActualizarNominaDesdePersonalUseCase actualizarDesdePersonal;
  late CerrarNominaUseCase cerrarNomina;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);

    nominaRepo = NominaRepositoryImpl(db, asignacionRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina =
        GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    actualizarRenglon = ActualizarRenglonNominaUseCase(nominaRepo);
    actualizarDesdePersonal = ActualizarNominaDesdePersonalUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
  });

  tearDown(() => db.close());

  var empleadoContador = 0;
  // Sueldo mensual $11,000.00 → importeBase de una primera quincena
  // (15 días) = sueldo/2 = $5,500.00 — el caso exacto reportado.
  Future<EmpleadoData> crearEmpleadoConSueldo(int sueldoMensualAdministrativo) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: empleadoContador,
            nombres: 'Empleado$n',
            apellidoPaterno: 'Apellido$n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX$n',
            rfc: 'PEXJ900101$n',
            nss: '100000000$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  var articuloContador = 0;
  Future<ArticuloData> crearArticuloDePrueba() async {
    articuloContador++;
    final categoria = (await CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db)).ejecutar(nombre: 'Uniformes$articuloContador')
            as CrearCategoriaArticuloExitoso)
        .categoria;
    final resultado = await CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)))
        .ejecutar(categoriaId: categoria.id, nombre: 'PANTALON NEGRO COMANDO $articuloContador', manejaVariante: false, manejaSerie: false);
    final articulo = (resultado as CrearArticuloExitoso).articulo;
    await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 8, 1));
    return articulo;
  }

  /// Genera un descuento pendiente real de [importe] para [empleadoId]
  /// — Artículo → Asignación → pérdida con cargo (misma cadena que la
  /// prueba funcional real de Marlon).
  Future<void> generarDescuentoPendiente(String empleadoId, int importe) async {
    final articulo = await crearArticuloDePrueba();
    final asignacion = ((await crearAsignacion.ejecutar(
      articuloId: articulo.id,
      cantidad: 1,
      empleadoId: empleadoId,
      fechaEntrega: DateTime(2026, 8, 2),
    )) as CrearAsignacionExitoso)
        .asignacion;
    await cerrarAsignacion.ejecutar(
      asignacionId: asignacion.id,
      motivo: MotivoCierreAsignacion.perdida,
      fechaCierre: DateTime(2026, 8, 3),
      atribuibleAlEmpleado: true,
      generaDescuento: true,
      importeDescuento: importe,
      empleadoResponsableDescuentoId: empleadoId,
    );
  }

  void esperarCuadre(NominaEmpleadoData renglon) {
    expect(
      renglon.montoFiscal + renglon.montoNoFiscal,
      renglon.totalAPagar,
      reason: 'invariante dura: Fiscal + No fiscal debe ser siempre exactamente el total a pagar',
    );
  }

  test('Nómina \$5,500 sin movimientos: Fiscal = \$5,500, No fiscal = \$0', () async {
    final empleado = await crearEmpleadoConSueldo(1100000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

    expect(renglon.importeBase, 550000);
    expect(renglon.totalAPagar, 550000);
    expect(renglon.montoFiscal, 550000);
    expect(renglon.montoNoFiscal, 0);
    esperarCuadre(renglon);
  });

  test(
    'caso real reportado: descuento de Inventario \$250 sobre base \$5,500 → neto \$5,250 → Fiscal + No fiscal = \$5,250 '
    '(nunca \$5,500 Fiscal)',
    () async {
      final empleado = await crearEmpleadoConSueldo(1100000);
      await generarDescuentoPendiente(empleado.id, 25000);

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

      expect(renglon.importeBase, 550000);
      expect(renglon.descuentosInventario, 25000);
      expect(renglon.totalAPagar, 525000, reason: '5500 - 250 = 5250');
      expect(renglon.montoFiscal, 525000, reason: 'nunca debe quedar congelado en 5500');
      expect(renglon.montoNoFiscal, 0);
      esperarCuadre(renglon);
    },
  );

  test('agregar un bono (actualizarMovimientos) sobre una Nómina con descuento: la distribución sigue cuadrando', () async {
    final empleado = await crearEmpleadoConSueldo(1100000);
    await generarDescuentoPendiente(empleado.id, 25000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglonInicial = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

    final resultado = await actualizarRenglon.ejecutar(nominaEmpleadoId: renglonInicial.id, bono: 100000);
    expect(resultado, isA<ActualizarRenglonNominaExitoso>());
    final renglon = (resultado as ActualizarRenglonNominaExitoso).renglon;

    expect(renglon.totalAPagar, 625000, reason: '5500 + 1000 bono - 250 descuento = 6250');
    expect(renglon.montoFiscal, 625000);
    expect(renglon.montoNoFiscal, 0);
    esperarCuadre(renglon);
  });

  test('agregar préstamo y otros descuentos (actualizarMovimientos): la distribución sigue cuadrando', () async {
    final empleado = await crearEmpleadoConSueldo(1100000);
    await generarDescuentoPendiente(empleado.id, 25000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglonInicial = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

    final resultado = await actualizarRenglon.ejecutar(nominaEmpleadoId: renglonInicial.id, prestamo: 50000, otrosDescuentos: 20000);
    expect(resultado, isA<ActualizarRenglonNominaExitoso>());
    final renglon = (resultado as ActualizarRenglonNominaExitoso).renglon;

    expect(renglon.totalAPagar, 455000, reason: '5500 - 250 descuento - 500 préstamo - 200 otros = 4550');
    expect(renglon.montoFiscal, 455000);
    esperarCuadre(renglon);
  });

  test('"Actualizar desde Personal" incorpora un descuento nacido DESPUÉS del borrador: la distribución se recalcula', () async {
    final empleado = await crearEmpleadoConSueldo(1100000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglonInicial = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;
    expect(renglonInicial.montoFiscal, 550000);

    await generarDescuentoPendiente(empleado.id, 25000);
    final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
    expect(resultado, isA<ActualizarNominaDesdePersonalExitoso>());

    final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;
    expect(renglon.totalAPagar, 525000);
    expect(renglon.montoFiscal, 525000, reason: 'se recalcula, no queda congelado en el total anterior');
    expect(renglon.montoNoFiscal, 0);
    esperarCuadre(renglon);
  });

  test('ejecutar "Actualizar desde Personal" una segunda vez: no altera ni duplica importes', () async {
    final empleado = await crearEmpleadoConSueldo(1100000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await generarDescuentoPendiente(empleado.id, 25000);
    await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
    final renglonTrasPrimera = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

    final resultado2 = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
    expect(resultado2, isA<ActualizarNominaDesdePersonalExitoso>());
    final renglonTrasSegunda = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

    expect(renglonTrasSegunda.totalAPagar, renglonTrasPrimera.totalAPagar);
    expect(renglonTrasSegunda.montoFiscal, renglonTrasPrimera.montoFiscal);
    expect(renglonTrasSegunda.montoNoFiscal, renglonTrasPrimera.montoNoFiscal);
    expect(renglonTrasSegunda.descuentosInventario, 25000, reason: 'nunca se duplica el descuento');
    esperarCuadre(renglonTrasSegunda);
  });

  test(
    'distribución modificada a mano: se conserva SIEMPRE ante un cambio de neto posterior, nunca se ajusta en silencio — '
    'se marca pendiente de revisión y bloquea el cierre',
    () async {
      final empleado = await crearEmpleadoConSueldo(1100000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonInicial = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;
      expect(renglonInicial.totalAPagar, 550000);

      // El usuario captura una distribución manual (300000 Fiscal / 250000 No fiscal).
      final manual = await actualizarRenglon.ejecutar(
        nominaEmpleadoId: renglonInicial.id,
        distribucionManual: (montoFiscal: 300000, montoNoFiscal: 250000),
      );
      expect(manual, isA<ActualizarRenglonNominaExitoso>());
      final renglonManual = (manual as ActualizarRenglonNominaExitoso).renglon;
      expect(renglonManual.distribucionModificadaManualmente, isTrue);
      expect(renglonManual.distribucionPendienteRevision, isFalse);
      esperarCuadre(renglonManual);

      // Ahora nace un descuento de Inventario que cambia el neto — la
      // distribución manual NUNCA se ajusta en silencio.
      await generarDescuentoPendiente(empleado.id, 25000);
      await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);

      final renglonTrasCambio = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;
      expect(renglonTrasCambio.totalAPagar, 525000);
      expect(renglonTrasCambio.montoFiscal, 300000, reason: 'la intención manual del usuario se conserva tal cual, nunca se repone');
      expect(renglonTrasCambio.montoNoFiscal, 250000);
      expect(
        renglonTrasCambio.montoFiscal + renglonTrasCambio.montoNoFiscal,
        isNot(equals(renglonTrasCambio.totalAPagar)),
        reason: 'la distribución preservada ya no cuadra con el nuevo neto — se marca, nunca se disfraza',
      );
      expect(renglonTrasCambio.distribucionPendienteRevision, isTrue);

      // Y el cierre debe bloquearse mientras siga así.
      final cierre = await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      expect(cierre, isA<CerrarNominaDistribucionPendiente>());
    },
  );

  test('distribución modificada a mano que SIGUE cuadrando tras un cambio ajeno: no se marca pendiente de revisión', () async {
    final empleado = await crearEmpleadoConSueldo(1100000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    final renglonInicial = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: generado.nomina.id, empleadoId: empleado.id))!;

    final manual = await actualizarRenglon.ejecutar(
      nominaEmpleadoId: renglonInicial.id,
      distribucionManual: (montoFiscal: 400000, montoNoFiscal: 150000),
    );
    final renglonManual = (manual as ActualizarRenglonNominaExitoso).renglon;

    // Un movimiento manual que NO cambia el total (bono compensado por
    // préstamo del mismo monto) — la distribución conservada sigue
    // cuadrando exactamente.
    final resultado = await actualizarRenglon.ejecutar(nominaEmpleadoId: renglonManual.id, bono: 30000, prestamo: 30000);
    final renglon = (resultado as ActualizarRenglonNominaExitoso).renglon;

    expect(renglon.totalAPagar, 550000);
    expect(renglon.montoFiscal, 400000);
    expect(renglon.montoNoFiscal, 150000);
    expect(renglon.distribucionPendienteRevision, isFalse);
    esperarCuadre(renglon);
  });
}
