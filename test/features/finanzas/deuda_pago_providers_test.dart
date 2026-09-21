// Etapa 9 — regresión POR LA VÍA DE LOS PROVIDERS de producción.
//
// Existe por la lección de la etapa anterior (caso EGR-000035): un
// cableado roto de DI —un ciclo en el grafo de Riverpod, un provider
// mal compuesto— es INVISIBLE para toda prueba que arme los
// repositorios a mano, y las de widget no lo detectan si solo abren
// diálogos sin confirmar. Cada vía nueva de escritura necesita al menos
// una prueba con `ProviderContainer` real.
//
// Cubre además el punto 16 del pedido en sus dos sentidos: el Egreso de
// un pago de Deuda sigue bloqueado desde Finanzas, y corregir/cancelar
// el pago desde la Deuda SÍ lo sincroniza.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<CuentaFinancieraData> crearCuenta(String nombre, String codigo, int saldo) {
    return container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: codigo,
          nombre: nombre,
          tipo: 'banco',
          saldoInicial: saldo,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );
  }

  Future<DeudaData> crearPrestamo(int saldo) async {
    final r = await container.read(registrarDeudaUseCaseProvider).ejecutar(
          nombre: 'SANDRA PRESTAMO PERSONAL',
          tipo: 'prestamo',
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: saldo,
          saldoInicial: saldo,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );
    return (r as RegistrarDeudaExitoso).deuda;
  }

  Future<MovimientoDeudaData> pagar(String deudaId, int importe, String cuentaId) async {
    final r = await container.read(registrarPagoDeudaUseCaseProvider).ejecutar(
          deudaId: deudaId,
          fecha: DateTime(2026, 3, 5),
          importe: importe,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuentaId,
        );
    expect(r, isA<RegistrarPagoDeudaExitoso>());
    final movimientos = await container.read(deudaRepositoryProvider).listarMovimientos(deudaId);
    return movimientos.lastWhere((m) => m.tipo == TipoMovimientoDeuda.pago.name);
  }

  test('los use cases de pago se resuelven desde el container sin ciclo de dependencias', () {
    expect(() => container.read(corregirPagoDeudaUseCaseProvider), returnsNormally);
    expect(() => container.read(cancelarPagoDeudaUseCaseProvider), returnsNormally);
    expect(() => container.read(deudaRepositoryProvider), returnsNormally);
    expect(() => container.read(egresoRepositoryProvider), returnsNormally);
  });

  test('corregir un pago por la vía real de la UI sincroniza Deuda, Egreso y Caja', () async {
    final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
    final deuda = await crearPrestamo(1500000);
    final pago = await pagar(deuda.id, 500000, bbva.id);

    final r = await container.read(corregirPagoDeudaUseCaseProvider).ejecutar(
          pagoId: pago.id,
          nuevoImporte: 450000,
          nuevaCuentaFinancieraId: bbva.id,
          motivo: 'Se capturó de más',
        );

    expect(
      r,
      isA<CorregirPagoDeudaExitoso>(),
      reason: r is CorregirPagoDeudaErrorInesperado ? 'falló con: ${r.mensaje}' : null,
    );
    expect((await container.read(deudaRepositoryProvider).obtenerPorId(deuda.id))!.saldoActual, 1050000);
    expect(await container.read(cuentaFinancieraRepositoryProvider).calcularSaldo(bbva.id), 1550000);
    expect((await container.read(egresoRepositoryProvider).obtenerPorId(pago.egresoId!))!.monto, 450000);
  });

  test('cancelar un pago por la vía real de la UI revierte todo', () async {
    final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
    final deuda = await crearPrestamo(1500000);
    final pago = await pagar(deuda.id, 500000, bbva.id);

    final r = await container
        .read(cancelarPagoDeudaUseCaseProvider)
        .ejecutar(pagoId: pago.id, motivo: 'Duplicado');

    expect(
      r,
      isA<CancelarPagoDeudaExitoso>(),
      reason: r is CancelarPagoDeudaErrorInesperado ? 'falló con: ${r.mensaje}' : null,
    );
    expect((await container.read(deudaRepositoryProvider).obtenerPorId(deuda.id))!.saldoActual, 1500000);
    expect(await container.read(cuentaFinancieraRepositoryProvider).calcularSaldo(bbva.id), 2000000);
    expect((await container.read(egresoRepositoryProvider).obtenerPorId(pago.egresoId!))!.estatus, 'cancelado');
  });

  group('Punto 16 — el bloqueo desde Finanzas sigue en pie, en ambos sentidos', () {
    test('corregir el Egreso de un pago de Deuda DESDE Finanzas se bloquea y señala su origen', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(1500000);
      final pago = await pagar(deuda.id, 500000, bbva.id);

      final r = await container.read(corregirEgresoUseCaseProvider).ejecutar(
            egresoId: pago.egresoId!,
            monto: 450000,
            motivo: 'Intento desde Finanzas',
          );

      expect(r, isA<CorregirEgresoOrigenAutomatico>());
      final origen = (r as CorregirEgresoOrigenAutomatico).origen;
      expect(origen, isA<OrigenAutomaticoEgresoDeuda>());
      expect((origen as OrigenAutomaticoEgresoDeuda).deudaId, deuda.id);
      expect((await container.read(egresoRepositoryProvider).obtenerPorId(pago.egresoId!))!.monto, 500000);
    });

    test('cancelar ese Egreso DESDE Finanzas también se bloquea', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(1500000);
      final pago = await pagar(deuda.id, 500000, bbva.id);

      final r = await container
          .read(cancelarEgresoUseCaseProvider)
          .ejecutar(egresoId: pago.egresoId!, motivo: 'Intento desde Finanzas');

      expect(r, isA<CancelarEgresoOrigenAutomatico>());
      expect((await container.read(egresoRepositoryProvider).obtenerPorId(pago.egresoId!))!.estatus, 'registrado');
      expect((await container.read(deudaRepositoryProvider).obtenerPorId(deuda.id))!.saldoActual, 1000000);
    });

    test('pero corregirlo DESDE la Deuda sí lo sincroniza (la vía correcta)', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 2000000);
      final deuda = await crearPrestamo(1500000);
      final pago = await pagar(deuda.id, 500000, bbva.id);

      await container
          .read(corregirPagoDeudaUseCaseProvider)
          .ejecutar(pagoId: pago.id, nuevoImporte: 450000, motivo: 'Desde el expediente de la Deuda');

      expect((await container.read(egresoRepositoryProvider).obtenerPorId(pago.egresoId!))!.monto, 450000);
    });
  });
}
