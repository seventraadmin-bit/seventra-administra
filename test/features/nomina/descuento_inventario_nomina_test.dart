// Prueba funcional Inventario + Personal + Nómina (Marlon, punto 2):
// flujo completo "Pendiente → Aplicado en Nómina" de un
// `DescuentoInventario` por daño/pérdida con cargo al empleado —
// investigación previa confirmó que el tramo estaba completamente sin
// implementar (la tabla y el estatus `aplicado` ya existían, pero
// nada los consumía). Esta prueba cubre exactamente los escenarios
// obligatorios: crea descuento pendiente al reportar con cargo, no lo
// crea sin cargo, `GenerarNominaUseCase` lo aplica exactamente una vez
// (resta del neto, vincula el renglón, cambia a Aplicado), no vuelve a
// aplicarse en una Nómina posterior, y el vínculo queda auditable
// (folio + fecha, resoluble desde el expediente del empleado).

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
import 'package:riseg_one/features/inventario/data/tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
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
    actualizarDesdePersonal = ActualizarNominaDesdePersonalUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
  });

  tearDown(() => db.close());

  var empleadoContador = 0;
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
    await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 8, 20));
    return articulo;
  }

  /// Asigna un artículo recién creado al Empleado y lo cierra con
  /// `motivo: perdida` — con o sin cargo, según [cargoAlEmpleado].
  Future<void> reportarPerdidaConCargo(String empleadoId, {required bool cargoAlEmpleado, int importe = 20000}) async {
    final articulo = await crearArticuloDePrueba();
    final creada = ((await crearAsignacion.ejecutar(
      articuloId: articulo.id,
      cantidad: 1,
      empleadoId: empleadoId,
      fechaEntrega: DateTime(2026, 8, 21),
    )) as CrearAsignacionExitoso)
        .asignacion;

    final resultado = await cerrarAsignacion.ejecutar(
      asignacionId: creada.id,
      motivo: MotivoCierreAsignacion.perdida,
      fechaCierre: DateTime(2026, 8, 22),
      atribuibleAlEmpleado: cargoAlEmpleado,
      generaDescuento: cargoAlEmpleado,
      importeDescuento: cargoAlEmpleado ? importe : null,
      empleadoResponsableDescuentoId: cargoAlEmpleado ? empleadoId : null,
    );
    expect(resultado, isA<CerrarAsignacionExitoso>());
  }

  test('reportar pérdida CON cargo al empleado crea un DescuentoInventario pendiente', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 20000);

    final pendientes = await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id);
    expect(pendientes, hasLength(1));
    expect(pendientes.single.importe, 20000);
    expect(pendientes.single.estatus, EstatusDescuentoInventario.pendiente.name);
    expect(pendientes.single.nominaEmpleadoId, isNull, reason: 'nada se aplica todavía');
  });

  test('reportar pérdida SIN cargo al empleado no genera ningún descuento', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: false);

    final todos = await asignacionRepo.listarDescuentosPorEmpleado(empleado.id);
    expect(todos, isEmpty);
  });

  test(
    'GenerarNominaUseCase aplica exactamente una vez el descuento pendiente: lo resta del neto, lo vincula al '
    'renglón y lo cambia a Aplicado',
    () async {
      final empleado = await crearEmpleadoConSueldo(1500000);
      await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 20000);

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera);
      expect(resultado, isA<GenerarNominaExitoso>());
      final nomina = (resultado as GenerarNominaExitoso).nomina;

      final renglon = await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id);
      expect(renglon, isNotNull);
      expect(renglon!.descuentosInventario, 20000);
      expect(
        renglon.totalAPagar,
        renglon.importeBase + renglon.bono + renglon.tiempoExtra - renglon.prestamo - renglon.descuentoPorFaltas - renglon.otrosDescuentos - 20000,
        reason: 'el descuento de inventario debe restarse del neto',
      );

      final descuento = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
      expect(descuento.estatus, EstatusDescuentoInventario.aplicado.name);
      expect(descuento.nominaEmpleadoId, renglon.id, reason: 'vínculo auditable entre el descuento y el renglón de Nómina');
      expect(descuento.fechaAplicacion, isNotNull);

      final pendientesRestantes = await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id);
      expect(pendientesRestantes, isEmpty);
    },
  );

  test('un descuento ya Aplicado no vuelve a entrar en una Nómina posterior', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 20000);

    final primeraNomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
    final renglonPrimera = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: primeraNomina.id, empleadoId: empleado.id))!;
    expect(renglonPrimera.descuentosInventario, 20000);

    final segundaNomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso).nomina;
    final renglonSegunda = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: segundaNomina.id, empleadoId: empleado.id))!;
    expect(renglonSegunda.descuentosInventario, 0, reason: 'el descuento ya se aplicó en la primera Nómina — nunca se cobra dos veces');

    // Sigue habiendo un único DescuentoInventario, sin duplicarse.
    final todos = await asignacionRepo.listarDescuentosPorEmpleado(empleado.id);
    expect(todos, hasLength(1));
    expect(todos.single.nominaEmpleadoId, renglonPrimera.id);
  });

  test('un Empleado con varios descuentos pendientes: la Nómina suma todos correctamente en un solo renglón', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 20000);
    await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 35000);
    await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 15000);

    final pendientesAntes = await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id);
    expect(pendientesAntes, hasLength(3));

    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
    final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;

    expect(renglon.descuentosInventario, 70000, reason: '20000 + 35000 + 15000');

    final aplicados = await asignacionRepo.listarDescuentosPorEmpleado(empleado.id);
    expect(aplicados.every((d) => d.estatus == EstatusDescuentoInventario.aplicado.name), isTrue);
    expect(aplicados.every((d) => d.nominaEmpleadoId == renglon.id), isTrue);
  });

  test(
    '"Actualizar desde Personal" incorpora un descuento pendiente creado DESPUÉS del borrador, sin duplicar en '
    'llamadas repetidas',
    () async {
      final empleado = await crearEmpleadoConSueldo(1500000);

      // Borrador generado ANTES de que exista ningún descuento.
      final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
      final renglonInicial = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;
      expect(renglonInicial.descuentosInventario, 0);

      // El descuento nace DESPUÉS de que el borrador ya existía.
      await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 20000);

      final resultado1 = await actualizarDesdePersonal.ejecutar(nominaId: nomina.id);
      expect(resultado1, isA<ActualizarNominaDesdePersonalExitoso>());

      final renglonTrasActualizar = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;
      expect(renglonTrasActualizar.descuentosInventario, 20000, reason: 'el descuento nuevo debe incorporarse sin acción adicional');
      expect(renglonTrasActualizar.id, renglonInicial.id, reason: 'guardarRenglon debe actualizar in-place, nunca borrar+reinsertar');

      final descuento = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
      expect(descuento.estatus, EstatusDescuentoInventario.aplicado.name);
      expect(descuento.nominaEmpleadoId, renglonInicial.id);

      // Repetir "Actualizar desde Personal" no debe duplicar el descuento
      // ya aplicado.
      final resultado2 = await actualizarDesdePersonal.ejecutar(nominaId: nomina.id);
      expect(resultado2, isA<ActualizarNominaDesdePersonalExitoso>());

      final renglonTrasSegundaActualizacion = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;
      expect(renglonTrasSegundaActualizacion.descuentosInventario, 20000, reason: 'nunca se duplica un descuento ya aplicado');

      final todos = await asignacionRepo.listarDescuentosPorEmpleado(empleado.id);
      expect(todos, hasLength(1));
    },
  );

  test(
    'descuentos pendientes que superan el neto: aplica solo lo que cabe, deja el resto pendiente y marca el '
    'renglón para revisión — nunca un total negativo',
    () async {
      // Sueldo administrativo bajo para forzar un neto pequeño.
      final empleado = await crearEmpleadoConSueldo(550000);
      await reportarPerdidaConCargo(empleado.id, cargoAlEmpleado: true, importe: 700000);

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera);
      expect(resultado, isA<GenerarNominaExitoso>());
      final nomina = (resultado as GenerarNominaExitoso).nomina;

      final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;

      // El único descuento pendiente ($7,000) no cabe en el neto
      // disponible — se rechaza por completo (no hay forma de aplicar
      // parte de un solo renglón de descuento) y el renglón queda
      // marcado para revisión manual.
      expect(renglon.descuentosInventario, 0, reason: 'el descuento no cabe en el neto disponible, no se aplica');
      expect(renglon.descuentosInventarioPendienteRevision, isTrue);
      expect(renglon.totalAPagar, greaterThanOrEqualTo(0), reason: 'nunca un total negativo silencioso');

      final pendientes = await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id);
      expect(pendientes, hasLength(1), reason: 'el descuento que no cupo permanece pendiente para una Nómina futura');
      expect(pendientes.single.importe, 700000);

      // Cerrar la Nómina debe bloquearse mientras quede un renglón
      // pendiente de revisión por descuentos de Inventario.
      final cierre = await cerrarNomina.ejecutar(nominaId: nomina.id);
      expect(cierre, isA<CerrarNominaDescuentosInventarioPendientes>());
    },
  );
}
