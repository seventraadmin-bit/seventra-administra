// Servicios Eventuales — el Egreso de un eventual es un Egreso
// AUTOMÁTICO desde el día uno.
//
// Este archivo existe porque el mismo hueco ya se abrió tres veces
// (Préstamos, Vehículos, Telefonía): el dominio nuevo creaba Egresos
// pero nadie los reconocía, así que Finanzas los trataba como manuales
// —los dejaba corregir y cancelar por encima del dominio que los
// creó— y Reportes los contaba como "manual".

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresoRepo;
  late ServicioEventualRepositoryImpl repo;
  late ObtenerOrigenAutomaticoEgresoUseCase obtenerOrigen;
  late ClasificarEgresosPorOrigenUseCase clasificar;
  late CorregirEgresoUseCase corregirEgreso;
  late CancelarEgresoUseCase cancelarEgreso;

  late CrearServicioEventualUseCase crear;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late AgregarCostoServicioEventualUseCase agregarCosto;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late PagarCostoServicioEventualUseCase pagarCosto;

  late ServicioEventualData eventual;
  late ServicioEventualParticipanteData participante;
  late CuentaFinancieraData cuenta;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    repo = ServicioEventualRepositoryImpl(
      db,
      egresoRepo,
      deudaRepo,
      codigoSecuencia,
      CuentaPorCobrarRepositoryImpl(db),
      PagoRepositoryImpl(db),
    );

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final descuentoRepo = DescuentoProgramadoRepositoryImpl(db, egresoRepo, codigoSecuencia);
    final compraRepo = CompraRepositoryImpl(
      db,
      InventarioRepositoryImpl(db),
      ArticuloRepositoryImpl(db),
      egresoRepo,
      deudaRepo,
    );
    final tiempoExtraRepo =
        TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    final recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia);
    final lineaRepo = LineaTelefonicaRepositoryImpl(
      db,
      AsignacionLineaTelefonicaRepositoryImpl(db),
      LineaTelefonicaEquipoRepositoryImpl(
        db,
        AsignacionLineaTelefonicaRepositoryImpl(db),
        AsignacionRepositoryImpl(db),
      ),
    );

    obtenerOrigen = ObtenerOrigenAutomaticoEgresoUseCase(
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      deudaRepo,
      descuentoRepo,
      VehiculoMantenimientoRepositoryImpl(db),
      VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db)),
      recargaRepo,
      lineaRepo,
      repo,
    );
    clasificar = ClasificarEgresosPorOrigenUseCase(
      egresoRepo,
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      recargaRepo,
      deudaRepo,
      descuentoRepo,
      VehiculoMantenimientoRepositoryImpl(db),
      repo,
    );
    corregirEgreso = CorregirEgresoUseCase(egresoRepo, obtenerOrigen, deudaRepo);
    cancelarEgreso = CancelarEgresoUseCase(egresoRepo, obtenerOrigen);

    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), EntidadFiscalRepositoryImpl(db));
    agregarParticipante = AgregarParticipanteServicioEventualUseCase(repo, empleadoRepo);
    agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
    agregarCosto = AgregarCostoServicioEventualUseCase(repo);
    pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);
    pagarCosto = PagarCostoServicioEventualUseCase(repo, deudaRepo);

    cuenta = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 100000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );

    eventual = ((await crear.ejecutar(
      nombre: 'Concierto plaza',
      fechaHoraInicio: DateTime(2026, 5, 1, 18),
      fechaHoraFin: DateTime(2026, 5, 2, 2),
      importeAcordado: 5000000,
      tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      solicitanteNombre: 'Promotora Norte',
    )) as CrearServicioEventualExitoso)
        .servicioEventual;

    participante = ((await agregarParticipante.ejecutar(
      servicioEventualId: eventual.id,
      nombreExterno: 'Refuerzo externo',
    )) as AgregarParticipanteServicioEventualExitoso)
        .participante;
  });

  tearDown(() => db.close());

  Future<String> pagarUnaCobertura({int importe = 250000}) async {
    final cobertura = ((await agregarCobertura.ejecutar(
      servicioEventualId: eventual.id,
      participanteId: participante.id,
      fecha: DateTime(2026, 5, 1),
      horaInicioMinutos: 18 * 60,
      horaFinMinutos: 2 * 60,
      importeAcordado: importe,
    )) as AgregarCoberturaServicioEventualExitoso)
        .cobertura;
    await pagarCobertura.ejecutar(
      coberturaId: cobertura.id,
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
    );
    return (await repo.obtenerCobertura(cobertura.id))!.egresoId!;
  }

  Future<String> pagarUnCosto({int monto = 90000}) async {
    final costo = ((await agregarCosto.ejecutar(
      servicioEventualId: eventual.id,
      concepto: 'Traslado de personal',
      monto: monto,
      fecha: DateTime(2026, 5, 1),
    )) as AgregarCostoServicioEventualExitoso)
        .costo;
    await pagarCosto.ejecutar(
      costoId: costo.id,
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
    );
    return (await repo.obtenerCosto(costo.id))!.egresoId!;
  }

  test('el Egreso de una cobertura tiene origen ServicioEventual, con su folio', () async {
    final egresoId = await pagarUnaCobertura();
    final origen = await obtenerOrigen.ejecutar(egresoId);

    expect(origen, isA<OrigenAutomaticoEgresoServicioEventual>());
    final se = origen! as OrigenAutomaticoEgresoServicioEventual;
    expect(se.servicioEventualId, eventual.id);
    expect(se.folio, eventual.folio);
    expect(se.coberturaId, isNotNull);
    expect(se.costoId, isNull);
  });

  test('el Egreso de un costo distingue costo de cobertura', () async {
    final egresoId = await pagarUnCosto();
    final se = (await obtenerOrigen.ejecutar(egresoId))! as OrigenAutomaticoEgresoServicioEventual;
    expect(se.costoId, isNotNull);
    expect(se.coberturaId, isNull);
  });

  test('ese Egreso NO se puede corregir ni cancelar desde Finanzas', () async {
    final egresoId = await pagarUnaCobertura();

    expect(
      await corregirEgreso.ejecutar(egresoId: egresoId, monto: 999999, motivo: 'Intento'),
      isA<CorregirEgresoOrigenAutomatico>(),
    );
    expect(
      await cancelarEgreso.ejecutar(egresoId: egresoId, motivo: 'Intento'),
      isA<CancelarEgresoOrigenAutomatico>(),
    );

    // Y el Egreso siguió intacto: la protección corta antes de escribir.
    final egreso = (await egresoRepo.obtenerPorId(egresoId))!;
    expect(egreso.monto, 250000);
    expect(egreso.estatus, 'registrado');
  });

  test('Reportes lo clasifica como servicioEventual, nunca como manual', () async {
    await pagarUnaCobertura();
    await pagarUnCosto();

    final resumen = await clasificar.ejecutar();
    expect(resumen.totalServicioEventual, 340000);
    expect(resumen.totalManual, 0);
    expect(
      resumen.detalle.map((e) => e.origen).toSet(),
      {OrigenEgreso.servicioEventual},
    );
  });

  test('un pago con tarjeta no aparece en la clasificación: no genera Egreso', () async {
    final tarjeta = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-TDC',
            nombre: 'TDC',
            tipo: 'tarjetaCredito',
            saldoActual: 0,
            tarjetaLimiteCredito: const Value(5000000),
          ),
        );
    final cobertura = ((await agregarCobertura.ejecutar(
      servicioEventualId: eventual.id,
      participanteId: participante.id,
      fecha: DateTime(2026, 5, 1),
      horaInicioMinutos: 18 * 60,
      horaFinMinutos: 2 * 60,
      importeAcordado: 250000,
    )) as AgregarCoberturaServicioEventualExitoso)
        .cobertura;
    await pagarCobertura.ejecutar(
      coberturaId: cobertura.id,
      formaPago: FormaPago.tarjeta.name,
      deudaIdTarjeta: tarjeta.id,
    );

    final resumen = await clasificar.ejecutar();
    expect(resumen.detalle, isEmpty);
    expect(resumen.totalServicioEventual, 0);
  });

  test('un Egreso ajeno al dominio sigue siendo manual', () async {
    await db.into(db.egreso).insert(
          EgresoCompanion.insert(
            folioEgreso: 'EGR-999999',
            monto: 10000,
            fecha: DateTime(2026, 5, 1),
            formaPago: FormaPago.transferencia.name,
            concepto: 'Papelería',
            cuentaFinancieraId: Value(cuenta.id),
          ),
        );
    final resumen = await clasificar.ejecutar();
    expect(resumen.totalManual, 10000);
    expect(resumen.totalServicioEventual, 0);
    expect(await obtenerOrigen.ejecutar(resumen.detalle.single.egreso.id), isNull);
  });
}
