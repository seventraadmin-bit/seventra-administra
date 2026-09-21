// §2 y §8 — cancelar el evento es ANULAR LA VENTA.
//
// El caso que lo destapó, tal cual se probó a mano:
//
//   subtotal $8,000 + IVA → total $9,280 → cobro inicial $8,000
//   → Pago → AplicacionPago → Ingreso → banco +$8,000
//   → "Cancelar evento"
//   → el evento quedaba cancelado y el dinero seguía vivo.
//
// Una operación cancelada con efecto financiero vivo no es un detalle
// de UX: es un saldo bancario que afirma algo que ya no es cierto.
//
// La matriz que estas pruebas fijan, escenario por escenario:
//
//   | Escenario                  | Qué pasa                                |
//   |----------------------------|-----------------------------------------|
//   | sin cobros                 | evento + CxC cancelados                 |
//   | pago parcial               | + Pago/Ingreso/banco revertidos         |
//   | totalmente cobrado         | + Pago/Ingreso/banco revertidos         |
//   | CFDI vigente               | BLOQUEA                                 |
//   | Complemento vigente        | BLOQUEA                                 |
//   | coberturas pendientes      | se cancelan                             |
//   | coberturas/costos pagados  | NO se tocan (gasto real)                |
//   | pago compartido con otra   | sólo se suelta la aplicación            |

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart'
    show EstatusAplicacionPago, EstatusPago, FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ServicioEventualRepositoryImpl repo;
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late PagoRepositoryImpl pagoRepo;
  late ComplementoPagoRepositoryImpl complementoRepo;
  late ServicioEventualDocumentoFiscalRepositoryImpl documentoRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;

  late CrearServicioEventualUseCase crear;
  late CancelarServicioEventualUseCase anular;
  late RegistrarCobroServicioEventualUseCase cobrar;
  late RegistrarDocumentoFiscalEventualUseCase facturar;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late AgregarCostoServicioEventualUseCase agregarCosto;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late PagarCostoServicioEventualUseCase pagarCosto;
  late CuentaFinancieraRepositoryImpl cuentasFinancieras;

  late CuentaFinancieraData banco;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    complementoRepo = ComplementoPagoRepositoryImpl(db);
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);

    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, cuentaRepo, pagoRepo);
    documentoRepo = ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo);

    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), entidadFiscalRepo);
    anular = CancelarServicioEventualUseCase(repo, documentoRepo, complementoRepo);
    cobrar = RegistrarCobroServicioEventualUseCase(
      repo,
      RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, GenerarCodigoUseCase(codigoSecuencia)),
    );
    facturar = RegistrarDocumentoFiscalEventualUseCase(documentoRepo, repo, cuentaRepo, entidadFiscalRepo);
    registrarComplemento = RegistrarComplementoPagoUseCase(complementoRepo, pagoRepo);
    agregarParticipante = AgregarParticipanteServicioEventualUseCase(
      repo,
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
    agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
    agregarCosto = AgregarCostoServicioEventualUseCase(repo);
    pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);
    pagarCosto = PagarCostoServicioEventualUseCase(repo, deudaRepo);
    cuentasFinancieras = CuentaFinancieraRepositoryImpl(db);

    banco = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA',
            tipo: 'cuenta',
            saldoInicial: 0,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  /// El caso exacto de la prueba manual: $8,000 + IVA = $9,280.
  Future<CrearServicioEventualExitoso> venderConIva({
    bool conFactura = false,
    MetodoPagoCobro metodo = MetodoPagoCobro.noAplica,
    int? cobroInicial,
  }) async {
    final resultado = await crear.ejecutar(
      nombre: 'Posada',
      fechaHoraInicio: DateTime(2026, 5, 1, 18),
      fechaHoraFin: DateTime(2026, 5, 2, 2),
      importeAcordado: 800000,
      tratamientoIva: TratamientoIva.masIva,
      tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
      solicitanteNombre: 'Juan del comité',
      requiereFactura: conFactura,
      metodoCobro: metodo,
      solicitanteRazonSocial: conFactura ? 'Administradora Bosques S.A. de C.V.' : null,
      solicitanteRfc: conFactura ? 'ABO010101AA1' : null,
      solicitanteCodigoPostalFiscal: conFactura ? '06700' : null,
      cobroInmediato: cobroInicial == null
          ? null
          : CobroInmediatoServicioEventual(
              monto: cobroInicial,
              fechaPago: DateTime(2026, 5, 1),
              formaPago: FormaPago.transferencia.name,
              cuentaFinancieraId: banco.id,
            ),
    );
    return resultado as CrearServicioEventualExitoso;
  }

  /// El saldo real de la cuenta: derivado de Ingresos y Egresos, que
  /// es exactamente lo que la anulación tiene que mover.
  Future<int> saldoBanco() => cuentasFinancieras.calcularSaldo(banco.id);

  group('§8 — el flujo manual completo, de punta a punta', () {
    test('vender 8,000 mas IVA, cobrar 8,000, anular: el banco vuelve a cero', () async {
      final venta = await venderConIva(cobroInicial: 800000);

      // --- La venta, tal como la vio el usuario ------------------
      expect(venta.servicioEventual.importeAcordado, 800000);
      expect(
        totalVentaEventual(importeAcordado: 800000, tratamientoIva: TratamientoIva.masIva),
        928000,
      );
      expect(venta.cuenta.importeEmitido, 928000, reason: 'la CxC nace con el TOTAL');
      expect(venta.cuenta.saldoPendiente, 128000, reason: '9,280 - 8,000');
      expect(venta.cuenta.estatus, EstatusCuentaPorCobrar.parcial.name);
      expect(await saldoBanco(), 800000);

      final pago = venta.pago!;
      expect(pago.montoTotal, 800000);
      expect((await db.select(db.aplicacionPago).get()).single.monto, 800000);
      expect((await db.select(db.ingreso).get()).single.monto, 800000);

      // --- Y la anulación -----------------------------------------
      final resultado = await anular.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        motivo: 'El cliente canceló el evento',
      );
      expect(resultado, isA<CancelarServicioEventualExitoso>());

      final eventual = (await db.select(db.servicioEventual).get()).single;
      expect(eventual.estatus, EstatusServicioEventual.cancelado.name);

      final cuenta = (await db.select(db.cuentaPorCobrar).get()).single;
      expect(cuenta.estatus, EstatusCuentaPorCobrar.cancelada.name);
      expect(cuenta.saldoPendiente, 0, reason: 'no queda saldo por cobrar de una venta anulada');

      final pagoFinal = (await db.select(db.pago).get()).single;
      expect(pagoFinal.estatus, EstatusPago.cancelado.name);
      expect(
        (await db.select(db.aplicacionPago).get()).single.estatus,
        EstatusAplicacionPago.cancelada.name,
      );
      expect((await db.select(db.ingreso).get()).single.estatus, EstatusIngreso.cancelado.name);
      expect(await saldoBanco(), 0, reason: 'el dinero que se devolvió no puede seguir en el banco');
    });

    test('variante: cobro PARCIAL de 8,000 sobre 9,280 se revierte igual', () async {
      // Mismo importe, pero cobrado DESPUÉS de vender, por el flujo de
      // Pagos: el camino distinto no puede dar un resultado distinto.
      final venta = await venderConIva();
      expect(venta.cuenta.saldoPendiente, 928000);
      expect(await saldoBanco(), 0);

      await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 800000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: banco.id,
      );
      expect(await saldoBanco(), 800000);

      await anular.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        motivo: 'Cancelación del evento',
      );

      expect(await saldoBanco(), 0);
      expect((await db.select(db.cuentaPorCobrar).get()).single.saldoPendiente, 0);
      expect((await db.select(db.pago).get()).single.estatus, EstatusPago.cancelado.name);
    });

    test('el historial deja el rastro: venta anulada y cobro revertido', () async {
      final venta = await venderConIva(cobroInicial: 800000);
      await anular.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        motivo: 'Cancelación del evento',
      );

      final tipos = (await db.select(db.servicioEventualEvento).get()).map((e) => e.tipoEvento).toList();
      expect(tipos, contains(TipoEventoServicioEventual.cobroRevertido.name));
      expect(tipos, contains(TipoEventoServicioEventual.ventaAnulada.name));
      expect(tipos, contains(TipoEventoServicioEventual.cancelado.name));
    });
  });

  group('§2 — la matriz, escenario por escenario', () {
    test('sin cobros: se cancela el evento y la CxC, y no hay dinero que mover', () async {
      final venta = await venderConIva();

      final resumen = await anular.previsualizar(venta.servicioEventual.id);
      expect(resumen.sinCobros, isTrue);
      expect(resumen.montoQueVuelve, 0);
      expect(resumen.bloqueada, isFalse);

      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Sin cobros');

      expect((await db.select(db.cuentaPorCobrar).get()).single.estatus,
          EstatusCuentaPorCobrar.cancelada.name);
      expect(await db.select(db.pago).get(), isEmpty);
      expect(await db.select(db.ingreso).get(), isEmpty);
    });

    test('totalmente cobrado: se revierte todo y la cuenta queda sin saldo', () async {
      final venta = await venderConIva(cobroInicial: 928000);
      expect(venta.cuenta.estatus, EstatusCuentaPorCobrar.pagada.name);

      final resumen = await anular.previsualizar(venta.servicioEventual.id);
      expect(resumen.montoQueVuelve, 928000);
      expect(resumen.montoQueSeDesaplica, 0);

      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación');
      expect(await saldoBanco(), 0);
      expect((await db.select(db.cuentaPorCobrar).get()).single.saldoPendiente, 0);
    });

    test('con CFDI vigente: BLOQUEA y dice qué cancelar primero', () async {
      final venta = await venderConIva(conFactura: true, metodo: MetodoPagoCobro.pue);
      await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1001',
        fechaEmision: DateTime(2026, 5, 3),
        metodo: MetodoPagoCobro.pue,
      );

      final resumen = await anular.previsualizar(venta.servicioEventual.id);
      expect(resumen.bloqueada, isTrue);
      expect(resumen.documentoFiscalVigente?.folio, 'A-1001');

      expect(
        await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación'),
        isA<CancelarServicioEventualDocumentoFiscalVigente>()
            .having((r) => r.folio, 'folio', 'A-1001'),
      );
      // Y no tocó nada: el bloqueo va ANTES de escribir.
      expect((await db.select(db.servicioEventual).get()).single.estatus,
          EstatusServicioEventual.programado.name);
      expect((await db.select(db.cuentaPorCobrar).get()).single.estatus,
          isNot(EstatusCuentaPorCobrar.cancelada.name));
    });

    test('con Complemento vigente: BLOQUEA aunque el CFDI ya se haya cancelado', () async {
      final venta = await venderConIva(conFactura: true, metodo: MetodoPagoCobro.ppd);
      await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 400000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: banco.id,
      );
      final pago = (await db.select(db.pago).get()).single;
      await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '123e4567-e89b-12d3-a456-426614174000',
        fechaTimbrado: DateTime(2026, 5, 11),
        montoTotal: 400000,
      );

      final resumen = await anular.previsualizar(venta.servicioEventual.id);
      expect(resumen.bloqueada, isTrue);
      expect(resumen.complementoVigenteUuid, '123e4567-e89b-12d3-a456-426614174000');

      expect(
        await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación'),
        isA<CancelarServicioEventualComplementoVigente>(),
      );
      expect(await saldoBanco(), 400000, reason: 'nada se movió');
    });

    test('coberturas y costos PENDIENTES se cancelan', () async {
      final venta = await venderConIva();
      final participante = ((await agregarParticipante.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        nombreExterno: 'Pedro',
      )) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      await agregarCobertura.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 18 * 60,
        horaFinMinutos: 2 * 60,
        importeAcordado: 150000,
      );
      await agregarCosto.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        concepto: 'Estacionamiento',
        monto: 30000,
        fecha: DateTime(2026, 5, 1),
      );

      final resumen = await anular.previsualizar(venta.servicioEventual.id);
      expect(resumen.coberturasPorCancelar, 1);
      expect(resumen.costosPorCancelar, 1);
      expect(resumen.gastoQuePermanece, 0, reason: 'nada se ha pagado todavía');

      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación');

      expect((await db.select(db.servicioEventualCobertura).get()).single.estatus,
          EstatusEjecucionServicioEventual.cancelada.name);
      expect((await db.select(db.servicioEventualCosto).get()).single.estatus,
          EstatusEjecucionServicioEventual.cancelada.name);
    });

    test('coberturas y costos YA PAGADOS no se tocan: el gasto fue real', () async {
      final venta = await venderConIva(cobroInicial: 928000);
      final participante = ((await agregarParticipante.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        nombreExterno: 'Pedro',
      )) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      final cobertura = ((await agregarCobertura.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 18 * 60,
        horaFinMinutos: 2 * 60,
        importeAcordado: 150000,
      )) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
      final costo = ((await agregarCosto.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        concepto: 'Estacionamiento',
        monto: 30000,
        fecha: DateTime(2026, 5, 1),
      )) as AgregarCostoServicioEventualExitoso)
          .costo;

      await pagarCobertura.ejecutar(
        coberturaId: cobertura.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: banco.id,
      );
      await pagarCosto.ejecutar(
        costoId: costo.id,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: banco.id,
      );
      final egresosAntes = await db.select(db.egreso).get();
      expect(egresosAntes, hasLength(2));
      final saldoAntes = await saldoBanco();
      expect(saldoAntes, 928000 - 150000 - 30000);

      final resumen = await anular.previsualizar(venta.servicioEventual.id);
      expect(resumen.gastoQuePermanece, 180000);

      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación');

      // El gasto sigue siendo gasto; sólo se fue el cobro.
      expect((await db.select(db.servicioEventualCobertura).get()).single.estatus,
          EstatusEjecucionServicioEventual.pagada.name);
      expect((await db.select(db.servicioEventualCosto).get()).single.estatus,
          EstatusEjecucionServicioEventual.pagada.name);
      final egresosDespues = await db.select(db.egreso).get();
      expect(egresosDespues.map((e) => e.id).toSet(), egresosAntes.map((e) => e.id).toSet());
      expect(egresosDespues.every((e) => e.estatus == egresosAntes.firstWhere((a) => a.id == e.id).estatus),
          isTrue);
      expect(await saldoBanco(), -180000,
          reason: 'entraron 9,280 y se devolvieron; los 1,800 de gasto real siguen fuera');
    });

    test('un pago compartido con otra cuenta: sólo se suelta su aplicación', () async {
      // Dos ventas, un solo depósito que cubre las dos. Cancelar el
      // Pago entero devolvería dinero de una cobranza ajena.
      final ventaA = await venderConIva();
      final ventaB = await venderConIva();

      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000001',
        // La contraparte del Pago: el esquema exige Cliente o eventual.
        servicioEventualId: ventaA.servicioEventual.id,
        montoTotal: 600000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: banco.id,
      );
      await pagoRepo.aplicar(
        pagoId: pago.id,
        cuentaPorCobrarId: ventaA.cuenta.id,
        monto: 500000,
      );
      await pagoRepo.aplicar(
        pagoId: pago.id,
        cuentaPorCobrarId: ventaB.cuenta.id,
        monto: 100000,
      );

      final resumen = await anular.previsualizar(ventaA.servicioEventual.id);
      expect(resumen.montoQueVuelve, 0, reason: 'el depósito ocurrió y cubre otra cuenta');
      expect(resumen.montoQueSeDesaplica, 500000);

      await anular.ejecutar(servicioEventualId: ventaA.servicioEventual.id, motivo: 'Anulación');

      final pagoFinal = (await db.select(db.pago).get()).single;
      expect(pagoFinal.estatus, EstatusPago.registrado.name, reason: 'sigue vivo para la otra venta');
      expect(await saldoBanco(), 500000 + 100000,
          reason: 'el dinero entró de verdad; no sale del banco por anular una venta');

      final aplicaciones = await db.select(db.aplicacionPago).get();
      final deA = aplicaciones.firstWhere((a) => a.cuentaPorCobrarId == ventaA.cuenta.id);
      final deB = aplicaciones.firstWhere((a) => a.cuentaPorCobrarId == ventaB.cuenta.id);
      expect(deA.estatus, EstatusAplicacionPago.cancelada.name);
      expect(deB.estatus, EstatusAplicacionPago.aplicada.name);
    });

    test('anular exige motivo y no se anula dos veces', () async {
      final venta = await venderConIva();
      expect(
        await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: '   '),
        isA<CancelarServicioEventualMotivoRequerido>(),
      );
      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación');
      expect(
        await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Otra vez'),
        isA<CancelarServicioEventualYaCancelado>(),
      );
    });

    test('anular es atómico: la CxC nunca queda cancelada con un pago vivo', () async {
      final venta = await venderConIva(cobroInicial: 500000);
      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Anulación');

      final cuenta = (await db.select(db.cuentaPorCobrar).get()).single;
      final aplicaciones = await db.select(db.aplicacionPago).get();
      // La regla dura de Finanzas: una CxC con aplicaciones vigentes no
      // se puede cancelar. Que ésta lo esté prueba que se soltaron
      // primero, dentro de la misma transacción.
      expect(cuenta.estatus, EstatusCuentaPorCobrar.cancelada.name);
      expect(
        aplicaciones.where((a) => a.estatus == EstatusAplicacionPago.aplicada.name),
        isEmpty,
      );
    });
  });
}
