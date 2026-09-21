// Reportes Etapa B — análisis de cartera, pagos y deuda.
//
// Las reglas que estas pruebas defienden son las del pedido:
//
//  - El aging suma EXACTAMENTE el saldo de CxC incluido, y una cuenta
//    pagada o cancelada nunca se clasifica como vencida.
//  - Un Pago N:M aparece UNA vez, no una por aplicación.
//  - El estado del Complemento se deriva del Pago y del complemento
//    VIGENTE — uno cancelado no documenta nada.
//  - El gasto con TDC se cuenta una sola vez: cargar la tarjeta es
//    gasto, pagarla es caja.
//
// Se construyen Cuentas por cobrar reales (documento + repositorio del
// dominio) y Pagos reales vía `PagoRepository`, nunca filas inventadas
// a mano en la tabla de CxC.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_cobranza_usecase.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_deuda_usecase.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_pagos_usecase.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  var consecutivo = 0;

  /// Fecha de referencia fija: la antigüedad y el vencimiento se
  /// calculan contra ella, nunca contra el reloj.
  final hoy = DateTime(2026, 6, 15);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestro.new),
      // `documentoPorEmitirRepositoryProvider` arrastra
      // `attachmentStorageProvider`, que bajo `flutter test` no tiene
      // `path_provider` — mismo override que el resto de las pruebas.
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
    consecutivo = 0;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<String> crearCliente(String nombre) async {
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-${++consecutivo}', nombreComercial: nombre),
        );
    return cliente.id;
  }

  /// Documento + Cuenta por cobrar reales, con el vencimiento pedido.
  ///
  /// El documento se inserta directo porque lo único que Reportes lee de
  /// él es el snapshot (entidad fiscal y servicios); la Cuenta SÍ pasa
  /// por su repositorio, que es quien mantiene saldo y estatus.
  Future<CuentaPorCobrarData> crearCuenta({
    required String clienteId,
    required int importe,
    DateTime? vencimiento,
    bool ppdConComplemento = false,
    String? servicioId,
    String? entidadFiscalId,
  }) async {
    final n = ++consecutivo;
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-$n',
            clienteId: clienteId,
            entidadFiscalId: Value(entidadFiscalId),
            tipoDocumento: TipoDocumentoCobro.cfdi.name,
            agrupacion: AgrupacionCobro.porServicio.name,
            metodo: ppdConComplemento ? MetodoPagoCobro.ppd.name : MetodoPagoCobro.pue.name,
            requiereComplemento: Value(ppdConComplemento),
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GEN-$n',
            importeBaseEsperado: importe,
            importeFinalEsperado: importe,
          ),
        );
    if (servicioId != null) {
      await db.into(db.documentoPorEmitirServicio).insert(
            DocumentoPorEmitirServicioCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: servicioId,
            ),
          );
    }
    return container.read(cuentaPorCobrarRepositoryProvider).crear(
          documentoPorEmitirId: documento.id,
          clienteId: clienteId,
          tipoDocumento: TipoDocumentoCobro.cfdi.name,
          metodo: ppdConComplemento ? MetodoPagoCobro.ppd.name : MetodoPagoCobro.pue.name,
          requiereComplemento: ppdConComplemento,
          folioDocumento: 'FOL-$n',
          fechaEmisionReal: DateTime(2026, 1, 5),
          importeEmitido: importe,
          fechaVencimiento: vencimiento,
        );
  }

  Future<PagoData> crearPago({required String clienteId, required int monto, DateTime? fecha}) async {
    return container.read(pagoRepositoryProvider).crear(
          folioPago: 'PAG-${(++consecutivo).toString().padLeft(6, '0')}',
          clienteId: clienteId,
          montoTotal: monto,
          fechaPago: fecha ?? DateTime(2026, 6, 10),
          formaPago: FormaPago.transferencia.name,
        );
  }

  Future<AnalisisCobranza> analizarCobranza({FiltroCobranza filtro = const FiltroCobranza()}) {
    return container.read(obtenerAnalisisCobranzaUseCaseProvider).ejecutar(filtro: filtro, hoy: hoy);
  }

  Future<AnalisisPagos> analizarPagos({String? clienteId}) {
    return container.read(obtenerAnalisisPagosUseCaseProvider).ejecutar(
          rango: RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
          clienteId: clienteId,
        );
  }

  group('Antigüedad de cartera', () {
    test('el aging suma EXACTAMENTE el saldo de CxC incluido', () async {
      final cliente = await crearCliente('Sportium');
      await crearCuenta(clienteId: cliente, importe: 1000000, vencimiento: DateTime(2026, 7, 1)); // al corriente
      await crearCuenta(clienteId: cliente, importe: 500000, vencimiento: DateTime(2026, 6, 1)); // 14 días
      await crearCuenta(clienteId: cliente, importe: 300000, vencimiento: DateTime(2026, 5, 1)); // 45 días
      await crearCuenta(clienteId: cliente, importe: 200000, vencimiento: DateTime(2026, 1, 1)); // +90

      final analisis = await analizarCobranza();

      expect(analisis.saldoPendiente, 2000000);
      expect(analisis.totalAging, analisis.saldoPendiente, reason: 'la suma de cubetas ES el saldo, no una aproximación');
      expect(
        analisis.aging.fold<int>(0, (a, c) => a + c.cuentas),
        analisis.cuentasConSaldo,
        reason: 'el conteo por cubeta también tiene que cuadrar',
      );

      Map<RangoAntiguedadCuentaPorCobrar, int> porCubeta() =>
          {for (final c in analisis.aging) c.cubeta: c.importe};
      expect(porCubeta()[RangoAntiguedadCuentaPorCobrar.alCorriente], 1000000);
      expect(porCubeta()[RangoAntiguedadCuentaPorCobrar.dias0a30], 500000);
      expect(porCubeta()[RangoAntiguedadCuentaPorCobrar.dias31a60], 300000);
      expect(porCubeta()[RangoAntiguedadCuentaPorCobrar.dias90Mas], 200000);
    });

    test('una cuenta PAGADA no aparece como vencida ni aporta al aging', () async {
      final cliente = await crearCliente('Tikal');
      final vencidaYaPagada = await crearCuenta(
        clienteId: cliente,
        importe: 400000,
        vencimiento: DateTime(2026, 1, 1),
      );
      final pago = await crearPago(clienteId: cliente, monto: 400000);
      await container.read(pagoRepositoryProvider).aplicar(
            pagoId: pago.id,
            cuentaPorCobrarId: vencidaYaPagada.id,
            monto: 400000,
          );

      final analisis = await analizarCobranza();

      expect(analisis.saldoPendiente, 0);
      expect(analisis.saldoVencido, 0, reason: 'ya se cobró: su fecha vieja no la vuelve cartera vencida');
      expect(analisis.totalAging, 0);
      expect(analisis.cuentasConSaldo, 0);
      expect(analisis.porcentajeVencido, isNull, reason: 'sin saldo no hay porcentaje, y 0 % mentiría');
    });

    test('una cuenta CANCELADA tampoco entra al aging', () async {
      final cliente = await crearCliente('Morgan');
      final cuenta = await crearCuenta(clienteId: cliente, importe: 700000, vencimiento: DateTime(2026, 1, 1));
      await container.read(cuentaPorCobrarRepositoryProvider).cancelar(
            cuentaPorCobrarId: cuenta.id,
            motivo: 'Documento emitido por error',
          );

      final analisis = await analizarCobranza();
      expect(analisis.totalAging, 0);
      expect(analisis.saldoVencido, 0);
    });

    test('un pago parcial deja el saldo restante en su cubeta, no el importe original', () async {
      final cliente = await crearCliente('Milo');
      final cuenta = await crearCuenta(clienteId: cliente, importe: 1000000, vencimiento: DateTime(2026, 5, 1));
      final pago = await crearPago(clienteId: cliente, monto: 400000);
      await container
          .read(pagoRepositoryProvider)
          .aplicar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 400000);

      final analisis = await analizarCobranza();

      expect(analisis.saldoPendiente, 600000, reason: 'la cartera es el saldo, nunca el importe emitido');
      expect(analisis.totalAging, 600000);
      expect(analisis.cuentas.single.aplicado, 400000);
      expect(
        EstatusCuentaPorCobrar.values.byName(analisis.cuentas.single.cuenta.estatus),
        EstatusCuentaPorCobrar.parcial,
      );
    });

    test('una cuenta sin fecha de vencimiento queda al corriente y sin días de atraso inventados', () async {
      final cliente = await crearCliente('Mirabilia');
      await crearCuenta(clienteId: cliente, importe: 900000);

      final analisis = await analizarCobranza();
      expect(analisis.cuentas.single.cubeta, RangoAntiguedadCuentaPorCobrar.alCorriente);
      expect(analisis.cuentas.single.diasAtraso, isNull);
      expect(analisis.diasAtrasoPromedio, isNull, reason: 'sin nada vencido con fecha, no hay promedio que calcular');
    });

    test('el promedio de días de atraso pondera por saldo', () async {
      final cliente = await crearCliente('Atlacomulco');
      await crearCuenta(clienteId: cliente, importe: 900000, vencimiento: DateTime(2026, 6, 5)); // 10 días
      await crearCuenta(clienteId: cliente, importe: 100000, vencimiento: DateTime(2026, 3, 17)); // 90 días

      final analisis = await analizarCobranza();
      // (10*900000 + 90*100000) / 1000000 = 18
      expect(analisis.diasAtrasoPromedio, closeTo(18, 0.001));
    });
  });

  group('Filtros de cartera — el KPI y la tabla comparten universo', () {
    test('filtrar por cliente recalcula KPI, aging y concentración sobre lo filtrado', () async {
      final a = await crearCliente('Cliente A');
      final b = await crearCliente('Cliente B');
      await crearCuenta(clienteId: a, importe: 600000, vencimiento: DateTime(2026, 5, 1));
      await crearCuenta(clienteId: b, importe: 400000, vencimiento: DateTime(2026, 5, 1));

      final todos = await analizarCobranza();
      expect(todos.saldoPendiente, 1000000);
      expect(todos.clientesConSaldo, 2);

      final soloA = await analizarCobranza(filtro: FiltroCobranza(clienteId: a));
      expect(soloA.saldoPendiente, 600000);
      expect(soloA.totalAging, 600000, reason: 'el aging se recalcula sobre el filtro, no sobre el universo');
      expect(soloA.clientesConSaldo, 1);
      expect(soloA.concentracion.single.saldo, 600000);
      expect(
        soloA.cuentas.fold<int>(0, (acc, c) => acc + c.saldo),
        soloA.saldoPendiente,
        reason: 'sum(tabla filtrada) == KPI',
      );
    });

    test('"sólo vencidas" excluye las que están al corriente', () async {
      final cliente = await crearCliente('Mixto');
      await crearCuenta(clienteId: cliente, importe: 300000, vencimiento: DateTime(2026, 7, 1));
      await crearCuenta(clienteId: cliente, importe: 200000, vencimiento: DateTime(2026, 5, 1));

      final vencidas = await analizarCobranza(filtro: const FiltroCobranza(soloVencidas: true));
      expect(vencidas.cuentas, hasLength(1));
      expect(vencidas.saldoPendiente, 200000);
      expect(vencidas.saldoVencido, 200000);
    });

    test('filtrar por cubeta deja sólo esa cubeta con importe', () async {
      final cliente = await crearCliente('Cubetas');
      await crearCuenta(clienteId: cliente, importe: 300000, vencimiento: DateTime(2026, 6, 1)); // 0-30
      await crearCuenta(clienteId: cliente, importe: 500000, vencimiento: DateTime(2026, 1, 1)); // +90

      final analisis = await analizarCobranza(
        filtro: const FiltroCobranza(cubeta: RangoAntiguedadCuentaPorCobrar.dias90Mas),
      );
      expect(analisis.saldoPendiente, 500000);
      expect(analisis.totalAging, 500000);
    });

    test('las cuentas se ordenan por atraso y luego por saldo', () async {
      final cliente = await crearCliente('Orden');
      await crearCuenta(clienteId: cliente, importe: 100000, vencimiento: DateTime(2026, 6, 10)); // 5 días
      await crearCuenta(clienteId: cliente, importe: 900000, vencimiento: DateTime(2026, 1, 1)); // +90
      await crearCuenta(clienteId: cliente, importe: 500000, vencimiento: DateTime(2026, 7, 1)); // al corriente

      final analisis = await analizarCobranza();
      expect(analisis.cuentas.first.diasAtraso, greaterThan(100), reason: 'lo más viejo se trabaja primero');
      expect(analisis.cuentas.last.diasAtraso, isNull);
    });
  });

  group('Concentración de cartera', () {
    test('agrupa la cola larga en "Otros" sin perder un peso', () async {
      // Ocho clientes contra un tope de seis: dos caen en "Otros".
      var esperado = 0;
      for (var i = 1; i <= 8; i++) {
        final cliente = await crearCliente('Cliente $i');
        final importe = i * 100000;
        esperado += importe;
        await crearCuenta(clienteId: cliente, importe: importe, vencimiento: DateTime(2026, 5, 1));
      }

      final analisis = await analizarCobranza();
      final concentracion = analisis.concentracion;

      expect(concentracion, hasLength(ObtenerAnalisisCobranzaUseCase.topConcentracion + 1));
      expect(concentracion.last.esOtros, isTrue);
      expect(concentracion.last.cuentas, 2);
      expect(
        concentracion.fold<int>(0, (a, c) => a + c.saldo),
        esperado,
        reason: 'agrupar la cola no puede perder importe',
      );
      expect(concentracion.first.saldo, greaterThan(concentracion[1].saldo), reason: 'de mayor a menor');
      expect(concentracion.first.clienteId, isNotNull, reason: 'cada cliente agrega por FK, nunca por nombre');
    });

    test('con pocos clientes no se inventa una fila "Otros"', () async {
      final cliente = await crearCliente('Único');
      await crearCuenta(clienteId: cliente, importe: 100000, vencimiento: DateTime(2026, 5, 1));

      final analisis = await analizarCobranza();
      expect(analisis.concentracion, hasLength(1));
      expect(analisis.concentracion.single.esOtros, isFalse);
    });
  });

  group('Pagos — el objeto proyectado es el Pago', () {
    test('un pago N:M aparece UNA vez, con sus dos aplicaciones', () async {
      final cliente = await crearCliente('Sportium');
      final facturaA = await crearCuenta(clienteId: cliente, importe: 2000000);
      final facturaB = await crearCuenta(clienteId: cliente, importe: 3000000);

      final pago = await crearPago(clienteId: cliente, monto: 5000000);
      final repo = container.read(pagoRepositoryProvider);
      await repo.aplicar(pagoId: pago.id, cuentaPorCobrarId: facturaA.id, monto: 2000000);
      await repo.aplicar(pagoId: pago.id, cuentaPorCobrarId: facturaB.id, monto: 3000000);

      final analisis = await analizarPagos();

      expect(analisis.pagos, hasLength(1), reason: 'UN pago, no uno por aplicación');
      expect(analisis.importeRecibido, 5000000, reason: 'jamás 10,000,000');
      expect(analisis.pagos.single.aplicaciones, hasLength(2));
      expect(analisis.pagos.single.documentosCubiertos, 2);
      expect(analisis.pagos.single.aplicado, 5000000);
      expect(analisis.pagos.single.porAplicar, 0);
      expect(
        analisis.pagos.fold<int>(0, (a, p) => a + p.importe),
        analisis.importeRecibido,
        reason: 'sum(tabla) == KPI',
      );
    });

    test('un pago sin aplicar cuenta como recibido y como pendiente de aplicar', () async {
      final cliente = await crearCliente('Anticipo');
      await crearPago(clienteId: cliente, monto: 750000);

      final analisis = await analizarPagos();
      expect(analisis.importeRecibido, 750000);
      expect(analisis.importeAplicado, 0);
      expect(analisis.importePorAplicar, 750000, reason: 'el dominio permite un Pago sin aplicaciones');
      expect(analisis.pagos.single.documentosCubiertos, 0);
    });

    test('un pago cancelado no cuenta como dinero recibido', () async {
      final cliente = await crearCliente('Cancelado');
      final pago = await crearPago(clienteId: cliente, monto: 400000);
      await container.read(pagoRepositoryProvider).cancelar(pagoId: pago.id, motivo: 'Depósito devuelto');

      final analisis = await analizarPagos();
      expect(analisis.pagos, isEmpty);
      expect(analisis.importeRecibido, 0);
    });

    test('cuenta clientes distintos, no pagos', () async {
      final a = await crearCliente('A');
      final b = await crearCliente('B');
      await crearPago(clienteId: a, monto: 100000);
      await crearPago(clienteId: a, monto: 200000);
      await crearPago(clienteId: b, monto: 300000);

      final analisis = await analizarPagos();
      expect(analisis.pagosRecibidos, 3);
      expect(analisis.clientesQuePagaron, 2);
    });
  });

  group('Complementos — derivados del Pago y del complemento vigente', () {
    /// El caso obligatorio del pedido: factura PPD de $30,000 cubierta
    /// por dos pagos; uno timbrado y otro no.
    test('factura PPD con dos pagos: una obligación registrada y una pendiente', () async {
      final cliente = await crearCliente('PPD');
      final factura = await crearCuenta(clienteId: cliente, importe: 3000000, ppdConComplemento: true);

      final repo = container.read(pagoRepositoryProvider);
      final pagoA = await crearPago(clienteId: cliente, monto: 1000000);
      await repo.aplicar(pagoId: pagoA.id, cuentaPorCobrarId: factura.id, monto: 1000000);
      final pagoB = await crearPago(clienteId: cliente, monto: 2000000);
      await repo.aplicar(pagoId: pagoB.id, cuentaPorCobrarId: factura.id, monto: 2000000);

      await container.read(complementoPagoRepositoryProvider).crear(
            pagoId: pagoA.id,
            uuid: 'UUID-COMPLEMENTO-A',
            fechaTimbrado: DateTime(2026, 6, 11),
            montoTotal: 1000000,
          );

      final pagos = await analizarPagos();
      final cobranza = await analizarCobranza();

      expect(cobranza.saldoPendiente, 0, reason: 'la factura quedó saldada');
      expect(pagos.pagosRecibidos, 2, reason: 'dos pagos, dos obligaciones');
      expect(pagos.complementosRegistrados, 1);
      expect(pagos.complementosPendientes, 1);

      final porFolio = {for (final p in pagos.pagos) p.pago.id: p.estadoComplemento};
      expect(porFolio[pagoA.id], EstadoComplementoPago.registrado);
      expect(porFolio[pagoB.id], EstadoComplementoPago.pendiente);
    });

    test('un complemento CANCELADO no satisface la obligación', () async {
      final cliente = await crearCliente('Sustituto');
      final factura = await crearCuenta(clienteId: cliente, importe: 500000, ppdConComplemento: true);
      final pago = await crearPago(clienteId: cliente, monto: 500000);
      await container
          .read(pagoRepositoryProvider)
          .aplicar(pagoId: pago.id, cuentaPorCobrarId: factura.id, monto: 500000);

      final complementoRepo = container.read(complementoPagoRepositoryProvider);
      final complemento = await complementoRepo.crear(
        pagoId: pago.id,
        uuid: 'UUID-CANCELADO',
        fechaTimbrado: DateTime(2026, 6, 11),
        montoTotal: 500000,
      );
      expect((await analizarPagos()).complementosRegistrados, 1);

      await complementoRepo.cancelar(complementoPagoId: complemento.id, motivo: 'Timbrado con datos erróneos');

      final analisis = await analizarPagos();
      expect(analisis.complementosPendientes, 1, reason: 'un CFDI cancelado no documenta nada');
      expect(analisis.complementosRegistrados, 0);
      expect(analisis.pagos.single.estadoComplemento, EstadoComplementoPago.pendiente);
      expect(analisis.pagos.single.complementoVigenteUuid, isNull);

      // Y un sustituto vigente sí la satisface.
      await complementoRepo.crear(
        pagoId: pago.id,
        uuid: 'UUID-SUSTITUTO',
        fechaTimbrado: DateTime(2026, 6, 12),
        montoTotal: 500000,
      );
      final conSustituto = await analizarPagos();
      expect(conSustituto.pagos.single.estadoComplemento, EstadoComplementoPago.registrado);
      expect(conSustituto.pagos.single.complementoVigenteUuid, 'UUID-SUSTITUTO');
    });

    test('un pago de factura PUE no genera obligación', () async {
      final cliente = await crearCliente('PUE');
      final factura = await crearCuenta(clienteId: cliente, importe: 800000);
      final pago = await crearPago(clienteId: cliente, monto: 800000);
      await container
          .read(pagoRepositoryProvider)
          .aplicar(pagoId: pago.id, cuentaPorCobrarId: factura.id, monto: 800000);

      final analisis = await analizarPagos();
      expect(analisis.pagos.single.estadoComplemento, EstadoComplementoPago.noAplica);
      expect(analisis.complementosPendientes, 0);
    });

    test('la cartera marca la CxC cuyo pago sigue debiendo complemento', () async {
      final cliente = await crearCliente('PPD parcial');
      final factura = await crearCuenta(clienteId: cliente, importe: 1000000, ppdConComplemento: true);
      final pago = await crearPago(clienteId: cliente, monto: 400000);
      await container
          .read(pagoRepositoryProvider)
          .aplicar(pagoId: pago.id, cuentaPorCobrarId: factura.id, monto: 400000);

      final cobranza = await analizarCobranza();
      expect(cobranza.cuentas.single.complementoPendiente, isTrue);
      expect(cobranza.cuentas.single.saldo, 600000);
    });
  });

  group('Deudas y TDC — sin doble conteo', () {
    Future<DeudaData> crearTarjeta({int limite = 50000000, int saldoInicial = 1}) async {
      final r = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'TDC corporativa',
        tipo: TipoDeuda.tarjetaCredito.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: limite,
        saldoInicial: saldoInicial,
        tarjetaLimiteCredito: limite,
        tarjetaDiaCorte: 15,
        tarjetaDiaPago: 5,
        tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diaFijo.name,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
      return (r as RegistrarDeudaExitoso).deuda;
    }

    Future<AnalisisDeuda> analizarDeuda({RangoPeriodo? rango}) {
      return container.read(obtenerAnalisisDeudaUseCaseProvider).ejecutar(
            rango: rango ?? RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
            hoy: hoy,
          );
    }

    test('una Compra con TDC de \$8,000: gasto operativo sube, caja no se mueve, deuda sube', () async {
      final tarjeta = await crearTarjeta();
      final compra = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 6, 10),
            formaPago: 'tarjeta',
            deudaId: tarjeta.id,
            partidas: [
              const PartidaCompraInput(
                destino: 'gastoDirecto',
                concepto: 'Uniformes',
                cantidad: 1,
                costoUnitario: 800000,
              ),
            ],
          );
      expect(compra, isA<RegistrarCompraExitosa>());

      final operativo = await container.read(obtenerAnalisisOperativoUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
          );
      final deuda = await analizarDeuda();

      expect(operativo.gastoOperativo, 800000);
      expect(operativo.salidasDeEfectivo, 0, reason: 'la tarjeta no movió caja');
      expect(deuda.cargosDelPeriodo, 800000);
      expect(deuda.saldoTarjetas, 800001, reason: 'saldo inicial de \$0.01 + el cargo');
    });

    test('pagar la tarjeta mueve caja SIN volver a contar el gasto', () async {
      final tarjeta = await crearTarjeta();
      await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 6, 10),
            formaPago: 'tarjeta',
            deudaId: tarjeta.id,
            partidas: [
              const PartidaCompraInput(
                destino: 'gastoDirecto',
                concepto: 'Uniformes',
                cantidad: 1,
                costoUnitario: 800000,
              ),
            ],
          );
      final pago = await container.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: tarjeta.id,
        fecha: DateTime(2026, 6, 20),
        importe: 800000,
        formaPago: 'transferencia',
      );
      expect(pago, isA<RegistrarPagoDeudaExitoso>());

      final operativo = await container.read(obtenerAnalisisOperativoUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
          );
      final deuda = await analizarDeuda();

      expect(operativo.gastoOperativo, 800000, reason: 'JAMÁS 1,600,000: el gasto se reconoció al comprar');
      expect(operativo.salidasDeEfectivo, 800000, reason: 'pagar la tarjeta SÍ es salida de caja');
      expect(deuda.pagosDelPeriodo, 800000);
      expect(deuda.saldoTarjetas, 1, reason: 'sólo queda el saldo inicial de apertura');
    });

    test('utilización y crédito disponible salen del límite real, nunca asumiendo cero', () async {
      final tarjeta = await crearTarjeta(limite: 10000000, saldoInicial: 2500000);

      final deuda = await analizarDeuda();
      final proyectada = deuda.tarjetas.single;

      expect(proyectada.deuda.id, tarjeta.id);
      expect(proyectada.limite, 10000000);
      expect(proyectada.disponible, 7500000);
      expect(proyectada.utilizacion, closeTo(0.25, 0.0001));
      expect(deuda.utilizacionGlobal, closeTo(0.25, 0.0001));
      expect(proyectada.proximoCorte, isNotNull);
      expect(proyectada.proximaFechaLimite, isNotNull);
    });

    test('una tarjeta SIN límite capturado no aporta al límite total ni finge disponible', () async {
      final r = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'TDC sin límite',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 500000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
      expect(r, isA<RegistrarDeudaExitoso>());

      final deuda = await analizarDeuda();
      expect(deuda.tarjetas.single.disponible, isNull, reason: 'no saber el límite no es tener \$0 de crédito');
      expect(deuda.limiteTotal, 0);
      expect(deuda.utilizacionGlobal, isNull);
      expect(deuda.saldoTarjetas, 500000, reason: 'el saldo sí es conocido');
    });

    test('un préstamo no suma su importe al límite de crédito de tarjetas', () async {
      await crearTarjeta(limite: 10000000, saldoInicial: 1000000);
      final prestamo = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'Préstamo bancario',
        tipo: TipoDeuda.prestamo.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 30000000,
        saldoInicial: 30000000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
      expect(prestamo, isA<RegistrarDeudaExitoso>());

      final deuda = await analizarDeuda();
      expect(deuda.limiteTotal, 10000000, reason: 'un préstamo no es una línea revolvente');
      expect(deuda.saldoTarjetas, 1000000);
      expect(deuda.saldoOtrasDeudas, 30000000);
      expect(deuda.saldoTotal, 31000000);
    });

    test('el origen de cada movimiento se resuelve por FK, nunca por descripción', () async {
      final tarjeta = await crearTarjeta();
      await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 6, 10),
            formaPago: 'tarjeta',
            deudaId: tarjeta.id,
            partidas: [
              const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'X', cantidad: 1, costoUnitario: 500000),
            ],
          );
      await container.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: tarjeta.id,
        fecha: DateTime(2026, 6, 20),
        importe: 200000,
        formaPago: 'transferencia',
      );

      final deuda = await analizarDeuda();
      final porTipo = {for (final m in deuda.movimientos) m.tipo: m};

      expect(porTipo[TipoMovimientoDeuda.cargoCompra]!.origen, OrigenMovimientoDeuda.compra);
      expect(porTipo[TipoMovimientoDeuda.cargoCompra]!.efectoEnSaldo, 500000);
      expect(porTipo[TipoMovimientoDeuda.pago]!.origen, OrigenMovimientoDeuda.pago);
      expect(porTipo[TipoMovimientoDeuda.pago]!.efectoEnSaldo, -200000, reason: 'el tipo da el signo, no el importe');
    });

    test('cancelar una compra con TDC deja el cargo neto del periodo en cero', () async {
      final tarjeta = await crearTarjeta();
      await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 6, 10),
            formaPago: 'tarjeta',
            deudaId: tarjeta.id,
            partidas: [
              const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'X', cantidad: 1, costoUnitario: 700000),
            ],
          );
      final compra = (await db.select(db.compra).get()).single;
      await container.read(comprasControllerProvider.notifier).cancelarCompra(
            compraId: compra.id,
            motivo: MotivoCancelacionCompra.proveedorCancelo,
          );

      // El ajuste de reversión se fecha el día en que se cancela, no
      // retroactivamente al de la compra — así que el rango tiene que
      // cubrir ambos hechos para ver el neto. Con un rango que sólo
      // cubriera junio, el cargo aparecería sin su reversión, y eso
      // sería correcto: el periodo realmente tuvo ese cargo.
      final anioCompleto = RangoPeriodo(inicio: DateTime(2026, 1, 1), fin: DateTime(2026, 12, 31));
      final operativo =
          await container.read(obtenerAnalisisOperativoUseCaseProvider).ejecutar(rango: anioCompleto);
      final deuda = await analizarDeuda(rango: anioCompleto);

      expect(operativo.gastoOperativo, 0, reason: 'el ajuste netea el cargo original');
      expect(deuda.cargosDelPeriodo + deuda.ajustesDelPeriodo, 0,
          reason: 'cargo +700,000 y ajuste −700,000 se anulan');
      expect(deuda.saldoTarjetas, 1);
    });

    test('sin deudas registradas el análisis viene vacío, no en ceros inventados', () async {
      final deuda = await analizarDeuda();
      expect(deuda.deudas, isEmpty);
      expect(deuda.tarjetas, isEmpty);
      expect(deuda.hayTarjetas, isFalse, reason: 'distinto de "hay tarjetas con \$0 disponible"');
      expect(deuda.utilizacionGlobal, isNull);
    });
  });
}
