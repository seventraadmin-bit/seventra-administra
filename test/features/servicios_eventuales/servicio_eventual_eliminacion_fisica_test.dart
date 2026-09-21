// Microetapa de cierre — el Servicio Eventual como ORIGEN del borrado
// Maestro, y la cobranza vigente de una venta anulada.
//
// El caso real que lo motiva es EVT-000001: 8,000 + IVA, cobrado 8,000,
// anulado. Después de anular, el listado seguía diciendo "Cobrado
// $9,280" porque esa cifra se derivaba de `saldoOriginal -
// saldoPendiente`, y cancelar la Cuenta pone el saldo en 0.

import 'package:drift/drift.dart' show Value;
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
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
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
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/cancelar_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/listar_servicios_eventuales_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';

void main() {
  late AppDatabase db;
  late ServicioEventualRepositoryImpl repo;
  late PagoRepositoryImpl pagoRepo;
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late CuentaFinancieraRepositoryImpl cuentasFinancieras;
  late DeudaRepositoryImpl deudaRepo;
  late CrearServicioEventualUseCase crear;
  late CancelarServicioEventualUseCase anular;
  late EliminarServicioEventualFisicamenteUseCase eliminar;
  late ListarServiciosEventualesUseCase listar;
  late RegistrarDocumentoFiscalEventualUseCase facturar;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late AgregarParticipanteServicioEventualUseCase agregarParticipante;
  late AgregarCoberturaServicioEventualUseCase agregarCobertura;
  late AgregarCostoServicioEventualUseCase agregarCosto;
  late PagarCoberturaServicioEventualUseCase pagarCobertura;
  late PagarCostoServicioEventualUseCase pagarCosto;
  late CuentaFinancieraData bbva;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    final complementoRepo = ComplementoPagoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, cuentaRepo, pagoRepo);
    final documentoRepo = ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo);
    cuentasFinancieras = CuentaFinancieraRepositoryImpl(db);

    crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), entidadFiscalRepo);
    anular = CancelarServicioEventualUseCase(repo, documentoRepo, complementoRepo);
    eliminar = EliminarServicioEventualFisicamenteUseCase(repo);
    listar = ListarServiciosEventualesUseCase(repo, ClienteRepositoryImpl(db), cuentaRepo);
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

    bbva = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-BBVA',
            nombre: 'BBVA Empresarial',
            tipo: 'banco',
            saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> saldoBbva() => cuentasFinancieras.calcularSaldo(bbva.id);

  /// El gemelo de EVT-000001: 8,000 + IVA = 9,280, con factura PUE.
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

  /// Participantes, dos coberturas y un costo, como el caso real.
  Future<void> poblarOperacion(String eventualId) async {
    final participante = ((await agregarParticipante.ejecutar(
      servicioEventualId: eventualId,
      nombreExterno: 'Pedro',
    )) as AgregarParticipanteServicioEventualExitoso)
        .participante;
    for (var i = 0; i < 2; i++) {
      await agregarCobertura.ejecutar(
        servicioEventualId: eventualId,
        participanteId: participante.id,
        fecha: DateTime(2026, 9, 17),
        horaInicioMinutos: 18 * 60,
        horaFinMinutos: 2 * 60,
        importeAcordado: 40000,
      );
    }
    await agregarCosto.ejecutar(
      servicioEventualId: eventualId,
      concepto: 'Estacionamiento',
      monto: 100000,
      fecha: DateTime(2026, 9, 17),
    );
  }

  Future<RenglonServicioEventual> renglonDe(String eventualId) async =>
      (await listar.ejecutar()).firstWhere((r) => r.servicioEventual.id == eventualId);

  group('Cobranza vigente de una venta anulada', () {
    test('tras anular, lo cobrado vigente es 0 — no el total de la venta', () async {
      final venta = await venderComoEvt1();
      await poblarOperacion(venta.servicioEventual.id);

      final antes = await renglonDe(venta.servicioEventual.id);
      expect(antes.totalVenta, 928000);
      expect(antes.cobrado, 800000, reason: 'lo que de verdad entró');
      expect(antes.pendiente, 128000);

      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'PRUEBASdd');

      final despues = await renglonDe(venta.servicioEventual.id);
      expect(despues.cobrado, 0, reason: 'una venta anulada no conserva cobranza vigente');
      expect(despues.pendiente, 0, reason: 'ni nada exigible');
      // Y la historia sigue ahí: el Pago y el Ingreso existen, cancelados.
      expect(await db.select(db.pago).get(), hasLength(1));
      expect(await db.select(db.ingreso).get(), hasLength(1));
    });

    test('un Pago cancelado por su cuenta tampoco cuenta como cobrado', () async {
      final venta = await venderComoEvt1();
      await pagoRepo.cancelar(pagoId: venta.pago!.id, motivo: 'Cheque devuelto');

      final renglon = await renglonDe(venta.servicioEventual.id);
      expect(renglon.cobrado, 0);
      expect(renglon.servicioEventual.estatus, EstatusServicioEventual.programado.name,
          reason: 'el evento sigue vivo: la corrección es de la fuente, no un if por estatus');
      expect(renglon.pendiente, 928000, reason: 'la deuda vuelve a ser exigible completa');
    });

    test('cobro parcial: se cuenta lo aplicado, no la resta de saldos', () async {
      final venta = await venderComoEvt1(cobro: 300000);
      final renglon = await renglonDe(venta.servicioEventual.id);
      expect(renglon.cobrado, 300000);
      expect(renglon.pendiente, 628000);
    });

    test('el costo de consultarlo no crece con el número de eventuales', () async {
      // Una consulta agregada, no una por renglón: se comprueba que el
      // resultado es correcto para varios a la vez.
      final a = await venderComoEvt1(cobro: 100000, conFactura: false);
      final b = await venderComoEvt1(cobro: null, conFactura: false);
      final mapa = await repo.cobradoVigentePorEventual([a.servicioEventual.id, b.servicioEventual.id]);
      expect(mapa[a.servicioEventual.id], 100000);
      expect(mapa[b.servicioEventual.id], 0, reason: 'sin cobros, cero explícito');
    });
  });

  group('KPIs del listado', () {
    test('una venta anulada sale de venta/costo/resultado pero sigue listada', () async {
      final vivo = await venderComoEvt1(cobro: null, conFactura: false);
      await poblarOperacion(vivo.servicioEventual.id);
      final anulado = await venderComoEvt1(cobro: null, conFactura: false);
      await poblarOperacion(anulado.servicioEventual.id);
      await anular.ejecutar(servicioEventualId: anulado.servicioEventual.id, motivo: 'Prueba');

      final renglones = await listar.ejecutar();
      expect(renglones, hasLength(2), reason: 'los dos siguen en la tabla');

      final vigentes = renglones.where(
        (r) => r.servicioEventual.estatus != EstatusServicioEventual.cancelado.name,
      );
      expect(vigentes, hasLength(1));
      // 8,000 + IVA de UNO solo, no de los dos.
      expect(vigentes.fold<int>(0, (s, r) => s + r.totalVenta), 928000);
      // El anulado conserva su venta y pierde sus costos comprometidos,
      // así que sumarlo regalaba utilidad pura que nunca existió.
      final anuladoRenglon = renglones.firstWhere((r) => r.servicioEventual.id == anulado.servicioEventual.id);
      expect(anuladoRenglon.totales.costoComprometido, 0, reason: 'sus coberturas y costos se cancelaron');
      expect(anuladoRenglon.totalVenta, 928000, reason: 'su historia se conserva en el renglón');
    });
  });

  group('Eliminación física Maestro', () {
    test('el eventual es el origen: se lleva su cobranza exclusiva completa', () async {
      // Una operación ajena que no puede moverse ni un centavo.
      final ajeno = await venderComoEvt1(cobro: 500000, conFactura: false);
      final saldoAjeno = await saldoBbva();

      final venta = await venderComoEvt1();
      await poblarOperacion(venta.servicioEventual.id);
      expect(await saldoBbva(), saldoAjeno + 800000);
      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Registro de prueba');

      final resultado = await eliminar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        motivo: 'Captura de prueba',
        actorUsuarioId: null,
      );
      expect(resultado, isA<EliminarServicioEventualFisicamenteExitoso>());

      // 1. El eventual y sus dependencias exclusivas, fuera.
      expect(await repo.obtenerPorId(venta.servicioEventual.id), isNull);
      // Acotado a ESTE eventual: el ajeno conserva los suyos.
      final suyo = venta.servicioEventual.id;
      expect((await db.select(db.servicioEventualParticipante).get()).where((x) => x.servicioEventualId == suyo), isEmpty);
      expect((await db.select(db.servicioEventualCobertura).get()).where((x) => x.servicioEventualId == suyo), isEmpty);
      expect((await db.select(db.servicioEventualCosto).get()).where((x) => x.servicioEventualId == suyo), isEmpty);
      expect((await db.select(db.servicioEventualEvento).get()).where((x) => x.servicioEventualId == suyo), isEmpty);
      expect((await db.select(db.servicioEventualEvento).get()).where((x) => x.servicioEventualId == ajeno.servicioEventual.id), isNotEmpty,
          reason: 'el historial del ajeno no se toca');

      // 2. Ni CxC huérfana ni Pago/Ingreso fantasma.
      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(cuentas.where((c) => c.servicioEventualId == venta.servicioEventual.id), isEmpty);
      final pagos = await db.select(db.pago).get();
      expect(pagos.where((p) => p.id == venta.pago!.id), isEmpty);
      expect((await db.select(db.aplicacionPago).get()).where((a) => a.pagoId == venta.pago!.id), isEmpty);
      expect((await db.select(db.ingreso).get()).where((i) => i.pagoId == venta.pago!.id), isEmpty);

      // 3. La operación ajena, intacta, y el saldo como si el eventual
      //    nunca hubiera existido.
      expect(await repo.obtenerPorId(ajeno.servicioEventual.id), isNotNull);
      expect(cuentas.where((c) => c.servicioEventualId == ajeno.servicioEventual.id), hasLength(1));
      expect(await saldoBbva(), saldoAjeno);

      // 4. Auditoría central: el eventual y su Pago, cada uno con su
      //    snapshot. No queda historial normal simulando que no pasó.
      final eliminaciones = await db.select(db.eliminacionFisicaEvento).get();
      expect(eliminaciones.map((e) => e.tipoEntidad).toSet(), {'servicioEventual', 'pago'});
      final delEventual = eliminaciones.firstWhere((e) => e.tipoEntidad == 'servicioEventual');
      expect(delEventual.entidadIdOriginal, venta.servicioEventual.id);
      expect(delEventual.motivo, 'Captura de prueba');
      expect(delEventual.snapshotJson, contains(venta.servicioEventual.folio));
    });

    test('sin cobro: se elimina igual, sin tocar Finanzas', () async {
      final venta = await venderComoEvt1(cobro: null, conFactura: false);
      await poblarOperacion(venta.servicioEventual.id);

      expect(
        await eliminar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          motivo: 'Prueba',
        ),
        isA<EliminarServicioEventualFisicamenteExitoso>(),
      );
      expect(await db.select(db.servicioEventual).get(), isEmpty);
      expect(await db.select(db.cuentaPorCobrar).get(), isEmpty);
      expect(await db.select(db.pago).get(), isEmpty);
    });

    test('con documento fiscal cancelado y venta anulada: el CFDI histórico se va con él', () async {
      final venta = await venderComoEvt1(cobro: null);
      await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1001',
        fechaEmision: DateTime(2026, 9, 17),
        metodo: MetodoPagoCobro.pue,
      );
      final documento = (await db.select(db.servicioEventualDocumentoFiscal).get()).single;
      await db.customStatement(
        "UPDATE servicio_eventual_documento_fiscal SET estatus = 'cancelado' WHERE id = ?",
        [documento.id],
      );

      expect(
        await eliminar.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Prueba'),
        isA<EliminarServicioEventualFisicamenteExitoso>(),
      );
      expect(await db.select(db.servicioEventualDocumentoFiscal).get(), isEmpty);
    });
  });

  group('Escenarios que BLOQUEAN', () {
    test('un Pago vigente: hay que anular la venta primero', () async {
      final venta = await venderComoEvt1();
      final resultado = await eliminar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        motivo: 'Prueba',
      );
      expect(
        resultado,
        isA<EliminarServicioEventualFisicamenteTieneDependencias>()
            .having((r) => r.detalle, 'detalle', contains('sigue activo')),
      );
      expect(await repo.obtenerPorId(venta.servicioEventual.id), isNotNull);
    });

    test('un Pago COMPARTIDO con otra cuenta por cobrar', () async {
      final ventaA = await venderComoEvt1(cobro: null, conFactura: false);
      final ventaB = await venderComoEvt1(cobro: null, conFactura: false);
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
      await anular.ejecutar(servicioEventualId: ventaA.servicioEventual.id, motivo: 'Prueba');
      // El Pago se cancela para que "Pago activo" NO pueda ser lo que
      // bloquee: así la única regla que queda en pie es la de
      // compartición, que es la que esta prueba mide.
      await pagoRepo.cancelar(pagoId: pago.id, motivo: 'Prueba');
      final saldoAntes = await saldoBbva();

      final resultado = await eliminar.ejecutar(
        servicioEventualId: ventaA.servicioEventual.id,
        motivo: 'Prueba',
      );
      expect(
        resultado,
        isA<EliminarServicioEventualFisicamenteTieneDependencias>()
            .having((r) => r.detalle, 'detalle', contains('también cubre')),
      );
      // Nada se movió: ni el evento, ni el pago, ni el banco.
      expect(await repo.obtenerPorId(ventaA.servicioEventual.id), isNotNull);
      expect(await pagoRepo.obtenerPorId(pago.id), isNotNull);
      expect(await saldoBbva(), saldoAntes);
    });

    test('un Complemento de pago en el histórico', () async {
      final venta = await venderComoEvt1(conFactura: true);
      await registrarComplemento.ejecutar(
        pagoId: venta.pago!.id,
        uuid: '123e4567-e89b-12d3-a456-426614174000',
        fechaTimbrado: DateTime(2026, 9, 18),
        montoTotal: 800000,
      );
      // Se cancela el Complemento y se anula la venta: aun así, un CFDI
      // que existió ante el SAT bloquea el borrado del Pago.
      await db.customStatement("UPDATE complemento_pago SET estatus = 'cancelado'");
      await anular.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Prueba');

      expect(
        await eliminar.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Prueba'),
        isA<EliminarServicioEventualFisicamenteTieneDependencias>()
            .having((r) => r.detalle, 'detalle', contains('Complemento')),
      );
      expect(await repo.obtenerPorId(venta.servicioEventual.id), isNotNull);
    });

    test('una cobertura con Egreso real: hay que revertir el pago primero', () async {
      final venta = await venderComoEvt1(cobro: null, conFactura: false);
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

      expect(
        await eliminar.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Prueba'),
        isA<EliminarServicioEventualFisicamenteTieneDependencias>()
            .having((r) => r.detalle, 'detalle', contains('cobertura')),
      );
      expect((await db.select(db.egreso).get()), hasLength(1), reason: 'el gasto real sigue ahí');
    });

    test('un costo cargado a TARJETA: el pasivo vivo bloquea', () async {
      final tarjeta = await db.into(db.deuda).insertReturning(
        DeudaCompanion.insert(
          folio: 'DEU-TDC',
          nombre: 'TDC Banorte',
          tipo: TipoDeuda.tarjetaCredito.name,
          saldoActual: 0,
          tarjetaLimiteCredito: const Value(5000000),
        ),
      );
      final venta = await venderComoEvt1(cobro: null, conFactura: false);
      final costo = ((await agregarCosto.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        concepto: 'Estacionamiento',
        monto: 100000,
        fecha: DateTime(2026, 9, 17),
      )) as AgregarCostoServicioEventualExitoso)
          .costo;
      await pagarCosto.ejecutar(
        costoId: costo.id,
        formaPago: FormaPago.tarjeta.name,
        deudaIdTarjeta: tarjeta.id,
      );

      expect(
        await eliminar.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: 'Prueba'),
        isA<EliminarServicioEventualFisicamenteTieneDependencias>()
            .having((r) => r.detalle, 'detalle', contains('costo')),
      );
      expect((await deudaRepo.obtenerPorId(tarjeta.id))!.saldoActual, 100000,
          reason: 'el pasivo de la tarjeta no se toca');
    });

    test('sin motivo no se elimina', () async {
      final venta = await venderComoEvt1(cobro: null, conFactura: false);
      expect(
        await eliminar.ejecutar(servicioEventualId: venta.servicioEventual.id, motivo: '   '),
        isA<EliminarServicioEventualFisicamenteMotivoRequerido>(),
      );
      expect(await repo.obtenerPorId(venta.servicioEventual.id), isNotNull);
    });
  });
}
