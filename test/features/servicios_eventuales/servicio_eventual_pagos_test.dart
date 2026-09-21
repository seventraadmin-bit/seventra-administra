// Servicios Eventuales — Rebanada 1, efectos financieros reales.
//
// El invariante que se protege: pagar produce **exactamente uno** de
// los dos hechos —un Egreso (Cuenta) o un cargo a tarjeta (TDC)— y
// nunca ambos ni ninguno; revertir el pago deshace ese hecho
// exactamente una vez y devuelve la cobertura a `programada`, **sin**
// cancelarla.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show TipoMovimientoDeuda;
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/revertir_pago_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/revertir_pago_costo_servicio_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late DeudaRepositoryImpl deudaRepo;
  late ServicioEventualRepositoryImpl repo;

  late CrearServicioEventualUseCase crear;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late CancelarCoberturaServicioEventualUseCase cancelarCobertura;
  late AgregarCostoServicioEventualUseCase agregarCosto;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late RevertirPagoCoberturaServicioEventualUseCase revertirPagoCobertura;
  late PagarCostoServicioEventualUseCase pagarCosto;
  late RevertirPagoCostoServicioEventualUseCase revertirPagoCosto;

  late ServicioEventualData eventual;
  late ServicioEventualParticipanteData participante;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db));

    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), EntidadFiscalRepositoryImpl(db));
    agregarParticipante = AgregarParticipanteServicioEventualUseCase(
      repo,
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
    agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
    cancelarCobertura = CancelarCoberturaServicioEventualUseCase(repo);
    agregarCosto = AgregarCostoServicioEventualUseCase(repo);
    pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);
    revertirPagoCobertura = RevertirPagoCoberturaServicioEventualUseCase(repo);
    pagarCosto = PagarCostoServicioEventualUseCase(repo, deudaRepo);
    revertirPagoCosto = RevertirPagoCostoServicioEventualUseCase(repo);

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

  Future<CuentaFinancieraData> crearCuenta() {
    return db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 100000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<DeudaData> crearTarjeta({int limite = 5000000, int saldoActual = 0}) {
    return db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-TDC',
            nombre: 'TDC Corporativa',
            tipo: 'tarjetaCredito',
            saldoActual: saldoActual,
            tarjetaLimiteCredito: Value(limite),
          ),
        );
  }

  Future<ServicioEventualCoberturaData> nuevaCobertura({int importe = 250000}) async {
    final resultado = await agregarCobertura.ejecutar(
      servicioEventualId: eventual.id,
      participanteId: participante.id,
      fecha: DateTime(2026, 5, 1),
      horaInicioMinutos: 18 * 60,
      horaFinMinutos: 2 * 60,
      importeAcordado: importe,
    );
    return (resultado as AgregarCoberturaServicioEventualExitoso).cobertura;
  }

  Future<ServicioEventualCostoData> nuevoCosto({int monto = 90000}) async {
    final resultado = await agregarCosto.ejecutar(
      servicioEventualId: eventual.id,
      concepto: 'Traslado de personal',
      monto: monto,
      fecha: DateTime(2026, 5, 1),
    );
    return (resultado as AgregarCostoServicioEventualExitoso).costo;
  }

  group('Pago desde Cuenta', () {
    test('crea exactamente un Egreso y cero cargos a tarjeta', () async {
      final cuenta = await crearCuenta();
      final cobertura = await nuevaCobertura();

      final resultado = await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );
      expect(resultado, isA<PagarCoberturaServicioEventualExitoso>());

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1));
      expect(egresos.single.monto, 250000);
      expect(egresos.single.cuentaFinancieraId, cuenta.id);
      expect(egresos.single.deudaId, isNull);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);

      final guardada = (await repo.obtenerCobertura(cobertura.id))!;
      expect(guardada.estatus, EstatusEjecucionServicioEventual.pagada.name);
      expect(guardada.egresoId, egresos.single.id);
      expect(guardada.deudaId, isNull);
    });

    test('un costo adicional paga aparte, con su propio Egreso', () async {
      final cuenta = await crearCuenta();
      await pagarCobertura.ejecutar(
        coberturaId: (await nuevaCobertura()).id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );
      await pagarCosto.ejecutar(
        costoId: (await nuevoCosto()).id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );

      // Dos Egresos, nunca uno fusionado: mismo criterio que los
      // costos adicionales de Tiempo Extra.
      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(2));
      expect(egresos.map((e) => e.monto).toSet(), {250000, 90000});
      expect(egresos.map((e) => e.folioEgreso).toSet().length, 2);
    });
  });

  group('Pago con tarjeta', () {
    test('sube el saldo de la Deuda y NO crea Egreso', () async {
      final tarjeta = await crearTarjeta();
      final cobertura = await nuevaCobertura();

      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.tarjeta.name,
        deudaIdTarjeta: tarjeta.id,
      );

      expect(await db.select(db.egreso).get(), isEmpty);
      final movimientos = await db.select(db.movimientoDeuda).get();
      expect(movimientos, hasLength(1));
      expect(movimientos.single.tipo, TipoMovimientoDeuda.cargoCompra.name);
      expect(movimientos.single.importe, 250000);
      expect(movimientos.single.servicioEventualCoberturaId, cobertura.id);

      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 250000);
      final guardada = (await repo.obtenerCobertura(cobertura.id))!;
      expect(guardada.deudaId, tarjeta.id);
      expect(guardada.egresoId, isNull);
    });

    test('una tarjeta sin límite capturado se rechaza sin escribir nada', () async {
      final tarjeta = await db.into(db.deuda).insertReturning(
            DeudaCompanion.insert(folio: 'DEU-2', nombre: 'Sin límite', tipo: 'tarjetaCredito', saldoActual: 0),
          );
      final cobertura = await nuevaCobertura();
      expect(
        await pagarCobertura.ejecutar(
          coberturaId: cobertura.id,
          formaPago: FormaPago.tarjeta.name,
          deudaIdTarjeta: tarjeta.id,
        ),
        isA<PagarCoberturaServicioEventualTarjetaSinLimiteConfigurado>(),
      );
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
      expect((await repo.obtenerCobertura(cobertura.id))!.estatus,
          EstatusEjecucionServicioEventual.programada.name);
    });

    test('excederse del crédito disponible se rechaza y dice cuánto queda', () async {
      final tarjeta = await crearTarjeta(limite: 100000);
      final cobertura = await nuevaCobertura(importe: 250000);
      final resultado = await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.tarjeta.name,
        deudaIdTarjeta: tarjeta.id,
      );
      expect(resultado, isA<PagarCoberturaServicioEventualTarjetaExcedeLimite>());
      expect((resultado as PagarCoberturaServicioEventualTarjetaExcedeLimite).disponible, 100000);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });
  });

  group('Origen financiero obligatorio', () {
    test('sin cuenta ni tarjeta se rechaza', () async {
      final cobertura = await nuevaCobertura();
      expect(
        await pagarCobertura.ejecutar(coberturaId: cobertura.id, formaPago: FormaPago.efectivo.name),
        isA<PagarCoberturaServicioEventualOrigenFinancieroRequerido>(),
      );
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('cuenta Y tarjeta a la vez se rechaza', () async {
      final cuenta = await crearCuenta();
      final tarjeta = await crearTarjeta();
      final cobertura = await nuevaCobertura();
      expect(
        await pagarCobertura.ejecutar(
          coberturaId: cobertura.id,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuenta.id,
          deudaIdTarjeta: tarjeta.id,
        ),
        isA<PagarCoberturaServicioEventualOrigenFinancieroAmbiguo>(),
      );
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    test('un costo exige el mismo origen que una cobertura', () async {
      final costo = await nuevoCosto();
      expect(
        await pagarCosto.ejecutar(costoId: costo.id, formaPago: FormaPago.efectivo.name),
        isA<PagarCostoServicioEventualOrigenFinancieroRequerido>(),
      );
    });
  });

  group('Reversión', () {
    test('cancela el Egreso, vuelve a programada y permite pagar de nuevo', () async {
      final cuenta = await crearCuenta();
      final cobertura = await nuevaCobertura();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );

      final resultado = await revertirPagoCobertura.ejecutar(
        coberturaId: cobertura.id,
        motivo: 'Se pagó de la cuenta equivocada',
      );
      expect(resultado, isA<RevertirPagoCoberturaServicioEventualExitoso>());

      final revertida = (await repo.obtenerCobertura(cobertura.id))!;
      // Revertir el pago NO cancela la cobertura.
      expect(revertida.estatus, EstatusEjecucionServicioEventual.programada.name);
      expect(revertida.egresoId, isNull);
      expect(revertida.deudaId, isNull);
      expect((await db.select(db.egreso).get()).single.estatus, 'cancelado');

      // Y se puede volver a pagar, con otro origen.
      final tarjeta = await crearTarjeta();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.tarjeta.name,
        deudaIdTarjeta: tarjeta.id,
      );
      expect((await repo.obtenerCobertura(cobertura.id))!.deudaId, tarjeta.id);
      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 250000);
    });

    test('revertir un cargo a tarjeta devuelve el crédito exactamente una vez', () async {
      final tarjeta = await crearTarjeta();
      final cobertura = await nuevaCobertura();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.tarjeta.name,
        deudaIdTarjeta: tarjeta.id,
      );
      await revertirPagoCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'Error de captura');
      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 0);

      // Segunda reversión: el caso de uso corta antes por estatus, así
      // que el crédito nunca se devuelve dos veces.
      expect(
        await revertirPagoCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'Otra vez'),
        isA<RevertirPagoCoberturaServicioEventualNoPagada>(),
      );
      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 0);
    });

    test('revertir exige motivo', () async {
      final cuenta = await crearCuenta();
      final cobertura = await nuevaCobertura();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );
      expect(
        await revertirPagoCobertura.ejecutar(coberturaId: cobertura.id, motivo: '  '),
        isA<RevertirPagoCoberturaServicioEventualMotivoRequerido>(),
      );
      expect((await repo.obtenerCobertura(cobertura.id))!.estatus,
          EstatusEjecucionServicioEventual.pagada.name);
    });

    test('tras revertir, la cobertura sí se puede cancelar', () async {
      final cuenta = await crearCuenta();
      final cobertura = await nuevaCobertura();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );
      await revertirPagoCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'Se canceló el turno');
      expect(
        await cancelarCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'No se presentó'),
        isA<CancelarCoberturaServicioEventualExitoso>(),
      );
    });

    test('revertir el pago de un costo se comporta igual', () async {
      final tarjeta = await crearTarjeta();
      final costo = await nuevoCosto();
      await pagarCosto.ejecutar(
        costoId: costo.id,
        formaPago: FormaPago.tarjeta.name,
        deudaIdTarjeta: tarjeta.id,
      );
      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 90000);

      await revertirPagoCosto.ejecutar(costoId: costo.id, motivo: 'Se cargó a la tarjeta equivocada');
      final revertido = (await repo.obtenerCosto(costo.id))!;
      expect(revertido.estatus, EstatusEjecucionServicioEventual.programada.name);
      expect(revertido.deudaId, isNull);
      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 0);
    });
  });

  test('pagar dos veces no duplica el gasto', () async {
    final cuenta = await crearCuenta();
    final cobertura = await nuevaCobertura();
    await pagarCobertura.ejecutar(
      coberturaId: cobertura.id,
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
    );
    expect(
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      ),
      isA<PagarCoberturaServicioEventualYaPagada>(),
    );
    expect(await db.select(db.egreso).get(), hasLength(1));
  });

  test('una cobertura cancelada no se paga', () async {
    final cuenta = await crearCuenta();
    final cobertura = await nuevaCobertura();
    await cancelarCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'No se presentó');
    expect(
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      ),
      isA<PagarCoberturaServicioEventualCancelada>(),
    );
    expect(await db.select(db.egreso).get(), isEmpty);
  });
}
