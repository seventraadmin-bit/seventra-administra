// Etapa 9 — "Deudas y crédito: corrección y cancelación individual de
// pagos". Pruebas de dominio/repositorio contra BD real (nunca mocks),
// en el orden del pedido de Marlon.
//
// Distinción que atraviesa toda la etapa y que ninguna prueba debe
// dejar de proteger:
//   MovimientoDeuda.egresoId      = Egreso generado al PAGAR la deuda.
//   MovimientoDeuda.egresoGastoId = Egreso-documento de un GASTO
//                                   financiado con la tarjeta.
// Corregir o cancelar un pago solo toca la primera; los cargos de la
// tarjeta quedan intactos.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresoRepo;
  late DeudaRepository deudaRepo;
  late CuentaFinancieraRepositoryImpl cuentaRepo;
  late RegistrarDeudaUseCase registrarDeuda;
  late RegistrarPagoDeudaUseCase registrarPago;
  late CorregirPagoDeudaUseCase corregirPago;
  late CancelarPagoDeudaUseCase cancelarPago;
  late RegistrarEgresoUseCase registrarEgreso;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaFinancieraRepositoryImpl(db);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    registrarPago = RegistrarPagoDeudaUseCase(deudaRepo, generarCodigo);
    corregirPago = CorregirPagoDeudaUseCase(deudaRepo);
    cancelarPago = CancelarPagoDeudaUseCase(deudaRepo);
    registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo);
  });

  tearDown(() => db.close());

  Future<CuentaFinancieraData> crearCuenta(String nombre, String codigo, int saldoInicial) {
    return cuentaRepo.crear(
      codigo: codigo,
      nombre: nombre,
      tipo: 'banco',
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
  }

  Future<DeudaData> crearPrestamo({required int saldo}) async {
    final r = await registrarDeuda.ejecutar(
      nombre: 'SANDRA PRESTAMO PERSONAL',
      tipo: 'prestamo',
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: saldo,
      saldoInicial: saldo,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
    return (r as RegistrarDeudaExitoso).deuda;
  }

  Future<DeudaData> crearTarjeta({
    required int limite,
    required int saldoInicial,
    int? diaCorte,
    int? diasDespuesCorte,
  }) async {
    final r = await registrarDeuda.ejecutar(
      nombre: 'TDC Konfío Empresarial',
      tipo: 'tarjetaCredito',
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime(2026, 1, 1),
      tarjetaLimiteCredito: limite,
      tarjetaDiaCorte: diaCorte,
      tarjetaDiasDespuesCorte: diasDespuesCorte,
      tarjetaReglaFechaPago: diaCorte == null ? null : ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
    );
    return (r as RegistrarDeudaExitoso).deuda;
  }

  Future<MovimientoDeudaData> pagar({
    required String deudaId,
    required int importe,
    required String cuentaId,
    DateTime? fecha,
  }) async {
    final r = await registrarPago.ejecutar(
      deudaId: deudaId,
      fecha: fecha ?? DateTime(2026, 3, 5),
      importe: importe,
      formaPago: 'transferencia',
      cuentaFinancieraId: cuentaId,
    );
    expect(r, isA<RegistrarPagoDeudaExitoso>());
    final movimientos = await deudaRepo.listarMovimientos(deudaId);
    return movimientos.lastWhere((m) => m.tipo == TipoMovimientoDeuda.pago.name);
  }

  Future<DeudaData> recargar(String id) async => (await deudaRepo.obtenerPorId(id))!;
  int? disponibleDe(DeudaData t) =>
      creditoDisponibleTarjeta(limiteCredito: t.tarjetaLimiteCredito, saldoActual: t.saldoActual);

  group('Punto 1 — identidad del pago', () {
    test('MovimientoDeuda.id identifica el pago sin ambigüedad y lo liga a su Egreso por egresoId', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);

      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      expect(pago.tipo, TipoMovimientoDeuda.pago.name);
      expect(pago.egresoId, isNotNull, reason: 'el Egreso del PAGO va en egresoId');
      expect(pago.egresoGastoId, isNull, reason: 'egresoGastoId es de un GASTO con TDC, nunca de un pago');
      expect(pago.saldoAnterior, 1500000);
      expect(pago.saldoPosterior, 1000000);

      final recuperado = await deudaRepo.obtenerMovimiento(pago.id);
      expect(recuperado!.id, pago.id);

      final estado = await deudaRepo.obtenerEstadoPago(pago.id);
      expect(estado.existe, isTrue);
      expect(estado.cancelado, isFalse);
      expect(estado.importeNeto, 500000);
    });

    test('un id que no es de un pago (un cargo) se reporta como inexistente, nunca revienta', () async {
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 0);
      await registrarEgreso.ejecutar(
        monto: 135998,
        fecha: DateTime(2026, 3, 5),
        formaPago: 'tarjeta',
        concepto: 'gasolina',
        origen: OrigenFinancieroTarjeta(tarjeta.id),
      );
      final cargo = (await deudaRepo.listarMovimientos(tarjeta.id))
          .firstWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);

      expect((await deudaRepo.obtenerEstadoPago(cargo.id)).existe, isFalse);
      expect(await corregirPago.ejecutar(pagoId: cargo.id, motivo: 'x'), isA<CorregirPagoDeudaNoExiste>());
      expect(await cancelarPago.ejecutar(pagoId: cargo.id, motivo: 'x'), isA<CancelarPagoDeudaNoExiste>());
    });
  });

  group('Puntos 2-4 — corregir monto: ledger append-only y Egreso sincronizado', () {
    test('\$5,000 → \$4,500: deuda +\$500, BBVA recupera \$500, Egreso final \$4,500, historial intacto', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 2000000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      expect((await recargar(deuda.id)).saldoActual, 1500000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1500000);

      final r = await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'Se capturó de más');
      expect(r, isA<CorregirPagoDeudaExitoso>());

      expect((await recargar(deuda.id)).saldoActual, 1550000, reason: 'saldo deuda = \$15,500');
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1550000, reason: 'BBVA recupera \$500');

      final egreso = await egresoRepo.obtenerPorId(pago.egresoId!);
      expect(egreso!.monto, 450000, reason: 'el Egreso representa la MISMA realidad que el pago');
      expect(egreso.estatus, 'registrado', reason: 'nunca se cancela y recrea');

      // Ledger append-only: el pago original conserva su importe.
      final original = await deudaRepo.obtenerMovimiento(pago.id);
      expect(original!.importe, 500000, reason: 'el historial conserva que originalmente se capturaron \$5,000');
      final ajustes = await deudaRepo.listarMovimientosDePago(pago.id);
      expect(ajustes, hasLength(1));
      expect(ajustes.single.tipo, TipoMovimientoDeuda.ajustePositivo.name);
      expect(ajustes.single.importe, 50000);
      expect(ajustes.single.movimientoOrigenId, pago.id);

      // Cero doble conteo: "Pagado" es el neto, no el importe original.
      expect((await deudaRepo.totalPagadoPorDeuda())[deuda.id], 450000);
      expect((await deudaRepo.obtenerEstadoPago(pago.id)).importeNeto, 450000);
    });

    test('\$5,000 → \$6,000: deuda baja otros \$1,000 y BBVA baja otros \$1,000', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 2000000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 600000, motivo: 'Faltaba un cargo');

      expect((await recargar(deuda.id)).saldoActual, 1400000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1400000);
      expect((await egresoRepo.obtenerPorId(pago.egresoId!))!.monto, 600000);

      final ajustes = await deudaRepo.listarMovimientosDePago(pago.id);
      expect(ajustes.single.tipo, TipoMovimientoDeuda.ajusteNegativo.name);
      expect(ajustes.single.importe, 100000);
    });
  });

  group('Punto 5 — cambio de CuentaFinanciera', () {
    test('BBVA → Klar: BBVA recupera todo, Klar disminuye, saldo de la Deuda NO cambia', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final klar = await crearCuenta('Klar', 'CTA-0002', 1000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      final saldoDeudaAntes = (await recargar(deuda.id)).saldoActual;
      await corregirPago.ejecutar(
        pagoId: pago.id,
        nuevaCuentaFinancieraId: klar.id,
        motivo: 'Salió de Klar, no de BBVA',
      );

      expect(await cuentaRepo.calcularSaldo(bbva.id), 2000000, reason: 'BBVA recupera \$5,000');
      expect(await cuentaRepo.calcularSaldo(klar.id), 500000, reason: 'Klar disminuye \$5,000');
      expect((await recargar(deuda.id)).saldoActual, saldoDeudaAntes, reason: 'mismo pago lógico');

      final egreso = await egresoRepo.obtenerPorId(pago.egresoId!);
      expect(egreso!.id, pago.egresoId, reason: 'MISMO Egreso, nunca uno nuevo');
      expect(egreso.cuentaFinancieraId, klar.id);
      expect(egreso.monto, 500000);
    });
  });

  group('Punto 6 — cambio simultáneo de cuenta e importe', () {
    test('BBVA \$5,000 → Klar \$4,500 en una sola operación', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final klar = await crearCuenta('Klar', 'CTA-0002', 1000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      await corregirPago.ejecutar(
        pagoId: pago.id,
        nuevoImporte: 450000,
        nuevaCuentaFinancieraId: klar.id,
        motivo: 'Cuenta e importe equivocados',
      );

      expect(await cuentaRepo.calcularSaldo(bbva.id), 2000000);
      expect(await cuentaRepo.calcularSaldo(klar.id), 1000000 - 450000);
      expect((await recargar(deuda.id)).saldoActual, 1050000, reason: 'la deuda recupera \$500');
      expect((await egresoRepo.obtenerPorId(pago.egresoId!))!.monto, 450000);
    });
  });

  group('Punto 7 — sobrepago', () {
    test('registrar un pago mayor al saldo se rechaza (regresión de la regla vigente)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 500000);

      final r = await registrarPago.ejecutar(
        deudaId: deuda.id,
        fecha: DateTime(2026, 3, 5),
        importe: 600000,
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
      );
      expect(r, isA<RegistrarPagoDeudaSobrepasaSaldo>());
    });

    test('corregir un pago por encima del máximo se rechaza, sin crear saldo a favor ni Ingreso', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1000000);
      final pago = await pagar(deudaId: deuda.id, importe: 300000, cuentaId: bbva.id);

      final r = await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 1500000, motivo: 'Imposible');

      expect(r, isA<CorregirPagoDeudaSobrepasaSaldo>());
      // El máximo es saldo actual (700,000) + lo que este pago ya
      // ocupaba (300,000): comparar contra el saldo a secas sería
      // ingenuo.
      expect((r as CorregirPagoDeudaSobrepasaSaldo).importeMaximo, 1000000);
      expect((await recargar(deuda.id)).saldoActual, 700000, reason: 'nada cambió');
      expect(await db.select(db.ingreso).get(), isEmpty, reason: 'jamás se crea un Ingreso compensatorio');
    });

    test('corregir hasta el máximo exacto sí se permite (liquida la deuda)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1000000);
      final pago = await pagar(deudaId: deuda.id, importe: 300000, cuentaId: bbva.id);

      final r = await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 1000000, motivo: 'Pagó todo');

      expect(r, isA<CorregirPagoDeudaExitoso>());
      final actualizada = await recargar(deuda.id);
      expect(actualizada.saldoActual, 0);
      expect(actualizada.estatus, EstatusDeuda.liquidada.name);
    });
  });

  group('Punto 8 — liquidada ↔ activa', () {
    test('liquidar, corregir a la baja devuelve a activa, y cancelar la deja activa con el saldo completo', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      var actual = await recargar(deuda.id);
      expect(actual.saldoActual, 0);
      expect(actual.estatus, EstatusDeuda.liquidada.name);

      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'Se pagó menos');
      actual = await recargar(deuda.id);
      expect(actual.saldoActual, 50000);
      expect(actual.estatus, EstatusDeuda.activa.name, reason: 'nunca queda liquidada con saldo > 0');

      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'El pago nunca ocurrió');
      actual = await recargar(deuda.id);
      expect(actual.saldoActual, 500000);
      expect(actual.estatus, EstatusDeuda.activa.name);
    });
  });

  group('Punto 12 — cancelar pago', () {
    test('revierte saldo, Egreso, cuenta y estatus; conserva el movimiento original', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      final r = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Duplicado');
      expect(r, isA<CancelarPagoDeudaExitoso>());

      expect((await recargar(deuda.id)).saldoActual, 1500000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 2000000);
      expect((await egresoRepo.obtenerPorId(pago.egresoId!))!.estatus, 'cancelado');

      final original = await deudaRepo.obtenerMovimiento(pago.id);
      expect(original, isNotNull, reason: 'el movimiento NUNCA se borra');
      expect(original!.importe, 500000);

      final estado = await deudaRepo.obtenerEstadoPago(pago.id);
      expect(estado.cancelado, isTrue);
      expect(estado.importeNeto, 0);
      expect((await deudaRepo.totalPagadoPorDeuda())[deuda.id] ?? 0, 0);
    });

    test('una segunda cancelación es un error tipado, nunca una doble reversión', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Primera');
      final segunda = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Segunda');

      expect(segunda, isA<CancelarPagoDeudaYaCancelado>());
      expect((await recargar(deuda.id)).saldoActual, 1500000, reason: 'nunca se pasa del saldo original');
      final reversiones = (await deudaRepo.listarMovimientosDePago(pago.id))
          .where((m) => m.tipo == TipoMovimientoDeuda.reversionPago.name);
      expect(reversiones, hasLength(1));
    });

    test('corregir un pago ya cancelado se rechaza', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelado');
      expect(
        await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 100000, motivo: 'Tarde'),
        isA<CorregirPagoDeudaCancelado>(),
      );
    });

    test('cancelar un pago YA CORREGIDO revierte solo su neto vivo', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'Corrección');
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelación');

      expect((await recargar(deuda.id)).saldoActual, 1500000, reason: 'exactamente el saldo previo al pago');
      expect(await cuentaRepo.calcularSaldo(bbva.id), 2000000);
    });
  });

  group('Punto 13 — auditoría', () {
    test('la corrección deja actor, motivo, vínculo al pago y saldo antes/después', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final actor = await db.into(db.usuario).insertReturning(
            UsuarioCompanion.insert(
              nombre: 'Auditor',
              nombreUsuario: 'auditor',
              passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            ),
          );
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      await corregirPago.ejecutar(
        pagoId: pago.id,
        nuevoImporte: 450000,
        nuevaCuentaFinancieraId: bbva.id,
        motivo: 'Se capturó de más',
        actorUsuarioId: actor.id,
      );

      final ajuste = (await deudaRepo.listarMovimientosDePago(pago.id)).single;
      expect(ajuste.actorUsuarioId, actor.id);
      expect(ajuste.observaciones, 'Se capturó de más');
      expect(ajuste.movimientoOrigenId, pago.id);
      expect(ajuste.saldoAnterior, 1000000);
      expect(ajuste.saldoPosterior, 1050000);

      // El Egreso guarda el antes/después del monto en su evento.
      final eventos = await egresoRepo.listarEventos(pago.egresoId!);
      final corregido = eventos.lastWhere((e) => e.tipoEvento == 'corregido');
      expect(corregido.observacion, 'Se capturó de más');
      expect(corregido.actorUsuarioId, actor.id);
    });
  });

  group('Punto 17 — caso integral préstamo', () {
    test('recorre pago, 2 correcciones, cambio de cuenta y cancelación con cifras exactas', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final klar = await crearCuenta('Klar', 'CTA-0002', 1000000);
      final deuda = await crearPrestamo(saldo: 1500000);

      Future<void> verificar(int esperadoBbva, int esperadoKlar, int esperadaDeuda, String etapa) async {
        expect(await cuentaRepo.calcularSaldo(bbva.id), esperadoBbva, reason: '$etapa — BBVA');
        expect(await cuentaRepo.calcularSaldo(klar.id), esperadoKlar, reason: '$etapa — Klar');
        expect((await recargar(deuda.id)).saldoActual, esperadaDeuda, reason: '$etapa — deuda');
      }

      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);
      await verificar(1500000, 1000000, 1000000, 'tras el pago de \$5,000');

      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'A \$4,500');
      await verificar(1550000, 1000000, 1050000, 'tras corregir a \$4,500');

      await corregirPago.ejecutar(pagoId: pago.id, nuevaCuentaFinancieraId: klar.id, motivo: 'Salió de Klar');
      await verificar(2000000, 550000, 1050000, 'tras mover a Klar');

      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 600000, motivo: 'A \$6,000');
      await verificar(2000000, 400000, 900000, 'tras corregir a \$6,000');

      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelado');
      await verificar(2000000, 1000000, 1500000, 'tras cancelar');
    });
  });

  group('Puntos 9/10/18 — TDC: crédito disponible y cargos intactos', () {
    test('caso integral TDC con cifras exactas, sin tocar los cargos de gasto', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final klar = await crearCuenta('Klar', 'CTA-0002', 1000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 3326608 - 135998);

      // Un gasto real financiado con la tarjeta: NUNCA debe verse
      // afectado por corregir o cancelar el pago mensual (punto 10).
      final gasto = await registrarEgreso.ejecutar(
        monto: 135998,
        fecha: DateTime(2026, 3, 1),
        formaPago: 'tarjeta',
        concepto: 'gasolina',
        origen: OrigenFinancieroTarjeta(tarjeta.id),
      );
      final egresoGasto = (gasto as RegistrarEgresoExitoso).egreso;
      final cargo = (await deudaRepo.listarMovimientos(tarjeta.id))
          .firstWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);

      expect((await recargar(tarjeta.id)).saldoActual, 3326608);
      expect(disponibleDe(await recargar(tarjeta.id)), 673392);

      Future<void> verificarGastoIntacto(String etapa) async {
        final egresoActual = await egresoRepo.obtenerPorId(egresoGasto.id);
        expect(egresoActual!.estatus, 'registrado', reason: '$etapa — el gasto sigue vivo');
        expect(egresoActual.deudaId, tarjeta.id);
        final cargoActual = await deudaRepo.obtenerMovimiento(cargo.id);
        expect(cargoActual!.importe, 135998, reason: '$etapa — el cargo nunca se toca');
        expect(cargoActual.egresoGastoId, egresoGasto.id);
        expect(await deudaRepo.netoAportadoPorEgreso(deudaId: tarjeta.id, egresoId: egresoGasto.id), 135998);
      }

      // Pago $5,000 desde BBVA.
      final pago = await pagar(deudaId: tarjeta.id, importe: 500000, cuentaId: bbva.id);
      expect((await recargar(tarjeta.id)).saldoActual, 2826608);
      expect(disponibleDe(await recargar(tarjeta.id)), 1173392);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1500000);
      await verificarGastoIntacto('tras el pago');

      // Corregir a $4,500.
      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'A \$4,500');
      expect((await recargar(tarjeta.id)).saldoActual, 2876608);
      expect(disponibleDe(await recargar(tarjeta.id)), 1123392);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1550000, reason: 'Caja refleja exactamente \$4,500 de salida');
      await verificarGastoIntacto('tras corregir');

      // Mover a Klar.
      await corregirPago.ejecutar(pagoId: pago.id, nuevaCuentaFinancieraId: klar.id, motivo: 'Salió de Klar');
      expect(await cuentaRepo.calcularSaldo(bbva.id), 2000000);
      expect(await cuentaRepo.calcularSaldo(klar.id), 550000);
      expect((await recargar(tarjeta.id)).saldoActual, 2876608, reason: 'cambiar de cuenta no mueve la tarjeta');
      await verificarGastoIntacto('tras mover de cuenta');

      // Cancelar: todo vuelve al inicio.
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelado');
      expect((await recargar(tarjeta.id)).saldoActual, 3326608);
      expect(disponibleDe(await recargar(tarjeta.id)), 673392);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 2000000);
      expect(await cuentaRepo.calcularSaldo(klar.id), 1000000);
      await verificarGastoIntacto('tras cancelar');
    });

    test('corregir un pago de TDC nunca entra en el gasto operativo (cargosTarjetaPeriodo)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 1000000);
      final pago = await pagar(deudaId: tarjeta.id, importe: 500000, cuentaId: bbva.id);

      final cargosAntes = await deudaRepo.totalCargadoEnRango();
      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'Corrección');
      await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelación');

      expect(
        await deudaRepo.totalCargadoEnRango(),
        cargosAntes,
        reason: 'corregir/cancelar un PAGO no es gasto — solo los ajustes de CARGO cuentan ahí',
      );
    });
  });

  group('Punto 11 — ciclo de la tarjeta', () {
    test('corregir el monto NUNCA mueve tarjetaVencimientoCubiertoHasta (el monto no participa)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 1000000, diaCorte: 17, diasDespuesCorte: 20);
      final pago = await pagar(deudaId: tarjeta.id, importe: 500000, cuentaId: bbva.id);

      final anclaTrasPago = (await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta;
      expect(anclaTrasPago, isNotNull, reason: 'un pago avanza el ciclo');

      await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 100, motivo: 'Bajísimo');

      expect((await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta, anclaTrasPago);
    });

    test('cancelar el único pago retrocede el ciclo exactamente al ancla previa (caso inequívoco)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 1000000, diaCorte: 17, diasDespuesCorte: 20);
      final anclaInicial = (await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta;

      final pago = await pagar(deudaId: tarjeta.id, importe: 500000, cuentaId: bbva.id);
      expect((await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta, isNotNull);

      final r = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelado');

      expect((r as CancelarPagoDeudaExitoso).resultado.cicloTarjetaRetrocedido, isTrue);
      expect(r.cicloTarjetaRequiereConciliacion, isFalse);
      expect((await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta, anclaInicial);
    });

    test('con un pago POSTERIOR vivo no retrocede el ciclo y lo reporta para conciliar', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 5000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 2000000, diaCorte: 17, diasDespuesCorte: 20);

      final primero = await pagar(deudaId: tarjeta.id, importe: 300000, cuentaId: bbva.id, fecha: DateTime(2026, 3, 5));
      await pagar(deudaId: tarjeta.id, importe: 300000, cuentaId: bbva.id, fecha: DateTime(2026, 4, 5));
      final anclaConDosPagos = (await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta;

      final r = await cancelarPago.ejecutar(pagoId: primero.id, motivo: 'Cancelo el primero');

      expect((r as CancelarPagoDeudaExitoso).resultado.cicloTarjetaRetrocedido, isFalse);
      expect(r.cicloTarjetaRequiereConciliacion, isTrue, reason: 'nunca retrocede ignorando pagos posteriores');
      expect((await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta, anclaConDosPagos, reason: 'intacto');
      // El efecto financiero sí se revierte por completo.
      expect((await recargar(tarjeta.id)).saldoActual, 2000000 - 300000);
    });

    test('si el ciclo fue conciliado a mano después del pago, no se pisa esa decisión', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 1000000, diaCorte: 17, diasDespuesCorte: 20);
      final pago = await pagar(deudaId: tarjeta.id, importe: 500000, cuentaId: bbva.id);

      // Conciliación manual posterior (lo que permite "Corregir deuda").
      final conciliadoAMano = DateTime(2027, 1, 6);
      await deudaRepo.corregir(deudaId: tarjeta.id, tarjetaVencimientoCubiertoHasta: conciliadoAMano);

      final r = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelado');

      expect((r as CancelarPagoDeudaExitoso).resultado.cicloTarjetaRetrocedido, isFalse);
      expect(r.cicloTarjetaRequiereConciliacion, isTrue);
      expect((await recargar(tarjeta.id)).tarjetaVencimientoCubiertoHasta, conciliadoAMano);
    });

    test('un pago de deuda fija nunca reporta conciliación de ciclo (no hay ciclo)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      final r = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Cancelado');
      expect((r as CancelarPagoDeudaExitoso).resultado.cicloTarjetaRequiereConciliacion, isFalse);
    });
  });

  group('Punto 19 — atomicidad', () {
    test('un fallo real a mitad de la corrección deja Deuda, movimientos, Egreso y cuenta iguales', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(saldo: 1500000);
      final pago = await pagar(deudaId: deuda.id, importe: 500000, cuentaId: bbva.id);

      final saldoDeudaAntes = (await recargar(deuda.id)).saldoActual;
      final saldoCuentaAntes = await cuentaRepo.calcularSaldo(bbva.id);
      final movimientosAntes = (await deudaRepo.listarMovimientos(deuda.id)).length;
      final eventosAntes = (await egresoRepo.listarEventos(pago.egresoId!)).length;

      await expectLater(
        () => db.transaction(() async {
          await corregirPago.ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'Se va a revertir');
          throw StateError('Fallo real provocado a mitad de la transacción');
        }),
        throwsA(isA<StateError>()),
      );

      expect((await recargar(deuda.id)).saldoActual, saldoDeudaAntes);
      expect((await recargar(deuda.id)).estatus, EstatusDeuda.activa.name);
      expect(await cuentaRepo.calcularSaldo(bbva.id), saldoCuentaAntes);
      expect((await deudaRepo.listarMovimientos(deuda.id)).length, movimientosAntes);
      expect((await egresoRepo.obtenerPorId(pago.egresoId!))!.monto, 500000);
      expect((await egresoRepo.listarEventos(pago.egresoId!)).length, eventosAntes);
    });

    test('un fallo real a mitad de la cancelación deja todo igual, incluido el ciclo de la tarjeta', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final tarjeta = await crearTarjeta(limite: 4000000, saldoInicial: 1000000, diaCorte: 17, diasDespuesCorte: 20);
      final pago = await pagar(deudaId: tarjeta.id, importe: 500000, cuentaId: bbva.id);

      final antes = await recargar(tarjeta.id);
      final movimientosAntes = (await deudaRepo.listarMovimientos(tarjeta.id)).length;

      await expectLater(
        () => db.transaction(() async {
          await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Se va a revertir');
          throw StateError('Fallo real provocado a mitad de la transacción');
        }),
        throwsA(isA<StateError>()),
      );

      final despues = await recargar(tarjeta.id);
      expect(despues.saldoActual, antes.saldoActual);
      expect(despues.estatus, antes.estatus);
      expect(despues.tarjetaVencimientoCubiertoHasta, antes.tarjetaVencimientoCubiertoHasta);
      expect((await deudaRepo.listarMovimientos(tarjeta.id)).length, movimientosAntes);
      expect((await egresoRepo.obtenerPorId(pago.egresoId!))!.estatus, 'registrado');
      expect((await deudaRepo.obtenerEstadoPago(pago.id)).cancelado, isFalse);
    });
  });

  group('Política de saldo (v91) — pago de deuda', () {
    test('A) con saldo suficiente: el pago se registra y la deuda baja', () async {
      final cuenta = await cuentaRepo.crear(
        codigo: 'CTA-PAGO-OK',
        nombre: 'Cuenta con fondos',
        tipo: 'banco',
        saldoInicial: 1500000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
      final deuda = await crearPrestamo(saldo: 3000000);
      final resultado = await registrarPago.ejecutar(
        deudaId: deuda.id,
        fecha: DateTime(2026, 2, 1),
        importe: 1500000,
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta.id,
      );
      expect(resultado, isA<RegistrarPagoDeudaExitoso>());
      expect(await cuentaRepo.calcularSaldo(cuenta.id), 0);
    });

    test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
      final cuenta = await cuentaRepo.crear(
        codigo: 'CTA-PAGO-CORTA',
        nombre: 'Cuenta corta',
        tipo: 'banco',
        saldoInicial: 100000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
      final deuda = await crearPrestamo(saldo: 3000000);
      final movimientosAntes = (await db.select(db.movimientoDeuda).get()).length;

      await expectLater(
        registrarPago.ejecutar(
          deudaId: deuda.id,
          fecha: DateTime(2026, 2, 1),
          importe: 1500000,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuenta.id,
        ),
        throwsA(isA<SaldoInsuficienteException>()),
      );

      expect(
        (await db.select(db.movimientoDeuda).get()).length,
        movimientosAntes,
        reason: 'ni el MovimientoDeuda del pago',
      );
      expect(
        (await db.select(db.egreso).get()).where((e) => e.monto == 1500000),
        isEmpty,
        reason: 'ni el Egreso',
      );
      expect(
        (await db.select(db.egresoFuente).get()).where((f) => f.cuentaFinancieraId == cuenta.id),
        isEmpty,
        reason: 'ni su fuente',
      );
      expect(await cuentaRepo.calcularSaldo(cuenta.id), 100000);
      expect((await deudaRepo.obtenerPorId(deuda.id))!.saldoActual, deuda.saldoActual);
    });
  });
}
