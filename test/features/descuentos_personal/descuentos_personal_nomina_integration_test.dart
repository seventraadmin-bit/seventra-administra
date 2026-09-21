// Etapa 15 — Descuentos Programados al Personal, integración real con
// Nómina. Cubre los escenarios obligatorios del pedido: préstamos
// (pago único/parcialidades, sin perder centavos), botas (sugerido y
// modificado), incorporación automática en Nómina (correspondiente,
// nunca futura, nunca duplicada), el punto exacto donde una cuota
// pasa de `reservada` a `aplicada` (solo al pagarse de verdad, nunca
// en Borrador), reversas (eliminar Borrador, eliminar cadena de
// prueba de una Nómina Pagada), préstamo+botas+DescuentoInventario+
// faltas combinados, baja laboral conserva saldo, cancelación
// conserva historial, reprogramación solo toca cuotas futuras, y el
// bloqueo de cierre cuando las deducciones no caben en el neto.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/reprogramar_cuotas_pendientes_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_cadena_prueba_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late ActualizarNominaDesdePersonalUseCase actualizarDesdePersonal;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late EliminarNominaFisicamenteUseCase eliminarNominaFisicamente;
  late EliminarCadenaPruebaNominaUseCase eliminarCadenaPrueba;
  late DescuentoProgramadoRepository descuentoRepo;
  late ActualizarRenglonNominaUseCase actualizarRenglonNomina;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;
  late ReprogramarCuotasPendientesUseCase reprogramarCuotas;
  late CancelarSaldoDescuentoProgramadoUseCase cancelarSaldo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final EgresoRepository egresoRepo = EgresoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);

    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);

    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    nominaRepo = NominaRepositoryImpl(db, asignacionRepo, descuentoRepo, TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);
    actualizarDesdePersonal = ActualizarNominaDesdePersonalUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo);
    actualizarRenglonNomina = ActualizarRenglonNominaUseCase(nominaRepo);

    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));
    eliminarNominaFisicamente = EliminarNominaFisicamenteUseCase(nominaRepo);
    eliminarCadenaPrueba = EliminarCadenaPruebaNominaUseCase(nominaRepo);

    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, generarCodigo);
    reprogramarCuotas = ReprogramarCuotasPendientesUseCase(descuentoRepo);
    cancelarSaldo = CancelarSaldoDescuentoProgramadoUseCase(descuentoRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  var empleadoContador = 0;
  Future<EmpleadoData> crearEmpleadoDePrueba({int sueldoMensualAdministrativo = 3000000}) async {
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

  Future<DescuentoProgramadoEmpleadoData> registrarPrestamoDePrueba({
    required String empleadoId,
    required int importeOriginal,
    required int numeroCuotas,
    required DateTime fechaPrimeraCuota,
    String tipo = 'prestamo',
  }) async {
    final resultado = await registrarDescuento.ejecutar(
      empleadoId: empleadoId,
      tipo: tipo,
      fechaRegistro: fechaPrimeraCuota,
      importeOriginal: importeOriginal,
      numeroCuotas: numeroCuotas,
      fechaPrimeraCuota: fechaPrimeraCuota,
    );
    return (resultado as RegistrarDescuentoProgramadoExitoso).descuento;
  }

  group('1-2. Préstamos: pago único y parcialidades', () {
    test('pago único: 1 sola cuota, se incorpora íntegra en la Nómina correspondiente', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 300000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      expect(renglon.descuentosProgramados, 300000);
      expect(renglon.descuentosProgramadosPendienteRevision, isFalse);
    });

    test('2 parcialidades: cada cuota se incorpora en su propia Nómina, nunca las dos juntas', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 70000,
        numeroCuotas: 2,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generadoAgosto = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonAgosto = (await nominaRepo.listarEmpleados(generadoAgosto.nomina.id)).single;
      expect(renglonAgosto.descuentosProgramados, 35000, reason: 'solo la cuota 1/2, la 2/2 todavía no vence');

      final generadoSeptiembre =
          (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglonSeptiembre = (await nominaRepo.listarEmpleados(generadoSeptiembre.nomina.id)).single;
      expect(renglonSeptiembre.descuentosProgramados, 35000, reason: 'ahora la cuota 2/2');
    });
  });

  group('3. Nunca se pierde un centavo', () {
    test(r'$1,000/3: al aplicarse las 3 cuotas (pagando 3 Nóminas completas) el saldo llega EXACTO a 0', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 3,
        fechaPrimeraCuota: DateTime(2026, 1, 20),
      );
      expect(descuento.saldoPendiente, 100000);

      for (final periodo in [
        (anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera),
        (anio: 2026, mes: 1, tipo: TipoPeriodoNomina.segunda),
        (anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera),
      ]) {
        final generado =
            (await generarNomina.ejecutar(anio: periodo.anio, mes: periodo.mes, tipo: periodo.tipo)) as GenerarNominaExitoso;
        await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
        final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
        await registrarPagoNomina.ejecutar(
          nominaId: generado.nomina.id,
          fechaPago: DateTime(periodo.anio, periodo.mes, 20),
          formaPago: 'transferencia',
          cuentaFinancieraId: await _cuentaDePrueba(db),
          aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
        );
      }

      final final_ = await descuentoRepo.obtenerPorId(descuento.id);
      expect(final_!.saldoPendiente, 0);
      expect(final_.estatus, 'liquidado');
    });
  });

  group('4-5. Botas', () {
    test(r'botas $700 → 2 cuotas de $350 se incorporan igual que un préstamo', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        tipo: 'botas',
        importeOriginal: 70000,
        numeroCuotas: 2,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramados, 35000);
    });

    test('botas con plan modificado (reprogramado antes de que venza ninguna cuota) usa el nuevo plan', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        tipo: 'botas',
        importeOriginal: 70000,
        numeroCuotas: 2,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final reprogramado = await reprogramarCuotas.ejecutar(
        descuentoProgramadoId: descuento.id,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
        motivo: 'Se decidió cobrar en una sola exhibición',
      );
      expect(reprogramado, isA<ReprogramarCuotasPendientesExitoso>());

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramados, 70000, reason: 'el plan reprogramado a 1 sola cuota reemplazó las 2 originales');
    });
  });

  group('6-7. Generar Nómina: correspondiente sí, futura no', () {
    test('una cuota con fecha futura (mes siguiente) NUNCA se incorpora en la Nómina actual', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 9, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      expect(renglon.descuentosProgramados, 0);
      final cuotas = await descuentoRepo.listarCuotasPendientesPorEmpleado(empleado.id);
      expect(cuotas.single.estatus, 'pendiente', reason: 'sigue disponible para la Nómina de septiembre');
    });

    test('un préstamo registrado DESPUÉS de generar la Nómina se incorpora al llamar Actualizar desde Personal', () async {
      final empleado = await crearEmpleadoDePrueba();

      // La Nómina ya existe (Borrador) SIN ningún préstamo todavía —
      // reproduce el reporte real: "puse unos préstamos pero al
      // generar la nueva nómina no los jaló".
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonInicial = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglonInicial.descuentosProgramados, 0);

      // El préstamo se registra DESPUÉS, con su primera cuota dentro
      // de la fecha de pago de esa misma Nómina ya generada.
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
      expect(resultado, isA<ActualizarNominaDesdePersonalExitoso>());

      final renglonFinal = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglonFinal.descuentosProgramados, 100000, reason: 'el préstamo nuevo debe incorporarse al actualizar desde Personal');
    });
  });

  group('9. Actualizar desde Personal no duplica la reserva', () {
    test('llamar actualizarDesdePersonal después de generar no reserva la cuota dos veces', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonInicial = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglonInicial.descuentosProgramados, 100000);

      await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);

      final renglonFinal = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglonFinal.descuentosProgramados, 100000, reason: 'nunca 200000 — la cuota ya reservada no se vuelve a resolver');

      final movimientos = await descuentoRepo.listarMovimientos(
        (await descuentoRepo.listarPorEmpleado(empleado.id)).single.id,
      );
      expect(
        movimientos.where((m) => m.tipoMovimiento == 'cuotaReservada'),
        hasLength(1),
        reason: 'un solo evento de reserva, no dos',
      );
    });
  });

  group('10-11. Independencia entre obligaciones y combinación en una misma Nómina', () {
    test('dos préstamos del mismo empleado se resuelven de forma independiente', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 50000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramados, 150000);

      final descuentos = await descuentoRepo.listarPorEmpleado(empleado.id);
      expect(descuentos, hasLength(2));
    });

    test('préstamo + botas en la misma Nómina se suman en descuentosProgramados', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        tipo: 'botas',
        importeOriginal: 70000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramados, 170000);
    });
  });

  group('12. Préstamo + DescuentoInventario + faltas combinados', () {
    test('los tres descuentos actúan juntos sobre el mismo neto, sin doble conteo', () async {
      final empleado = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 3000000);

      // Cadena de Inventario: artículo perdido con cargo de $200.
      final categoria =
          (await CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db)).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
              .categoria;
      final articulo = (await CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)))
              .ejecutar(categoriaId: categoria.id, nombre: 'PANTALON NEGRO COMANDO', manejaVariante: false, manejaSerie: false)
          as CrearArticuloExitoso)
          .articulo;
      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 8, 1));
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 2),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 8, 3),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleado.id,
      );

      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonInicial = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      // 2 faltas sobre sueldo administrativo $30,000/mes → $15,000/quincena.
      final actualizado = await actualizarRenglonNomina.ejecutar(nominaEmpleadoId: renglonInicial.id, faltas: 2);
      final renglon = (actualizado as ActualizarRenglonNominaExitoso).renglon;

      final salarioDiario = renglon.pagoPorDia;
      final totalEsperado = renglon.importeBase - (salarioDiario * 2) - renglon.descuentosInventario - renglon.descuentosProgramados;

      expect(renglon.descuentosInventario, 20000);
      expect(renglon.descuentosProgramados, 100000);
      expect(renglon.totalAPagar, totalEsperado);
    });
  });

  group('13-14. Reservada en Borrador, aplicada solo al pagar de verdad', () {
    test('Nómina Borrador: la cuota queda `reservada`, NUNCA `aplicada`', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera);

      final cuotas = await descuentoRepo.listarCuotas(descuento.id);
      expect(cuotas.single.estatus, 'reservada');
      final saldo = (await descuentoRepo.obtenerPorId(descuento.id))!.saldoPendiente;
      expect(saldo, 100000, reason: 'el saldo NO decrece solo por estar en una Nómina Borrador');
    });

    test('Nómina Cerrada: la cuota SIGUE `reservada` — cerrar no es pagar', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final cuotas = await descuentoRepo.listarCuotas(descuento.id);
      expect(cuotas.single.estatus, 'reservada');
    });

    test('pago real: la cuota pasa a `aplicada`, el saldo decrece y el padre se liquida si llega a 0', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );

      final cuotas = await descuentoRepo.listarCuotas(descuento.id);
      expect(cuotas.single.estatus, 'aplicada');
      expect(cuotas.single.fechaAplicacion, isNotNull);
      final final_ = await descuentoRepo.obtenerPorId(descuento.id);
      expect(final_!.saldoPendiente, 0);
      expect(final_.estatus, 'liquidado');
    });
  });

  group('15-16. Reversas: eliminar Borrador y eliminar cadena de prueba', () {
    test('eliminar una Nómina Borrador libera la cuota de vuelta a `pendiente`', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;

      await eliminarNominaFisicamente.ejecutar(nominaId: generado.nomina.id, motivo: MotivoEliminacionFisicaNomina.nominaDePrueba);

      final cuotas = await descuentoRepo.listarCuotas(descuento.id);
      expect(cuotas.single.estatus, 'pendiente');
      expect(cuotas.single.nominaEmpleadoId, isNull);
    });

    test('eliminar cadena de prueba de una Nómina PAGADA revierte la cuota (aplicada→pendiente) y restaura el saldo', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );
      expect((await descuentoRepo.obtenerPorId(descuento.id))!.estatus, 'liquidado');

      final r = await eliminarCadenaPrueba.ejecutar(
        nominaId: generado.nomina.id,
        motivo: MotivoCadenaPruebaNomina.nominaDePrueba,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(r, isA<EliminarCadenaPruebaNominaExitoso>());

      final cuotas = await descuentoRepo.listarCuotas(descuento.id);
      expect(cuotas.single.estatus, 'pendiente', reason: 'la Nómina entera desapareció, nunca se queda reservada a nada');
      expect(cuotas.single.nominaEmpleadoId, isNull);
      expect(cuotas.single.fechaAplicacion, isNull);
      final restaurado = await descuentoRepo.obtenerPorId(descuento.id);
      expect(restaurado!.saldoPendiente, 100000, reason: 'el saldo se reconstruye exacto');
      expect(restaurado.estatus, 'activo', reason: 'se des-liquida');
    });
  });

  group('17. Una cuota aplicada nunca puede aparecer en otra Nómina', () {
    test('tras pagarse, la cuota deja de ofrecerse como pendiente para una Nómina futura', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      final generadoAgosto = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generadoAgosto.nomina.id);
      final renglonAgosto = (await nominaRepo.listarEmpleados(generadoAgosto.nomina.id)).single;
      await registrarPagoNomina.ejecutar(
        nominaId: generadoAgosto.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglonAgosto.id, monto: renglonAgosto.totalAPagar)],
      );

      final generadoSeptiembre =
          (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.segunda)) as GenerarNominaExitoso;
      final renglonSeptiembre = (await nominaRepo.listarEmpleados(generadoSeptiembre.nomina.id)).single;

      expect(renglonSeptiembre.descuentosProgramados, 0, reason: 'la cuota ya pagada no vuelve a cobrarse');
      final pendientes = await descuentoRepo.listarCuotasPendientesPorEmpleado(empleado.id);
      expect(pendientes, isEmpty);
      expect((await descuentoRepo.obtenerPorId(descuento.id))!.estatus, 'liquidado');
    });
  });

  group('18. Baja laboral conserva el saldo', () {
    test('dar de baja al empleado NO cancela ni modifica su saldo pendiente', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 2,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      await empleadoRepo.registrarBajaLaboral(empleadoId: empleado.id, fechaBaja: DateTime(2026, 8, 25), motivo: 'renuncia');

      final tras = await descuentoRepo.obtenerPorId(descuento.id);
      expect(tras!.saldoPendiente, 100000);
      expect(tras.estatus, 'activo');
    });
  });

  group('19. Cancelación conserva el historial de lo ya recuperado', () {
    test(r'préstamo $3,000, recuperado $1,000 → cancelar conserva lo recuperado y solo condona el resto', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 300000,
        numeroCuotas: 3,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );
      expect((await descuentoRepo.obtenerPorId(descuento.id))!.saldoPendiente, 200000);

      final r = await cancelarSaldo.ejecutar(descuentoProgramadoId: descuento.id, motivo: 'Empleado liquidó en efectivo por fuera');
      expect(r, isA<CancelarSaldoDescuentoProgramadoExitoso>());

      final final_ = await descuentoRepo.obtenerPorId(descuento.id);
      expect(final_!.saldoPendiente, 0);
      expect(final_.estatus, 'cancelado');

      final cuotas = await descuentoRepo.listarCuotas(descuento.id);
      expect(cuotas.where((c) => c.estatus == 'aplicada'), hasLength(1), reason: 'la cuota ya cobrada conserva su historial intacto');
      expect(cuotas.where((c) => c.estatus == 'cancelada'), hasLength(2));
    });
  });

  group('20. Reprogramación solo toca cuotas futuras', () {
    test('una cuota ya aplicada nunca se toca al reprogramar el resto del plan', () async {
      final empleado = await crearEmpleadoDePrueba();
      final descuento = await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 200000,
        numeroCuotas: 4,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 8, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );
      final cuotaAplicadaAntes = (await descuentoRepo.listarCuotas(descuento.id)).firstWhere((c) => c.estatus == 'aplicada');

      final r = await reprogramarCuotas.ejecutar(
        descuentoProgramadoId: descuento.id,
        numeroCuotas: 2,
        fechaPrimeraCuota: DateTime(2026, 9, 5),
        motivo: 'Empleado pidió menos cuotas de mayor monto',
      );
      expect(r, isA<ReprogramarCuotasPendientesExitoso>());

      final cuotasFinales = await descuentoRepo.listarCuotas(descuento.id);
      final cuotaAplicadaDespues = cuotasFinales.firstWhere((c) => c.id == cuotaAplicadaAntes.id);
      expect(cuotaAplicadaDespues.estatus, 'aplicada');
      expect(cuotaAplicadaDespues.importeProgramado, cuotaAplicadaAntes.importeProgramado);

      final nuevasPendientes = cuotasFinales.where((c) => c.estatus == 'pendiente').toList();
      expect(nuevasPendientes, hasLength(2));
      expect(nuevasPendientes.fold<int>(0, (s, c) => s + c.importeProgramado), 150000, reason: 'saldo restante tras 1 cuota aplicada');
    });
  });

  group('22. Reprogramar un descuento NUNCA contamina a otro descuento del mismo renglón (bug real corregido, Etapa 0)', () {
    test(
      'mismo empleado, mismo renglón de Nómina, descuento A y descuento B, ambos con cuota `reservada` en ese renglón: '
      'reprogramar A no cambia NADA de la cuota/saldo/estatus/movimientos de B',
      () async {
        final empleado = await crearEmpleadoDePrueba();
        final descuentoA = await registrarPrestamoDePrueba(
          empleadoId: empleado.id,
          importeOriginal: 100000,
          numeroCuotas: 1,
          fechaPrimeraCuota: DateTime(2026, 8, 20),
        );
        final descuentoB = await registrarPrestamoDePrueba(
          empleadoId: empleado.id,
          tipo: 'botas',
          importeOriginal: 50000,
          numeroCuotas: 1,
          fechaPrimeraCuota: DateTime(2026, 8, 20),
        );

        // Ambos quedan `reservada` en el MISMO renglón de Nómina — el
        // escenario exacto donde `liberarCuotasDeRenglones` (llamado
        // internamente por reprogramar) filtraba solo por
        // `nominaEmpleadoId`, sin distinguir a qué descuento pertenecía
        // cada cuota.
        final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
        final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
        expect(renglon.descuentosProgramados, 150000, reason: 'A + B ya reservados en el mismo renglón');

        final cuotaBAntes = (await descuentoRepo.listarCuotas(descuentoB.id)).single;
        expect(cuotaBAntes.estatus, 'reservada');
        expect(cuotaBAntes.nominaEmpleadoId, renglon.id);
        final movimientosBAntes = await descuentoRepo.listarMovimientos(descuentoB.id);

        final resultado = await reprogramarCuotas.ejecutar(
          descuentoProgramadoId: descuentoA.id,
          numeroCuotas: 2,
          fechaPrimeraCuota: DateTime(2026, 9, 5),
          motivo: 'Empleado pidió dividir el préstamo A en 2 cuotas',
        );
        expect(resultado, isA<ReprogramarCuotasPendientesExitoso>());

        // --- B: absolutamente nada debe haber cambiado.
        final cuotaBDespues = (await descuentoRepo.listarCuotas(descuentoB.id)).single;
        expect(cuotaBDespues.id, cuotaBAntes.id, reason: 'la cuota de B nunca se reemplaza');
        expect(cuotaBDespues.estatus, 'reservada', reason: 'B NUNCA se des-reserva por reprogramar A');
        expect(cuotaBDespues.nominaEmpleadoId, renglon.id, reason: 'B sigue vinculada al mismo renglón de Nómina');
        expect(cuotaBDespues.numeroCuota, cuotaBAntes.numeroCuota);
        expect(cuotaBDespues.importeProgramado, cuotaBAntes.importeProgramado);
        expect(cuotaBDespues.fechaProgramada, cuotaBAntes.fechaProgramada);

        final descuentoBDespues = await descuentoRepo.obtenerPorId(descuentoB.id);
        expect(descuentoBDespues!.saldoPendiente, 50000, reason: 'saldo de B intacto');
        expect(descuentoBDespues.estatus, 'activo');

        final movimientosBDespues = await descuentoRepo.listarMovimientos(descuentoB.id);
        expect(
          movimientosBDespues.length,
          movimientosBAntes.length,
          reason: 'cero movimientos nuevos en B — ni "cuotaRevertida" ni ningún otro',
        );

        // --- Confirma que A sí se reprogramó (la operación en sí funcionó):
        // la cuota vieja (1/1, `reservada`) queda `cancelada` y el plan
        // nuevo (2 cuotas) nace `pendiente` — nunca `reservada` a este
        // renglón, que es justo lo que prueba que A sí se liberó.
        final cuotasA = await descuentoRepo.listarCuotas(descuentoA.id);
        expect(cuotasA.where((c) => c.estatus == 'reservada'), isEmpty, reason: 'A sí se liberó/reprogramó — ninguna cuota de A sigue reservada');
        expect(cuotasA.where((c) => c.estatus == 'pendiente'), hasLength(2), reason: 'el nuevo plan de A (2 cuotas) queda pendiente');
      },
    );
  });

  group('21. Deducciones mayores al neto bloquean el cierre', () {
    test('una cuota que no cabe en el neto disponible marca pendienteRevision y bloquea CerrarNominaUseCase', () async {
      final empleado = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 100000);
      // Neto quincenal ≈ $500.00 (50000 centavos) — un préstamo de
      // $1,000.00 en 1 sola cuota no cabe.
      await registrarPrestamoDePrueba(
        empleadoId: empleado.id,
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 8, 20),
      );

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglon.descuentosProgramadosPendienteRevision, isTrue);
      expect(renglon.descuentosProgramados, 0, reason: 'no se aplicó nada parcial — o cabe completa o se queda pendiente');

      final resultadoCierre = await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      expect(resultadoCierre, isA<CerrarNominaDescuentosProgramadosPendientes>());
      final sinCerrar = await nominaRepo.obtenerPorId(generado.nomina.id);
      expect(sinCerrar!.estatus, 'borrador');
    });
  });
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
