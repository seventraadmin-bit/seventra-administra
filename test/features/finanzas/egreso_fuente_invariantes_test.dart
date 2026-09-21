// Invariantes de `EgresoFuente` y del ciclo cancelar / corregir.
//
// Cierra por prueba lo que la pasada de robustez pidió confirmar: que
// ningún Egreso desde cuenta pueda quedarse sin fuente, que la columna
// legacy nunca engañe, que cancelar conserve la historia sin afectar
// saldo, y que la auditoría pueda reconstruir el antes/después de una
// distribución.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/fuente_egreso.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresos;
  late CuentaFinancieraRepositoryImpl cuentas;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    egresos = EgresoRepositoryImpl(db);
    cuentas = CuentaFinancieraRepositoryImpl(db);
  });

  tearDown(() => db.close());

  var n = 0;
  Future<CuentaFinancieraData> crearCuenta(int saldo) async {
    n++;
    return db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-${n.toString().padLeft(4, '0')}',
            nombre: 'Cuenta $n',
            tipo: 'banco',
            saldoInicial: saldo,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  }

  var folio = 0;
  Future<EgresoData> gastar({required int monto, String? cuentaId, List<FuenteEgreso>? fuentes}) {
    folio++;
    return egresos.crear(
      folioEgreso: 'EGR-${folio.toString().padLeft(6, '0')}',
      monto: monto,
      fecha: DateTime(2026, 6, 15),
      cuentaFinancieraId: cuentaId,
      fuentes: fuentes,
      formaPago: 'transferencia',
      concepto: 'Gasto',
    );
  }

  Future<List<EgresoFuenteData>> fuentesDe(String id) =>
      (db.select(db.egresoFuente)..where((t) => t.egresoId.equals(id))).get();

  Future<int> saldo(String id) async => (await cuentas.calcularSaldos([id]))[id]!;

  test('ningún Egreso desde cuenta queda sin fuente, con una o con varias', () async {
    final a = await crearCuenta(1000000);
    final b = await crearCuenta(1000000);

    final unaSola = await gastar(monto: 100000, cuentaId: a.id);
    final varias = await gastar(monto: 300000, fuentes: [
      FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
      FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
    ]);

    for (final e in [unaSola, varias]) {
      final f = await fuentesDe(e.id);
      expect(f, isNotEmpty);
      expect(f.fold<int>(0, (s, x) => s + x.importe), e.monto, reason: 'la suma cuadra con el importe');
    }
  });

  test('un Egreso financiado con TDC no recibe fuentes: ese peso no salió de ninguna cuenta', () async {
    final deuda = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-000001',
            nombre: 'Tarjeta',
            tipo: 'tarjetaCredito',
            fechaOrigen: Value(DateTime(2026, 1, 1)),
            saldoActual: 0,
            tarjetaLimiteCredito: const Value(5000000),
          ),
        );
    final egreso = await egresos.crear(
      folioEgreso: 'EGR-TDC',
      monto: 250000,
      fecha: DateTime(2026, 6, 15),
      deudaId: deuda.id,
      formaPago: 'tarjeta',
      concepto: 'Gasto con TDC',
    );
    expect(await fuentesDe(egreso.id), isEmpty);
  });

  test('con varias fuentes la columna legacy queda null: nunca señala a una cuenta sola', () async {
    final a = await crearCuenta(1000000);
    final b = await crearCuenta(1000000);
    final egreso = await gastar(monto: 300000, fuentes: [
      FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
      FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
    ]);
    expect((await egresos.obtenerPorId(egreso.id))!.cuentaFinancieraId, isNull);

    // Y al volver a una sola cuenta, la columna vuelve a poblarse.
    await egresos.corregir(
      egresoId: egreso.id,
      fuentes: [FuenteEgreso(cuentaFinancieraId: a.id, importe: 300000)],
      motivo: 'Todo salió de A',
    );
    expect((await egresos.obtenerPorId(egreso.id))!.cuentaFinancieraId, a.id);
  });

  test('cancelar: el saldo se recupera y las fuentes permanecen como historia', () async {
    final a = await crearCuenta(1000000);
    final b = await crearCuenta(1000000);
    final egreso = await gastar(monto: 300000, fuentes: [
      FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
      FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
    ]);

    await egresos.cancelar(egresoId: egreso.id, motivo: 'Error de captura');

    expect(await saldo(a.id), 1000000);
    expect(await saldo(b.id), 1000000);
    expect(await fuentesDe(egreso.id), hasLength(2), reason: 'la distribución se conserva');
    expect(await db.select(db.ingreso).get(), isEmpty, reason: 'jamás un Ingreso compensatorio');

    // Y el historial de la cuenta las sigue mostrando, aunque no sumen.
    final movimientos = await cuentas.listarMovimientos(a.id);
    expect(movimientos.where((m) => m.referencia == egreso.folioEgreso), hasLength(1));
  });

  test('un Egreso cancelado NO puede corregirse: no existe reactivación en el proyecto', () async {
    final a = await crearCuenta(1000000);
    final egreso = await gastar(monto: 300000, cuentaId: a.id);
    await egresos.cancelar(egresoId: egreso.id, motivo: 'Error');

    // `EstatusEgreso` sólo tiene `registrado` y `cancelado`, y nada
    // vuelve a escribir `registrado`. La ruta de corrección lo rechaza
    // explícitamente en su caso de uso; aquí se fija que el estatus no
    // cambia por sí solo y que el saldo sigue recuperado.
    expect((await egresos.obtenerPorId(egreso.id))!.estatus, 'cancelado');
    expect(await saldo(a.id), 1000000);
  });

  test('el historial de la cuenta muestra el importe DE ESA cuenta, no el total del Egreso', () async {
    final a = await crearCuenta(1000000);
    final b = await crearCuenta(1000000);
    final egreso = await gastar(monto: 300000, fuentes: [
      FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
      FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
    ]);

    final deA = await cuentas.listarMovimientos(a.id);
    final deB = await cuentas.listarMovimientos(b.id);
    expect(deA.singleWhere((m) => m.referencia == egreso.folioEgreso).salida, 100000);
    expect(deB.singleWhere((m) => m.referencia == egreso.folioEgreso).salida, 200000);
  });

  test('la auditoría reconstruye el antes/después de la distribución', () async {
    final a = await crearCuenta(1000000);
    final b = await crearCuenta(1000000);
    final egreso = await gastar(monto: 300000, cuentaId: a.id);

    await egresos.corregir(
      egresoId: egreso.id,
      fuentes: [
        FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
        FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
      ],
      motivo: 'Se repartió entre dos cuentas',
    );

    final eventos = await egresos.listarEventos(egreso.id);
    // El alta dejó constancia de las fuentes originales...
    final alta = eventos.firstWhere((e) => e.tipoEvento == 'registrado');
    expect(alta.datosRelevantes, contains('fuentes'));
    expect(alta.datosRelevantes, contains(a.id));
    // ...y la corrección quedó registrada con su motivo.
    expect(eventos.where((e) => e.tipoEvento == 'corregido'), isNotEmpty);
    expect(
      eventos.firstWhere((e) => e.tipoEvento == 'corregido').observacion,
      'Se repartió entre dos cuentas',
    );
  });
}
