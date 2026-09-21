// Servicios Eventuales — Rebanada 3: el tratamiento de IVA.
//
// Lo que se protege: **una sola definición de "venta"**. El total que
// deriva el dominio es el mismo número que viaja a la Cuenta por
// cobrar, al documento fiscal y al cobro. Y la tasa y el redondeo son
// los que ya usaba la cobranza recurrente — aquí no hay un 0.16 nuevo.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_totales_esperados_usecase.dart'
    show tasaIvaMasIva;
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/corregir_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/listar_servicios_eventuales_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';

void main() {
  group('La derivación pura', () {
    test('Más IVA: el capturado es la base y el total lleva el impuesto encima', () {
      final t = calcularTotalesVentaEventual(
        importeAcordado: 1000000,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(t.subtotal, 1000000);
      expect(t.iva, 160000);
      expect(t.total, 1160000);
    });

    test('IVA incluido: el capturado es el total y el desglose lo explica', () {
      final t = calcularTotalesVentaEventual(
        importeAcordado: 1160000,
        tratamientoIva: TratamientoIva.ivaIncluido,
      );
      expect(t.subtotal, 1000000);
      expect(t.iva, 160000);
      expect(t.total, 1160000);
    });

    test('No aplica: base y total son el mismo número, sin impuesto', () {
      final t = calcularTotalesVentaEventual(
        importeAcordado: 1000000,
        tratamientoIva: TratamientoIva.noAplica,
      );
      expect(t.subtotal, 1000000);
      expect(t.iva, 0);
      expect(t.total, 1000000);
    });

    test('la tasa sale de la fuente de verdad de Comercial, no de una copia', () {
      // Si algún día la tasa cambia ahí, esta prueba sigue siendo
      // cierta — justamente porque no la teclea.
      final base = 777777;
      final t = calcularTotalesVentaEventual(
        importeAcordado: base,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(t.total, base + (base * tasaIvaMasIva + 0.5).floor());
    });

    group('redondeo con fracciones de centavo', () {
      test('Más IVA de un importe que no divide exacto', () {
        // 333.33 × 0.16 = 53.3328 → 53.33
        final t = calcularTotalesVentaEventual(
          importeAcordado: 33333,
          tratamientoIva: TratamientoIva.masIva,
        );
        expect(t.iva, 5333);
        expect(t.total, 38666);
        expect(t.subtotal + t.iva, t.total, reason: 'base + IVA siempre cuadra con el total');
      });

      test('IVA incluido nunca deja un centavo huérfano', () {
        // El caso feo: 1,000.01 no tiene una base exacta a 16 %.
        for (final total in [100001, 100003, 999999, 1, 7, 12345]) {
          final t = calcularTotalesVentaEventual(
            importeAcordado: total,
            tratamientoIva: TratamientoIva.ivaIncluido,
          );
          expect(
            t.subtotal + t.iva,
            t.total,
            reason: 'con total $total la suma del desglose debe dar exactamente el total',
          );
          expect(t.total, total, reason: 'el total capturado nunca se altera');
        }
      });
    });
  });

  group('La cadena completa', () {
    late AppDatabase db;
    late CuentaPorCobrarRepositoryImpl cuentaRepo;
    late PagoRepositoryImpl pagoRepo;
    late ServicioEventualRepositoryImpl repo;
    late CrearServicioEventualUseCase crear;
    late CorregirServicioEventualUseCase corregir;
    late RegistrarCobroServicioEventualUseCase cobrar;
    late RegistrarDocumentoFiscalEventualUseCase facturar;
    late ListarServiciosEventualesUseCase listar;
    late CuentaFinancieraData cuentaBanco;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final codigoSecuencia = CodigoSecuenciaService(db);
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
      pagoRepo = PagoRepositoryImpl(db);
      final clienteRepo = ClienteRepositoryImpl(db);
      repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, cuentaRepo, pagoRepo);

      crear = CrearServicioEventualUseCase(repo, clienteRepo, EntidadFiscalRepositoryImpl(db));
      corregir = CorregirServicioEventualUseCase(repo, cuentaRepo, pagoRepo);
      cobrar = RegistrarCobroServicioEventualUseCase(
        repo,
        RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, GenerarCodigoUseCase(codigoSecuencia)),
      );
      facturar = RegistrarDocumentoFiscalEventualUseCase(
        ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo),
        repo,
        cuentaRepo,
        EntidadFiscalRepositoryImpl(db),
      );
      listar = ListarServiciosEventualesUseCase(repo, clienteRepo, cuentaRepo);

      cuentaBanco = await db.into(db.cuentaFinanciera).insertReturning(
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

    Future<CrearServicioEventualExitoso> vender({
      required int importe,
      required TratamientoIva tratamiento,
      bool conFactura = false,
      MetodoPagoCobro metodo = MetodoPagoCobro.noAplica,
      CobroInmediatoServicioEventual? cobroInmediato,
    }) async {
      final resultado = await crear.ejecutar(
        nombre: 'Evento',
        fechaHoraInicio: DateTime(2026, 5, 1),
        fechaHoraFin: DateTime(2026, 5, 2),
        importeAcordado: importe,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'Promotora Norte',
        requiereFactura: conFactura,
        solicitanteRazonSocial: conFactura ? 'Promotora Norte S.A. de C.V.' : null,
        solicitanteRfc: conFactura ? 'PNO010101AB1' : null,
        solicitanteCodigoPostalFiscal: conFactura ? '64000' : null,
        tratamientoIva: tratamiento,
        metodoCobro: metodo,
        cobroInmediato: cobroInmediato,
      );
      return resultado as CrearServicioEventualExitoso;
    }

    test('la CxC nace con el TOTAL derivado, nunca con el importe capturado', () async {
      final venta = await vender(importe: 1000000, tratamiento: TratamientoIva.masIva);

      expect(venta.servicioEventual.importeAcordado, 1000000, reason: 'se conserva lo capturado');
      expect(venta.cuenta.importeEmitido, 1160000);
      expect(venta.cuenta.saldoOriginal, 1160000);
      expect(venta.cuenta.saldoPendiente, 1160000);
    });

    test('el documento fiscal usa el mismo total, no la base', () async {
      final venta = await vender(
        importe: 1000000,
        tratamiento: TratamientoIva.masIva,
        conFactura: true,
        metodo: MetodoPagoCobro.pue,
      );
      final factura = await facturar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        folio: 'A-1',
        fechaEmision: DateTime(2026, 5, 4),
        metodo: MetodoPagoCobro.pue,
        razonSocialManual: 'Promotora Norte SA',
        rfcManual: 'PRN123456AB1',
      );
      final documento = (factura as RegistrarDocumentoFiscalEventualExitoso).documento;

      expect(documento.importe, 1160000);
      expect(documento.importe, venta.cuenta.importeEmitido, reason: 'una sola definición de venta');
    });

    test('el cobro completo acepta exactamente el total con IVA', () async {
      final venta = await vender(importe: 1000000, tratamiento: TratamientoIva.masIva);

      final cobro = await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 1160000,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaBanco.id,
      );
      expect(cobro, isA<RegistrarCobroServicioEventualExitoso>());
      expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.saldoPendiente, 0);
    });

    test('cobrar por encima del total se sigue rechazando por la regla existente', () async {
      final venta = await vender(importe: 1000000, tratamiento: TratamientoIva.masIva);
      final resultado = await cobrar.ejecutar(
        servicioEventualId: venta.servicioEventual.id,
        monto: 1160001,
        fechaPago: DateTime(2026, 5, 10),
        formaPago: FormaPago.transferencia.name,
      );
      expect(resultado, isA<RegistrarCobroServicioEventualRechazado>());
      expect(
        (resultado as RegistrarCobroServicioEventualRechazado).motivo,
        isA<RegistrarPagoAplicadoSobrepago>(),
      );
    });

    test('el cobro inmediato se valida contra el total, no contra la base', () async {
      // 1,160,000 excede lo capturado (1,000,000) pero NO el total: con
      // la regla vieja esto se habría rechazado por "sobrepago".
      final venta = await vender(
        importe: 1000000,
        tratamiento: TratamientoIva.masIva,
        cobroInmediato: CobroInmediatoServicioEventual(
          monto: 1160000,
          fechaPago: DateTime(2026, 5, 1),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        ),
      );
      expect(venta.pago, isNotNull);
      expect(venta.cuenta.saldoPendiente, 0);
    });

    test('el resultado del listado usa el total bruto, la misma convención que Finanzas', () async {
      await vender(importe: 1000000, tratamiento: TratamientoIva.masIva);
      final renglon = (await listar.ejecutar()).single;

      expect(renglon.totalVenta, 1160000);
      // Sin costos todavía: el resultado ES la venta bruta. Es la misma
      // convención de `Ingreso.monto`/`Egreso.monto`, que también son
      // importes brutos.
      expect(renglon.resultado, 1160000);
    });

    group('corrección', () {
      test('sin pago, cambiar el tratamiento recalcula el total de la CxC', () async {
        final venta = await vender(importe: 1000000, tratamiento: TratamientoIva.noAplica);
        expect(venta.cuenta.importeEmitido, 1000000);

        final resultado = await corregir.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          tratamientoIva: TratamientoIva.masIva,
          motivo: 'Se acordó más IVA',
        );
        expect(resultado, isA<CorregirServicioEventualExitoso>());

        final cuenta = (await cuentaRepo.obtenerPorId(venta.cuenta.id))!;
        expect(cuenta.importeEmitido, 1160000);
        expect(cuenta.saldoPendiente, 1160000);
      });

      test('sin pago, cambiar el importe recalcula respetando el tratamiento', () async {
        final venta = await vender(importe: 1000000, tratamiento: TratamientoIva.masIva);
        await corregir.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          importeAcordado: 2000000,
          motivo: 'Se renegoció',
        );
        expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.importeEmitido, 2320000);
      });

      test('con un pago aplicado, cambiar el TRATAMIENTO se rechaza', () async {
        final venta = await vender(
          importe: 1160000,
          tratamiento: TratamientoIva.ivaIncluido,
          cobroInmediato: CobroInmediatoServicioEventual(
            monto: 1160000,
            fechaPago: DateTime(2026, 5, 1),
            formaPago: FormaPago.transferencia.name,
            cuentaFinancieraId: cuentaBanco.id,
          ),
        );

        // De "IVA incluido" a "más IVA" el total saltaría de 1,160,000 a
        // 1,345,600 — mover el total por la puerta de atrás.
        final resultado = await corregir.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          tratamientoIva: TratamientoIva.masIva,
          motivo: 'Intento',
        );
        expect(resultado, isA<CorregirServicioEventualImporteBloqueadoPorPago>());

        final eventual = (await repo.obtenerPorId(venta.servicioEventual.id))!;
        expect(eventual.tratamientoIva, TratamientoIva.ivaIncluido.name);
        expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.importeEmitido, 1160000);
      });

      test('con un pago aplicado, cambiar el IMPORTE se rechaza igual', () async {
        final venta = await vender(
          importe: 1000000,
          tratamiento: TratamientoIva.noAplica,
          cobroInmediato: CobroInmediatoServicioEventual(
            monto: 1000000,
            fechaPago: DateTime(2026, 5, 1),
            formaPago: FormaPago.transferencia.name,
            cuentaFinancieraId: cuentaBanco.id,
          ),
        );
        expect(
          await corregir.ejecutar(
            servicioEventualId: venta.servicioEventual.id,
            importeAcordado: 2000000,
            motivo: 'Intento',
          ),
          isA<CorregirServicioEventualImporteBloqueadoPorPago>(),
        );
      });
    });

    test('IVA y factura son independientes: sin factura se puede acordar más IVA', () async {
      final venta = await vender(importe: 1000000, tratamiento: TratamientoIva.masIva);
      expect(venta.servicioEventual.requiereFactura, isFalse);
      expect(venta.servicioEventual.tratamientoIva, TratamientoIva.masIva.name);
      expect(venta.cuenta.importeEmitido, 1160000);
      expect(venta.cuenta.metodo, MetodoPagoCobro.noAplica.name);
    });

    test('con factura se puede acordar que el IVA no aplica', () async {
      final venta = await vender(
        importe: 1000000,
        tratamiento: TratamientoIva.noAplica,
        conFactura: true,
        metodo: MetodoPagoCobro.pue,
      );
      expect(venta.servicioEventual.tratamientoIva, TratamientoIva.noAplica.name);
      expect(venta.cuenta.importeEmitido, 1000000);
    });

    test('una fila con la semántica legacy conserva su total', () async {
      // Lo que la migración deja: `tratamientoIva` en el default.
      final eventual = await db.into(db.servicioEventual).insertReturning(
            ServicioEventualCompanion.insert(
              folio: 'EVT-LEGACY',
              nombre: 'Evento anterior a la v89',
              fechaHoraInicio: DateTime(2026, 1, 1),
              fechaHoraFin: DateTime(2026, 1, 2),
              importeAcordado: 777777,
              tipoSolicitante: TipoSolicitanteServicioEventual.eventual.name,
              solicitanteNombre: const Value('Promotora'),
            ),
          );
      expect(eventual.tratamientoIva, tratamientoIvaLegacyEventual.name);
      expect(
        totalVentaEventual(
          importeAcordado: eventual.importeAcordado,
          tratamientoIva: TratamientoIva.values.byName(eventual.tratamientoIva),
        ),
        777777,
        reason: 'en la v88 importeAcordado ERA el total: el derivado tiene que dar lo mismo',
      );
    });
  });
}
