// Dos límites del dominio, actualizados a la Rebanada 2.
//
// 1. Vender un eventual **sí** genera cobranza (schemaVersion 88) —
//    exactamente una CxC— pero sigue SIN pasar por la agenda comercial:
//    cero `DocumentoPorEmitir`.
// 2. La eliminación física es Maestro-only y se niega en cuanto hay
//    huella financiera.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/finalizar_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/revertir_pago_cobertura_servicio_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late ServicioEventualRepositoryImpl repo;
  late CrearServicioEventualUseCase crear;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late AgregarCostoServicioEventualUseCase agregarCosto;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late RevertirPagoCoberturaServicioEventualUseCase revertirPago;
  late FinalizarServicioEventualUseCase finalizar;
  late EliminarServicioEventualFisicamenteUseCase eliminar;

  late ServicioEventualData eventual;
  late ServicioEventualParticipanteData participante;
  late CuentaFinancieraData cuenta;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db));

    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), EntidadFiscalRepositoryImpl(db));
    agregarParticipante = AgregarParticipanteServicioEventualUseCase(
      repo,
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
    agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
    agregarCosto = AgregarCostoServicioEventualUseCase(repo);
    pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);
    revertirPago = RevertirPagoCoberturaServicioEventualUseCase(repo);
    finalizar = FinalizarServicioEventualUseCase(repo);
    eliminar = EliminarServicioEventualFisicamenteUseCase(repo);

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
      requiereFactura: true,
      // Desde la v90 vender con factura exige receptor fiscal.
      solicitanteRazonSocial: 'Promotora Norte S.A. de C.V.',
      solicitanteRfc: 'PNO010101AB1',
      solicitanteCodigoPostalFiscal: '64000',
      metodoCobro: MetodoPagoCobro.ppd,
    )) as CrearServicioEventualExitoso)
        .servicioEventual;

    participante = ((await agregarParticipante.ejecutar(
      servicioEventualId: eventual.id,
      nombreExterno: 'Refuerzo externo',
    )) as AgregarParticipanteServicioEventualExitoso)
        .participante;
  });

  tearDown(() => db.close());

  Future<ServicioEventualCoberturaData> nuevaCobertura() async {
    return ((await agregarCobertura.ejecutar(
      servicioEventualId: eventual.id,
      participanteId: participante.id,
      fecha: DateTime(2026, 5, 1),
      horaInicioMinutos: 18 * 60,
      horaFinMinutos: 2 * 60,
      importeAcordado: 250000,
    )) as AgregarCoberturaServicioEventualExitoso)
        .cobertura;
  }

  test('el ciclo completo genera UNA cuenta por cobrar y ningún documento por emitir', () async {
    final cobertura = await nuevaCobertura();
    await agregarCosto.ejecutar(
      servicioEventualId: eventual.id,
      concepto: 'Traslado',
      monto: 90000,
      fecha: DateTime(2026, 5, 1),
    );
    await pagarCobertura.ejecutar(
      coberturaId: cobertura.id,
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
    );
    await finalizar.ejecutar(servicioEventualId: eventual.id);

    // Exactamente una CxC, de origen eventual, por el importe de la
    // venta — ni dos, ni cero.
    final cuentas = await db.select(db.cuentaPorCobrar).get();
    expect(cuentas, hasLength(1));
    expect(cuentas.single.servicioEventualId, eventual.id);
    expect(cuentas.single.documentoPorEmitirId, isNull);
    expect(cuentas.single.importeEmitido, 5000000);

    // La cobranza eventual NO pasa por la agenda comercial: no se
    // inventa un DocumentoPorEmitir para sostenerla.
    expect(await db.select(db.documentoPorEmitir).get(), isEmpty);
    // Nadie ha cobrado todavía.
    expect(await db.select(db.pago).get(), isEmpty);
    expect(await db.select(db.ingreso).get(), isEmpty);
    // Y el gasto sí ocurrió.
    expect(await db.select(db.egreso).get(), hasLength(1));
  });

  group('Eliminación física', () {
    test('exige motivo', () async {
      expect(
        await eliminar.ejecutar(servicioEventualId: eventual.id, motivo: '  '),
        isA<EliminarServicioEventualFisicamenteMotivoRequerido>(),
      );
      expect(await repo.obtenerPorId(eventual.id), isNotNull);
    });

    test('se niega mientras haya un pago registrado', () async {
      final cobertura = await nuevaCobertura();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );

      final resultado = await eliminar.ejecutar(
        servicioEventualId: eventual.id,
        motivo: 'Capturado por error',
      );
      expect(resultado, isA<EliminarServicioEventualFisicamenteTieneDependencias>());
      expect(await repo.obtenerPorId(eventual.id), isNotNull);
    });

    test('tras revertir el pago sí procede, y deja rastro en la bitácora de eliminaciones', () async {
      final cobertura = await nuevaCobertura();
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuenta.id,
      );
      await revertirPago.ejecutar(coberturaId: cobertura.id, motivo: 'Error de captura');

      final resultado = await eliminar.ejecutar(
        servicioEventualId: eventual.id,
        motivo: 'Evento capturado dos veces',
      );
      expect(resultado, isA<EliminarServicioEventualFisicamenteExitoso>());

      expect(await repo.obtenerPorId(eventual.id), isNull);
      expect(await db.select(db.servicioEventualCobertura).get(), isEmpty);
      expect(await db.select(db.servicioEventualParticipante).get(), isEmpty);
      expect(await db.select(db.servicioEventualEvento).get(), isEmpty);

      final bitacora = await (db.select(db.eliminacionFisicaEvento)
            ..where((t) => t.tipoEntidad.equals('servicioEventual')))
          .get();
      expect(bitacora, hasLength(1));
      expect(bitacora.single.entidadIdOriginal, eventual.id);
      expect(bitacora.single.motivo, 'Evento capturado dos veces');
      // El snapshot conserva lo que se borró.
      expect(bitacora.single.snapshotJson, contains('EVT-000001'));
    });

    test('un eventual inexistente no se inventa', () async {
      expect(
        await eliminar.ejecutar(servicioEventualId: 'no-existe', motivo: 'x'),
        isA<EliminarServicioEventualFisicamenteNoExiste>(),
      );
    });
  });
}
