// Etapa "Vehículos: ciclo de vida, gastos y origen financiero"
// (schemaVersion 80).
//
// GAP P0 QUE CIERRA: `VehiculoMantenimiento.costo` existía y se
// totalizaba en `calcularCostosVehiculo`, pero esa función se usaba en
// UN solo lugar — la pantalla del propio vehículo. El dinero nunca
// llegaba a Finanzas, ni a Reportes, ni al Dashboard.
//
// Ahora todo gasto monetario de Vehículos pregunta de dónde salió el
// dinero, reutilizando `OrigenFinancieroGasto` — la MISMA abstracción de
// Compras y Tiempos Extra, nunca un concepto paralelo.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart'
    show creditoDisponibleTarjeta;
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cancelar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';

void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late VehiculoMantenimientoRepositoryImpl mantenimientoRepo;
  late DeudaRepositoryImpl deudaRepo;
  late CuentaFinancieraRepositoryImpl cuentaRepo;
  late RegistrarMantenimientoVehiculoUseCase registrar;
  late CorregirMantenimientoVehiculoUseCase corregir;
  late CancelarMantenimientoVehiculoUseCase cancelar;

  late String vehiculoId;
  late String bbvaId;
  late String klarId;
  late String konfioId;

  // Cifras exactas del caso integral del pedido.
  const saldoInicialBbva = 2000000; // $20,000.00
  const saldoInicialKlar = 1000000; // $10,000.00
  const limiteKonfio = 1500000; // $15,000.00 de crédito disponible

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaFinancieraRepositoryImpl(db);
    vehiculoRepo = VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db));
    mantenimientoRepo = VehiculoMantenimientoRepositoryImpl(db);

    registrar = RegistrarMantenimientoVehiculoUseCase(
      mantenimientoRepo,
      vehiculoRepo,
      VehiculoKilometrajeRepositoryImpl(db),
      deudaRepo,
    );
    corregir = CorregirMantenimientoVehiculoUseCase(mantenimientoRepo, vehiculoRepo, deudaRepo);
    cancelar = CancelarMantenimientoVehiculoUseCase(mantenimientoRepo, vehiculoRepo);

    final bbva = await cuentaRepo.crear(
      codigo: 'CTA-BBVA',
      nombre: 'BBVA Empresarial',
      tipo: 'banco',
      saldoInicial: saldoInicialBbva,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
    bbvaId = bbva.id;
    final klar = await cuentaRepo.crear(
      codigo: 'CTA-KLAR',
      nombre: 'Klar Empresarial',
      tipo: 'banco',
      saldoInicial: saldoInicialKlar,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
    klarId = klar.id;

    final konfio = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-KONFIO',
            nombre: 'TDC Konfío Empresarial',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 0,
            tarjetaLimiteCredito: const Value(limiteKonfio),
          ),
        );
    konfioId = konfio.id;

    final vehiculo = await vehiculoRepo.crear(
      codigo: 'VEH-000001',
      marca: 'Nissan',
      modelo: 'NP300',
      tipoVehiculo: 'pickup',
    );
    vehiculoId = vehiculo.id;
  });

  tearDown(() => db.close());

  Future<int> saldo(String cuentaId) => cuentaRepo.calcularSaldo(cuentaId);

  Future<int> disponibleKonfio() async {
    final tarjeta = await deudaRepo.obtenerPorId(konfioId);
    return creditoDisponibleTarjeta(
      limiteCredito: tarjeta!.tarjetaLimiteCredito,
      saldoActual: tarjeta.saldoActual,
    )!;
  }

  /// Gasto operativo NETO reconocido por este mantenimiento — la suma de
  /// su Egreso vigente (si salió de una cuenta) más lo neto cargado a la
  /// tarjeta (si se financió con TDC). Es exactamente lo que el
  /// Resultado operativo debe reflejar, sin doble conteo.
  Future<int> gastoOperativoDelMantenimiento(String mantenimientoId) async {
    final registro = await mantenimientoRepo.obtenerPorId(mantenimientoId);
    if (registro == null) return 0;
    var total = 0;
    if (registro.egresoId != null) {
      final egreso = await (db.select(db.egreso)..where((t) => t.id.equals(registro.egresoId!))).getSingle();
      if (EstatusEgreso.values.byName(egreso.estatus) != EstatusEgreso.cancelado) total += egreso.monto;
    }
    if (registro.deudaId != null) {
      total += await deudaRepo.netoAportadoPorMantenimientoVehiculo(
        deudaId: registro.deudaId!,
        vehiculoMantenimientoId: mantenimientoId,
      );
    }
    return total;
  }

  Future<VehiculoMantenimientoData> registrarConCuenta(int costo, String cuentaId) async {
    final r = await registrar.ejecutar(
      vehiculoId: vehiculoId,
      fecha: DateTime(2026, 5, 10),
      tipo: TipoMantenimientoVehiculo.servicioGeneral.name,
      descripcion: 'Afinación',
      costo: costo,
      origen: OrigenFinancieroCuenta(cuentaId),
      actorUsuarioId: null,
    );
    return (r as RegistrarMantenimientoVehiculoExitoso).registro;
  }

  group('Comportamiento base: Cuenta vs. TDC', () {
    test('gasto con CUENTA genera Egreso y baja el saldo — nunca un cargo de TDC', () async {
      expect(await saldo(bbvaId), saldoInicialBbva);

      final registro = await registrarConCuenta(250000, bbvaId);

      expect(registro.egresoId, isNotNull);
      expect(registro.deudaId, isNull, reason: 'un gasto de cuenta jamás toca una tarjeta');
      expect(await saldo(bbvaId), saldoInicialBbva - 250000);
      expect(await deudaRepo.obtenerPorId(konfioId).then((d) => d!.saldoActual), 0);
    });

    test('gasto con TDC genera MovimientoDeuda y NO genera Egreso', () async {
      final r = await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.llantas.name,
        descripcion: 'Llantas',
        costo: 800000,
        origen: OrigenFinancieroTarjeta(konfioId),
      );
      final registro = (r as RegistrarMantenimientoVehiculoExitoso).registro;

      expect(registro.deudaId, konfioId);
      expect(registro.egresoId, isNull, reason: 'NUNCA Egreso + MovimientoDeuda simultáneos');
      expect(await db.select(db.egreso).get(), isEmpty);

      // El crédito disponible baja; Caja y bancos NO se mueven todavía.
      expect(await disponibleKonfio(), limiteKonfio - 800000);
      expect(await saldo(bbvaId), saldoInicialBbva);
      expect(await saldo(klarId), saldoInicialKlar);
    });

    test('costo sin origen se rechaza; sin costo no se exige nada', () async {
      final sinOrigen = await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.preventivo.name,
        descripcion: 'Servicio',
        costo: 100000,
      );
      expect(sinOrigen, isA<RegistrarMantenimientoVehiculoOrigenFinancieroRequerido>());

      // Un registro puramente documental sigue siendo válido.
      final documental = await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.preventivo.name,
        descripcion: 'Revisión visual',
      );
      expect(documental, isA<RegistrarMantenimientoVehiculoExitoso>());
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('una TDC sin crédito suficiente se rechaza antes de escribir nada', () async {
      final r = await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.correctivo.name,
        descripcion: 'Motor',
        costo: limiteKonfio + 1,
        origen: OrigenFinancieroTarjeta(konfioId),
      );
      expect(r, isA<RegistrarMantenimientoVehiculoTarjetaInvalida>());
      expect(await db.select(db.vehiculoMantenimiento).get(), isEmpty);
      expect(await disponibleKonfio(), limiteKonfio);
    });
  });

  group('CASO NUMÉRICO INTEGRAL (§11 del pedido)', () {
    test('BBVA 20,000 · Klar 10,000 · Konfío 15,000 — registrar, corregir ×2 y anular', () async {
      // --- Punto de partida ---
      expect(await saldo(bbvaId), 2000000);
      expect(await saldo(klarId), 1000000);
      expect(await disponibleKonfio(), 1500000);

      // --- 1. Mantenimiento $2,500 → BBVA ---
      final registro = await registrarConCuenta(250000, bbvaId);

      expect(await saldo(bbvaId), 1750000, reason: 'BBVA = 17,500');
      expect(await saldo(klarId), 1000000, reason: 'Klar intacta');
      expect(await disponibleKonfio(), 1500000, reason: 'Konfío intacta');
      expect(await gastoOperativoDelMantenimiento(registro.id), 250000, reason: 'gasto operativo +2,500');

      // --- 2. Corregir: $2,500 BBVA → $3,200 Konfío ---
      final correccion1 = await corregir.ejecutar(
        vehiculoMantenimientoId: registro.id,
        descripcion: 'Reparación',
        costo: 320000,
        origen: OrigenFinancieroTarjeta(konfioId),
        motivo: 'El taller cobró más y se pagó con la tarjeta',
      );
      expect(correccion1, isA<CorregirMantenimientoVehiculoExitoso>());

      expect(await saldo(bbvaId), 2000000, reason: 'BBVA recupera EXACTAMENTE los 2,500');
      expect(await saldo(klarId), 1000000);
      expect(await disponibleKonfio(), 1180000, reason: 'Konfio disponible = 11,800');
      expect(
        await gastoOperativoDelMantenimiento(registro.id),
        320000,
        reason: 'gasto acumulado = \$3,200, NUNCA \$5,700 (sin doble gasto)',
      );

      // --- 3. Corregir otra vez: $3,200 Konfío → $2,800 Klar ---
      final correccion2 = await corregir.ejecutar(
        vehiculoMantenimientoId: registro.id,
        costo: 280000,
        origen: OrigenFinancieroCuenta(klarId),
        motivo: 'Se pagó realmente desde Klar',
      );
      expect(correccion2, isA<CorregirMantenimientoVehiculoExitoso>());

      expect(await saldo(bbvaId), 2000000);
      expect(await saldo(klarId), 720000, reason: 'Klar = 7,200');
      expect(await disponibleKonfio(), 1500000, reason: 'Konfío recupera todo su crédito');
      expect(await gastoOperativoDelMantenimiento(registro.id), 280000, reason: 'gasto = 2,800');

      // --- 4. Anular ---
      final anulado = await cancelar.ejecutar(
        vehiculoMantenimientoId: registro.id,
        motivo: 'El servicio nunca se realizó',
      );
      expect(anulado, isA<CancelarMantenimientoVehiculoExitoso>());

      expect(await saldo(bbvaId), 2000000, reason: 'BBVA vuelve a 20,000');
      expect(await saldo(klarId), 1000000, reason: 'Klar vuelve a 10,000');
      expect(await disponibleKonfio(), 1500000, reason: 'Konfio vuelve a 15,000');
      expect(await gastoOperativoDelMantenimiento(registro.id), 0, reason: 'efecto operativo neto = 0');

      // Ningún Egreso vigente ni cargo de TDC vivo derivado del
      // mantenimiento anulado.
      final egresos = await db.select(db.egreso).get();
      expect(
        egresos.where((e) => EstatusEgreso.values.byName(e.estatus) != EstatusEgreso.cancelado),
        isEmpty,
        reason: 'no queda ningún Egreso registrado del mantenimiento anulado',
      );
      expect(
        await deudaRepo.netoAportadoPorMantenimientoVehiculo(
          deudaId: konfioId,
          vehiculoMantenimientoId: registro.id,
        ),
        0,
        reason: 'no queda ningún cargo TDC vigente',
      );

      // El registro NO se borró: conserva su evidencia.
      final final_ = await mantenimientoRepo.obtenerPorId(registro.id);
      expect(final_, isNotNull);
      expect(final_!.estatus, EstatusMantenimientoVehiculo.cancelado.name);
      expect(final_.motivoCancelacion, 'El servicio nunca se realizó');
    });
  });

  group('§7 — las 8 transiciones de origen', () {
    test('cuenta → MISMA cuenta con cambio de monto', () async {
      final r = await registrarConCuenta(250000, bbvaId);
      await corregir.ejecutar(
        vehiculoMantenimientoId: r.id,
        costo: 300000,
        origen: OrigenFinancieroCuenta(bbvaId),
        motivo: 'Ajuste de monto',
      );
      expect(await saldo(bbvaId), saldoInicialBbva - 300000);
      expect(await gastoOperativoDelMantenimiento(r.id), 300000);
    });

    test('cuenta → OTRA cuenta', () async {
      final r = await registrarConCuenta(250000, bbvaId);
      await corregir.ejecutar(
        vehiculoMantenimientoId: r.id,
        origen: OrigenFinancieroCuenta(klarId),
        motivo: 'Cuenta equivocada',
      );
      expect(await saldo(bbvaId), saldoInicialBbva);
      expect(await saldo(klarId), saldoInicialKlar - 250000);
    });

    test('TDC → MISMA TDC con cambio de monto (ajuste, no recarga)', () async {
      final r = (await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.llantas.name,
        descripcion: 'Llantas',
        costo: 500000,
        origen: OrigenFinancieroTarjeta(konfioId),
      ) as RegistrarMantenimientoVehiculoExitoso)
          .registro;

      await corregir.ejecutar(
        vehiculoMantenimientoId: r.id,
        costo: 700000,
        origen: OrigenFinancieroTarjeta(konfioId),
        motivo: 'Se agregó alineación',
      );

      expect(await disponibleKonfio(), limiteKonfio - 700000);
      expect(await gastoOperativoDelMantenimiento(r.id), 700000, reason: 'neto, nunca 500,000 + 700,000');
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'sigue sin tocar el banco');
    });

    test('TDC → cuenta', () async {
      final r = (await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.frenos.name,
        descripcion: 'Frenos',
        costo: 400000,
        origen: OrigenFinancieroTarjeta(konfioId),
      ) as RegistrarMantenimientoVehiculoExitoso)
          .registro;

      await corregir.ejecutar(
        vehiculoMantenimientoId: r.id,
        origen: OrigenFinancieroCuenta(bbvaId),
        motivo: 'En realidad se pagó por transferencia',
      );

      expect(await disponibleKonfio(), limiteKonfio, reason: 'la tarjeta recupera todo');
      expect(await saldo(bbvaId), saldoInicialBbva - 400000);
      final actualizado = await mantenimientoRepo.obtenerPorId(r.id);
      expect(actualizado!.deudaId, isNull);
      expect(actualizado.egresoId, isNotNull);
    });
  });

  group('§8 — la segunda anulación nunca revierte dos veces', () {
    test('cancelar dos veces deja los saldos idénticos', () async {
      final r = await registrarConCuenta(250000, bbvaId);
      await cancelar.ejecutar(vehiculoMantenimientoId: r.id, motivo: 'Error');
      final saldoTrasPrimera = await saldo(bbvaId);

      final segunda = await cancelar.ejecutar(vehiculoMantenimientoId: r.id, motivo: 'Error otra vez');
      expect(segunda, isA<CancelarMantenimientoVehiculoYaCancelado>());
      expect(await saldo(bbvaId), saldoTrasPrimera);
    });

    test('lo mismo con TDC — el neto ya es 0, no se emite otro ajuste', () async {
      final r = (await registrar.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 10),
        tipo: TipoMantenimientoVehiculo.bateria.name,
        descripcion: 'Batería',
        costo: 200000,
        origen: OrigenFinancieroTarjeta(konfioId),
      ) as RegistrarMantenimientoVehiculoExitoso)
          .registro;

      await cancelar.ejecutar(vehiculoMantenimientoId: r.id, motivo: 'Error');
      final movimientosTrasPrimera = (await deudaRepo.listarMovimientos(konfioId)).length;

      await cancelar.ejecutar(vehiculoMantenimientoId: r.id, motivo: 'Otra vez');
      expect((await deudaRepo.listarMovimientos(konfioId)).length, movimientosTrasPrimera);
      expect(await disponibleKonfio(), limiteKonfio);
    });
  });

  group('Legacy: el gasto histórico sin origen sigue siendo válido', () {
    test('una fila con costo y sin origen se lee sin romper nada', () async {
      // Exactamente la forma del mantenimiento real de $3,800 que existe
      // en producción: costo, sin `egresoId` ni `deudaId`. Marlon
      // decidió NO hacerle backfill.
      final legacy = await mantenimientoRepo.crear(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 4, 1),
        tipo: TipoMantenimientoVehiculo.llantas.name,
        descripcion: 'Llantas (histórico)',
        costo: 380000,
      );

      expect(legacy.costo, 380000);
      expect(legacy.egresoId, isNull);
      expect(legacy.deudaId, isNull);
      expect(legacy.estatus, EstatusMantenimientoVehiculo.registrado.name);
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'sin backfill: no se inventa un Egreso');
      expect(await saldo(bbvaId), saldoInicialBbva);
    });
  });
}
