// Reconciliación de eventuales cancelados ANTES de la v90.
//
// El caso real (EVT-000001 en la base de la prueba manual): 8,000 + IVA,
// cobro de 8,000, "Cancelar evento" con la implementación vieja. El
// evento quedó cancelado y la CxC, el Pago, su Aplicación, el Ingreso
// ING-000019 y los 8,000 en BBVA siguieron vivos.
//
// Para reproducir ese estado se usa `cambiarEstatus(cancelado)` del
// repositorio: es EXACTAMENTE lo único que hacía la cancelación vieja.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart'
    show EstatusAplicacionPago, EstatusPago, FormaPago;
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/reconciliar_anulaciones_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late ServicioEventualRepositoryImpl repo;
  late PagoRepositoryImpl pagoRepo;
  late CuentaFinancieraRepositoryImpl cuentasFinancieras;
  late CrearServicioEventualUseCase crear;
  late CancelarServicioEventualUseCase anularNuevo;
  late ReconciliarAnulacionesServicioEventualUseCase reconciliar;
  late RegistrarDocumentoFiscalEventualUseCase facturar;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late CuentaFinancieraData bbva;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    final complementoRepo = ComplementoPagoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, cuentaRepo, pagoRepo);
    final documentoRepo = ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo);
    cuentasFinancieras = CuentaFinancieraRepositoryImpl(db);

    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), entidadFiscalRepo);
    anularNuevo = CancelarServicioEventualUseCase(repo, documentoRepo, complementoRepo);
    reconciliar = ReconciliarAnulacionesServicioEventualUseCase(repo, documentoRepo, complementoRepo);
    facturar = RegistrarDocumentoFiscalEventualUseCase(documentoRepo, repo, cuentaRepo, entidadFiscalRepo);
    agregarParticipante = AgregarParticipanteServicioEventualUseCase(
      repo,
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
    agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
    pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);

    bbva = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA Empresarial',
            tipo: 'banco',
            saldoInicial: 0,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> saldoBbva() => cuentasFinancieras.calcularSaldo(bbva.id);

  /// 8,000 + IVA con factura PUE y cobro inmediato de 8,000 a BBVA —
  /// la forma exacta de EVT-000001.
  Future<CrearServicioEventualExitoso> venderComoEvt1({int? cobro = 800000, bool conFactura = true}) async {
    return await crear.ejecutar(
      nombre: 'Posada',
      fechaHoraInicio: DateTime(2026, 9, 17, 18),
      fechaHoraFin: DateTime(2026, 9, 18, 2),
      importeAcordado: 800000,
      tratamientoIva: TratamientoIva.masIva,
      tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      solicitanteNombre: 'Juan del comité',
      requiereFactura: conFactura,
      metodoCobro: conFactura ? MetodoPagoCobro.pue : MetodoPagoCobro.noAplica,
      solicitanteRazonSocial: conFactura ? 'Administradora Bosques S.A. de C.V.' : null,
      solicitanteRfc: conFactura ? 'ABO010101AA1' : null,
      solicitanteCodigoPostalFiscal: conFactura ? '06700' : null,
      cobroInmediato: cobro == null
          ? null
          : CobroInmediatoServicioEventual(
              monto: cobro,
              fechaPago: DateTime(2026, 9, 17),
              formaPago: FormaPago.transferencia.name,
              cuentaFinancieraId: bbva.id,
            ),
    ) as CrearServicioEventualExitoso;
  }

  /// La cancelación VIEJA, tal cual: sólo `cambiarEstatus`.
  Future<void> cancelarComoAntesDelFix(String id) => repo.cambiarEstatus(
        servicioEventualId: id,
        estatus: EstatusServicioEventual.cancelado,
        motivo: 'PRUEBASdd',
      );

  /// Todo lo que la reconciliación puede tocar, para comparar antes y
  /// después fila por fila.
  Future<String> fotografia() async {
    final partes = <String>[
      for (final e in await db.select(db.servicioEventual).get()) 'EV ${e.id} ${e.estatus}',
      for (final c in await db.select(db.cuentaPorCobrar).get()) 'CXC ${c.id} ${c.estatus} ${c.saldoPendiente}',
      for (final a in await db.select(db.aplicacionPago).get()) 'APL ${a.id} ${a.estatus}',
      for (final p in await db.select(db.pago).get()) 'PAG ${p.id} ${p.estatus} ${p.montoAplicado}',
      for (final i in await db.select(db.ingreso).get()) 'ING ${i.id} ${i.estatus}',
      for (final g in await db.select(db.egreso).get()) 'EGR ${g.id} ${g.estatus}',
      for (final c in await db.select(db.servicioEventualCobertura).get()) 'COB ${c.id} ${c.estatus}',
      'EVENTOS ${(await db.select(db.servicioEventualEvento).get()).length}',
      'SALDO ${await saldoBbva()}',
    ]..sort();
    return partes.join('\n');
  }

  group('El caso EVT-000001', () {
    test('reproducido: cancelado con la implementación vieja, el dinero sigue vivo', () async {
      final venta = await venderComoEvt1();
      await cancelarComoAntesDelFix(venta.servicioEventual.id);

      // El estado exacto que se encontró en la base de la prueba manual.
      expect((await db.select(db.servicioEventual).get()).single.estatus, 'cancelado');
      final cuenta = (await db.select(db.cuentaPorCobrar).get()).single;
      expect(cuenta.estatus, EstatusCuentaPorCobrar.parcial.name);
      expect(cuenta.saldoPendiente, 128000);
      expect((await db.select(db.aplicacionPago).get()).single.estatus, EstatusAplicacionPago.aplicada.name);
      expect((await db.select(db.pago).get()).single.estatus, EstatusPago.registrado.name);
      expect((await db.select(db.ingreso).get()).single.estatus, EstatusIngreso.registrado.name);
      expect(await saldoBbva(), 800000);
    });

    test('reconciliado: queda EXACTAMENTE como la cancelación nueva', () async {
      // Dos gemelos: uno cancelado con la semántica vieja y reconciliado,
      // otro cancelado directamente con la nueva. Tienen que coincidir.
      final viejo = await venderComoEvt1();
      await cancelarComoAntesDelFix(viejo.servicioEventual.id);
      final nuevo = await venderComoEvt1();
      await anularNuevo.ejecutar(servicioEventualId: nuevo.servicioEventual.id, motivo: 'PRUEBASdd');

      expect(await saldoBbva(), 800000, reason: 'antes: sólo el gemelo viejo conserva sus 8,000');

      final resultado = await reconciliar.ejecutar(aplicar: true);
      expect(resultado, hasLength(1), reason: 'sólo el cancelado con la semántica vieja');
      expect(resultado.single.servicioEventual.id, viejo.servicioEventual.id);

      Future<Map<String, String>> estadoDe(CrearServicioEventualExitoso venta) async {
        final cuenta = (await (db.select(db.cuentaPorCobrar)
                  ..where((t) => t.id.equals(venta.cuenta.id)))
                .getSingle());
        final pago = await (db.select(db.pago)..where((t) => t.id.equals(venta.pago!.id))).getSingle();
        final aplicacion =
            await (db.select(db.aplicacionPago)..where((t) => t.pagoId.equals(pago.id))).getSingle();
        final ingreso = await (db.select(db.ingreso)..where((t) => t.pagoId.equals(pago.id))).getSingle();
        final eventual = await repo.obtenerPorId(venta.servicioEventual.id);
        return {
          'evento': eventual!.estatus,
          'cxc': cuenta.estatus,
          'saldoCxc': '${cuenta.saldoPendiente}',
          'aplicacion': aplicacion.estatus,
          'pago': pago.estatus,
          'ingreso': ingreso.estatus,
        };
      }

      final esperado = await estadoDe(nuevo);
      expect(esperado, {
        'evento': 'cancelado',
        'cxc': EstatusCuentaPorCobrar.cancelada.name,
        'saldoCxc': '0',
        'aplicacion': EstatusAplicacionPago.cancelada.name,
        'pago': EstatusPago.cancelado.name,
        'ingreso': EstatusIngreso.cancelado.name,
      });
      expect(await estadoDe(viejo), esperado, reason: 'el reconciliado es indistinguible del nuevo');
      expect(await saldoBbva(), 0, reason: 'BBVA ya no contabiliza los 8,000');
    });

    test('el historial explica por qué se movió dinero de un evento ya cancelado', () async {
      final venta = await venderComoEvt1();
      await cancelarComoAntesDelFix(venta.servicioEventual.id);
      await reconciliar.ejecutar(aplicar: true);

      final eventos = await (db.select(db.servicioEventualEvento)
            ..where((t) => t.servicioEventualId.equals(venta.servicioEventual.id)))
          .get();
      final tipos = eventos.map((e) => e.tipoEvento).toList();
      expect(tipos.where((t) => t == TipoEventoServicioEventual.cancelado.name), hasLength(1),
          reason: 'el evento NO se vuelve a cancelar');
      expect(tipos, contains(TipoEventoServicioEventual.cobroRevertido.name));
      final anulada = eventos.singleWhere((e) => e.tipoEvento == TipoEventoServicioEventual.ventaAnulada.name);
      expect(anulada.observacion, contains('Reconciliación v90'));
      expect(anulada.observacion, contains('PRUEBASdd'), reason: 'conserva el motivo original');
    });
  });

  group('Lo que NO debe tocar', () {
    test('un eventual activo y cobrado', () async {
      await venderComoEvt1();
      final antes = await fotografia();
      expect(await reconciliar.ejecutar(aplicar: true), isEmpty);
      expect(await fotografia(), antes);
      expect(await saldoBbva(), 800000);
    });

    test('un eventual cancelado ya con la semántica nueva', () async {
      final venta = await venderComoEvt1();
      await anularNuevo.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación');
      final antes = await fotografia();
      expect(await reconciliar.ejecutar(aplicar: true), isEmpty);
      expect(await fotografia(), antes);
    });

    test('un pago compartido: sólo se suelta la aplicación y el banco no se mueve', () async {
      final ventaA = await venderComoEvt1(cobro: null, conFactura: false);
      final ventaB = await venderComoEvt1(cobro: null, conFactura: false);
      // Un solo depósito de 6,000 que cubre las dos ventas.
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000900',
        servicioEventualId: ventaA.servicioEventual.id,
        montoTotal: 600000,
        fechaPago: DateTime(2026, 9, 17),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
      );
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: ventaA.cuenta.id, monto: 500000);
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: ventaB.cuenta.id, monto: 100000);
      await cancelarComoAntesDelFix(ventaA.servicioEventual.id);
      expect(await saldoBbva(), 600000);

      final resultado = await reconciliar.ejecutar(aplicar: true);
      final reconciliado = resultado.single as EventualReconciliable;
      expect(reconciliado.montoQueVuelve, 0, reason: 'el depósito cubre otra cuenta');

      expect(await saldoBbva(), 600000, reason: 'ninguna salida bancaria incorrecta');
      expect((await pagoRepo.obtenerPorId(pago.id))!.estatus, EstatusPago.registrado.name);
      final aplicaciones = await pagoRepo.listarAplicacionesPorPago(pago.id);
      expect(aplicaciones.firstWhere((a) => a.cuentaPorCobrarId == ventaA.cuenta.id).estatus,
          EstatusAplicacionPago.cancelada.name);
      expect(aplicaciones.firstWhere((a) => a.cuentaPorCobrarId == ventaB.cuenta.id).estatus,
          EstatusAplicacionPago.aplicada.name);
    });

    test('gastos reales ya pagados', () async {
      final venta = await venderComoEvt1();
      final participante = ((await agregarParticipante.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        nombreExterno: 'Pedro',
      )) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      final cobertura = ((await agregarCobertura.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 9, 17),
        horaInicioMinutos: 18 * 60,
        horaFinMinutos: 2 * 60,
        importeAcordado: 40000,
      )) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
      );
      await cancelarComoAntesDelFix(venta.servicioEventual.id);
      expect(await saldoBbva(), 800000 - 40000);

      await reconciliar.ejecutar(aplicar: true);

      final cob = (await db.select(db.servicioEventualCobertura).get()).single;
      expect(cob.estatus, EstatusEjecucionServicioEventual.pagada.name);
      expect((await db.select(db.egreso).get()).single.estatus, isNot('cancelado'));
      expect(await saldoBbva(), -40000, reason: 'se va el cobro; el gasto de 400 sigue fuera');
    });

    test('un CFDI vigente bloquea: se reporta y no se toca nada', () async {
      final venta = await venderComoEvt1();
      await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1001',
        fechaEmision: DateTime(2026, 9, 17),
        metodo: MetodoPagoCobro.pue,
      );
      await cancelarComoAntesDelFix(venta.servicioEventual.id);
      final antes = await fotografia();

      final resultado = await reconciliar.ejecutar(aplicar: true);
      expect(
        resultado.single,
        isA<EventualBloqueadoPorFiscal>().having((r) => r.folioDocumento, 'folio', 'A-1001'),
      );
      expect(await fotografia(), antes, reason: 'no se inventa una cancelación fiscal');
    });
  });

  group('Seguridad de la corrida', () {
    test('el diagnóstico no escribe nada', () async {
      final venta = await venderComoEvt1();
      await cancelarComoAntesDelFix(venta.servicioEventual.id);
      final antes = await fotografia();

      final resultado = await reconciliar.ejecutar(aplicar: false);
      expect((resultado.single as EventualReconciliable).montoQueVuelve, 800000);
      expect(await fotografia(), antes);
    });

    test('la segunda corrida produce CERO cambios', () async {
      final venta = await venderComoEvt1();
      await cancelarComoAntesDelFix(venta.servicioEventual.id);

      expect(await reconciliar.ejecutar(aplicar: true), hasLength(1));
      final trasLaPrimera = await fotografia();

      expect(await reconciliar.ejecutar(aplicar: true), isEmpty);
      expect(await fotografia(), trasLaPrimera, reason: 'ni una reversa ni un saldo más');
    });
  });
}
