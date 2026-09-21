// REGRESIÓN del bug real del caso EGR-000035 (gasolina $1,359.98,
// Klar → TDC Konfío): la corrección fallaba en la app con "No se pudo
// corregir el Egreso" aunque toda la lógica de dominio era correcta.
//
// Causa: `egresoRepositoryProvider` leía `deudaRepositoryProvider`
// dentro de un callback diferido, y `deudaRepositoryProvider` ya hacía
// `ref.watch(egresoRepositoryProvider)`. Diferir la lectura NO evita
// que Riverpod registre la arista: al ejecutarse la corrección lanzaba
// `CircularDependencyError`, que el caso de uso traducía al mensaje
// genérico.
//
// Por qué NINGUNA prueba lo detectó: todas las de esta etapa (y las
// previas de Finanzas) arman los repositorios A MANO
// —`EgresoRepositoryImpl(db)`, `DeudaRepositoryImpl(db, egresoRepo)`—
// sin `ProviderContainer`, así que el grafo de Riverpod nunca
// participaba; y las pruebas de widget solo ABRÍAN los diálogos, sin
// confirmar una corrección. Ese era exactamente el hueco entre el
// fixture y la app real.
//
// Este archivo cierra ese hueco: ejerce las 6 transiciones POR LA VÍA
// DE LOS PROVIDERS DE PRODUCCIÓN, que es la única forma de volver a
// atrapar un ciclo de dependencias o un cableado roto de DI.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show TipoMovimientoDeuda;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
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

  Future<CuentaFinancieraData> crearCuenta(String nombre, String codigo, int saldoInicial) {
    return container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: codigo,
          nombre: nombre,
          tipo: 'banco',
          saldoInicial: saldoInicial,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );
  }

  Future<DeudaData> crearTarjeta(String nombre, {required int limite, int saldoInicial = 0}) async {
    final resultado = await container.read(registrarDeudaUseCaseProvider).ejecutar(
          nombre: nombre,
          tipo: 'tarjetaCredito',
          saldoInicial: saldoInicial,
          fechaSaldoInicial: saldoInicial > 0 ? DateTime(2026, 1, 1) : null,
          tarjetaLimiteCredito: limite,
        );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  Future<EgresoData> registrarGasto({required int monto, OrigenFinancieroGasto? origen}) async {
    final resultado = await container.read(registrarEgresoUseCaseProvider).ejecutar(
          monto: monto,
          fecha: DateTime(2026, 3, 5),
          formaPago: 'tarjeta',
          concepto: 'gasolina',
          origen: origen,
        );
    expect(resultado, isA<RegistrarEgresoExitoso>(), reason: 'el alta por la vía de los providers no debe fallar');
    return (resultado as RegistrarEgresoExitoso).egreso;
  }

  Future<CorregirEgresoResultado> corregir({
    required String egresoId,
    int? monto,
    OrigenFinancieroGasto? origen,
    bool limpiarOrigen = false,
  }) {
    return container.read(corregirEgresoUseCaseProvider).ejecutar(
          egresoId: egresoId,
          monto: monto,
          origen: origen,
          limpiarOrigen: limpiarOrigen,
          motivo: 'Corrección de origen financiero',
        );
  }

  Future<int> saldoCuenta(String id) => container.read(cuentaFinancieraRepositoryProvider).calcularSaldo(id);

  Future<DeudaData> recargarTarjeta(String id) async =>
      (await container.read(deudaRepositoryProvider).obtenerPorId(id))!;

  int? disponibleDe(DeudaData t) =>
      creditoDisponibleTarjeta(limiteCredito: t.tarjetaLimiteCredito, saldoActual: t.saldoActual);

  test(
    'el grafo de providers resuelve Egreso y Deuda sin ciclo — ambos sentidos, en cualquier orden de lectura',
    () {
      // Leer primero el de Egreso y luego el de Deuda (y al revés, en un
      // container nuevo) es justo lo que disparaba
      // `CircularDependencyError`.
      expect(() => container.read(egresoRepositoryProvider), returnsNormally);
      expect(() => container.read(deudaRepositoryProvider), returnsNormally);

      final otro = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(otro.dispose);
      expect(() => otro.read(deudaRepositoryProvider), returnsNormally);
      expect(() => otro.read(egresoRepositoryProvider), returnsNormally);
    },
  );

  test(
    'CASO REAL EGR-000035 — gasolina \$1,359.98 de Klar a TDC Konfío, por la vía de los providers',
    () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 699179 + 135998);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000, saldoInicial: 3326608);

      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroCuenta(klar.id));
      final saldoKlarConGastoMalCapturado = await saldoCuenta(klar.id);
      expect(saldoKlarConGastoMalCapturado, 699179, reason: 'estado equivocado de partida: Klar pagó algo que nunca pagó');

      final resultado = await corregir(egresoId: egreso.id, origen: OrigenFinancieroTarjeta(konfio.id));

      // Antes del arreglo esto era `CorregirEgresoErrorInesperado`
      // con el mensaje inútil "Instance of 'CircularDependencyError'".
      expect(
        resultado,
        isA<CorregirEgresoExitoso>(),
        reason: resultado is CorregirEgresoErrorInesperado ? 'falló con: ${resultado.mensaje}' : null,
      );

      final corregido = (resultado as CorregirEgresoExitoso).egreso;
      expect(corregido.id, egreso.id, reason: 'mismo Egreso.id');
      expect(corregido.folioEgreso, egreso.folioEgreso, reason: 'mismo folio');
      expect(corregido.cuentaFinancieraId, isNull);
      expect(corregido.deudaId, konfio.id);
      expect(corregido.monto, 135998, reason: 'el gasto operativo no cambia por cambiar el origen');
      expect(corregido.estatus, 'registrado', reason: 'no queda Egreso cancelado ni duplicado');

      expect(await saldoCuenta(klar.id), 699179 + 135998, reason: 'Klar recupera exactamente \$1,359.98');

      final tarjeta = await recargarTarjeta(konfio.id);
      expect(tarjeta.saldoActual, 3326608 + 135998, reason: 'Konfío incrementa su saldo utilizado exactamente \$1,359.98');
      expect(disponibleDe(tarjeta), 4000000 - (3326608 + 135998), reason: 'crédito disponible baja exactamente \$1,359.98');

      // Cero duplicados, y el cargo apunta de vuelta a ESTE Egreso.
      final egresos = await container.read(egresoRepositoryProvider).listar();
      expect(egresos, hasLength(1), reason: 'no queda Egreso duplicado');
      final cargos = (await container.read(deudaRepositoryProvider).listarMovimientos(konfio.id))
          .where((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name)
          .toList();
      expect(cargos, hasLength(1), reason: 'no queda cargo TDC duplicado');
      expect(cargos.single.egresoGastoId, egreso.id);
      expect(cargos.single.importe, 135998);

      // Auditoría: cuenta anterior y tarjeta nueva, ambas en el evento.
      final eventos = await container.read(egresoRepositoryProvider).listarEventos(egreso.id);
      final evento = eventos.lastWhere((e) => e.tipoEvento == 'corregido');
      expect(evento.estadoAnterior, contains('"cuentaFinancieraId":"${klar.id}"'));
      expect(evento.estadoNuevo, contains('"deudaId":"${konfio.id}"'));
    },
  );

  group('regresión de las 6 transiciones por la vía de los providers', () {
    test('Cuenta → misma Cuenta', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 1000000);
      final egreso = await registrarGasto(monto: 100000, origen: OrigenFinancieroCuenta(bbva.id));

      final r = await corregir(egresoId: egreso.id, monto: 150000, origen: OrigenFinancieroCuenta(bbva.id));

      expect(r, isA<CorregirEgresoExitoso>());
      expect(await saldoCuenta(bbva.id), 1000000 - 150000);
    });

    test('Cuenta → otra Cuenta', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 1000000);
      final klar = await crearCuenta('Klar', 'CTA-0002', 800000);
      final egreso = await registrarGasto(monto: 100000, origen: OrigenFinancieroCuenta(bbva.id));

      final r = await corregir(egresoId: egreso.id, origen: OrigenFinancieroCuenta(klar.id));

      expect(r, isA<CorregirEgresoExitoso>());
      expect(await saldoCuenta(bbva.id), 1000000);
      expect(await saldoCuenta(klar.id), 800000 - 100000);
    });

    test('Cuenta → TDC', () async {
      final klar = await crearCuenta('Klar', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('Konfío', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroCuenta(klar.id));

      final r = await corregir(egresoId: egreso.id, origen: OrigenFinancieroTarjeta(konfio.id));

      expect(r, isA<CorregirEgresoExitoso>());
      expect(await saldoCuenta(klar.id), 1000000);
      expect((await recargarTarjeta(konfio.id)).saldoActual, 135998);
    });

    test('TDC → misma TDC', () async {
      final konfio = await crearTarjeta('Konfío', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      final r = await corregir(egresoId: egreso.id, monto: 150000, origen: OrigenFinancieroTarjeta(konfio.id));

      expect(r, isA<CorregirEgresoExitoso>());
      expect((await recargarTarjeta(konfio.id)).saldoActual, 150000);
      final movimientos = await container.read(deudaRepositoryProvider).listarMovimientos(konfio.id);
      expect(
        movimientos.firstWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name).importe,
        135998,
        reason: 'el cargo original nunca se reescribe',
      );
    });

    test('TDC → otra TDC', () async {
      final konfio = await crearTarjeta('Konfío', limite: 4000000);
      final clara = await crearTarjeta('Clara', limite: 3000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      final r = await corregir(egresoId: egreso.id, monto: 150000, origen: OrigenFinancieroTarjeta(clara.id));

      expect(r, isA<CorregirEgresoExitoso>());
      expect((await recargarTarjeta(konfio.id)).saldoActual, 0);
      expect((await recargarTarjeta(clara.id)).saldoActual, 150000);
    });

    test('TDC → Cuenta', () async {
      final bbva = await crearCuenta('BBVA', 'CTA-0003', 1000000);
      final konfio = await crearTarjeta('Konfío', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      final r = await corregir(egresoId: egreso.id, origen: OrigenFinancieroCuenta(bbva.id));

      expect(r, isA<CorregirEgresoExitoso>());
      expect((await recargarTarjeta(konfio.id)).saldoActual, 0);
      expect(await saldoCuenta(bbva.id), 1000000 - 135998);
    });
  });

  test('alta y cancelación con TDC también funcionan por la vía de los providers', () async {
    final konfio = await crearTarjeta('Konfío', limite: 4000000);

    final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));
    expect((await recargarTarjeta(konfio.id)).saldoActual, 135998);

    final r = await container
        .read(cancelarEgresoUseCaseProvider)
        .ejecutar(egresoId: egreso.id, motivo: 'Gasto capturado por error');

    expect(
      r,
      isA<CancelarEgresoExitoso>(),
      reason: r is CancelarEgresoErrorInesperado ? 'falló con: ${r.mensaje}' : null,
    );
    expect((await recargarTarjeta(konfio.id)).saldoActual, 0);
    expect(disponibleDe(await recargarTarjeta(konfio.id)), 4000000);
  });
}
