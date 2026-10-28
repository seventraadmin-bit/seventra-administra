// La migración a v91 NO puede cambiar ningún saldo.
//
// Es la condición que Marlon puso por escrito: el relleno de
// `EgresoFuente` es estructural —la misma salida de dinero, escrita
// donde a partir de ahora se lee— y no una operación financiera. Si
// después de migrar un saldo cambiara aunque fuera un centavo, el
// relleno habría inventado o borrado dinero.

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';

import '../../generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('32, 33 y 34: cada Egreso con cuenta produce UNA fuente y los saldos no cambian', () async {
    // Se parte de una base REAL en v90, con historia sembrada en SQL
    // crudo (mismo patrón que `migration_test.dart`): así lo que se
    // mide es la migración de verdad, no una simulación.
    final schema = await verifier.schemaAt(90);

    const corteA = 1772323200; // 2026-03-01
    const corteB = 1767225600; // 2026-01-01

    schema.rawDatabase.execute(
      'INSERT INTO cuenta_financiera (id, created_at, updated_at, ciclo_vida_registro, codigo, nombre, tipo, saldo_inicial, fecha_saldo_inicial) '
      "VALUES ('cta-a', $corteA, $corteA, 'activo', 'CTA-0001', 'Cuenta A', 'banco', 5000000, $corteA), "
      "       ('cta-b', $corteB, $corteB, 'activo', 'CTA-0002', 'Cuenta B', 'banco', 1000000, $corteB)",
    );

    void ingreso(String folio, int monto, int fecha, String cuenta) {
      schema.rawDatabase.execute(
        'INSERT INTO ingreso (id, created_at, updated_at, ciclo_vida_registro, folio_ingreso, monto, fecha, forma_pago, concepto, cuenta_financiera_id, estatus) '
        "VALUES ('$folio', $fecha, $fecha, 'activo', '$folio', $monto, $fecha, 'transferencia', 'Cobro', '$cuenta', 'registrado')",
      );
    }

    void egreso(String folio, int monto, int fecha, String? cuenta, {String estatus = 'registrado'}) {
      final valorCuenta = cuenta == null ? 'NULL' : "'$cuenta'";
      schema.rawDatabase.execute(
        'INSERT INTO egreso (id, created_at, updated_at, ciclo_vida_registro, folio_egreso, monto, fecha, forma_pago, concepto, cuenta_financiera_id, estatus) '
        "VALUES ('$folio', $fecha, $fecha, 'activo', '$folio', $monto, $fecha, 'transferencia', 'Gasto', $valorCuenta, '$estatus')",
      );
    }

    ingreso('ING-000001', 2000000, 1774915200, 'cta-a'); // 2026-04-01
    egreso('EGR-000001', 300000, 1775260800, 'cta-a'); // 2026-04-05
    egreso('EGR-000002', 700000, 1777939200, 'cta-a'); // 2026-05-05
    // Cancelado: no afecta saldo, ni antes ni después.
    egreso('EGR-000003', 900000, 1778025600, 'cta-a', estatus: 'cancelado');
    // Anterior al corte de su cuenta: la fórmula lo descarta, antes y después.
    egreso('EGR-000004', 400000, 1770076800, 'cta-a'); // 2026-02-03
    egreso('EGR-000005', 250000, 1770163200, 'cta-b'); // 2026-02-04
    // Sin cuenta: no toca caja y tampoco debe recibir fuente.
    egreso('EGR-000006', 111111, 1778112000, null);

    // Saldos ANTES, con la fórmula vieja aplicada a mano:
    // saldoInicial + ingresos − egresos vigentes posteriores al corte.
    const saldoEsperadoA = 5000000 + 2000000 - 300000 - 700000;
    // B sí cuenta su egreso: es de febrero y su corte es de enero.
    // El caso 'anterior al corte' lo cubre A con EGR-000004.
    const saldoEsperadoB = 1000000 - 250000;

    // --- La migración real ---------------------------------------
    // Recién aquí se abre la base como AppDatabase: su primer acceso
    // dispara `onUpgrade`, que es justo lo que se quiere medir, ya con
    // la historia sembrada.
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 91);

    final cuentas = CuentaFinancieraRepositoryImpl(db);
    final saldos = await cuentas.calcularSaldos(['cta-a', 'cta-b']);
    expect(saldos['cta-a'], saldoEsperadoA, reason: 'el saldo de A no cambió con la migración');
    expect(saldos['cta-b'], saldoEsperadoB, reason: 'el saldo de B no cambió con la migración');

    // Cada Egreso con cuenta —vigente o cancelado— tiene exactamente
    // una fuente, por su importe completo y en su misma cuenta.
    final conCuenta = (await db.select(db.egreso).get()).where((e) => e.cuentaFinancieraId != null).toList();
    expect(conCuenta, hasLength(5));
    for (final e in conCuenta) {
      final fuentes = await (db.select(db.egresoFuente)..where((t) => t.egresoId.equals(e.id))).get();
      expect(fuentes, hasLength(1), reason: '${e.folioEgreso} debe tener exactamente una fuente');
      expect(fuentes.single.importe, e.monto);
      expect(fuentes.single.cuentaFinancieraId, e.cuentaFinancieraId);
    }

    // El Egreso sin cuenta no recibió ninguna.
    final sinCuenta = (await db.select(db.egreso).get()).firstWhere((e) => e.folioEgreso == 'EGR-000006');
    expect(await (db.select(db.egresoFuente)..where((t) => t.egresoId.equals(sinCuenta.id))).get(), isEmpty);

    // Y no se inventó ni se borró ningún movimiento.
    expect(await db.select(db.ingreso).get(), hasLength(1));
    expect(await db.select(db.egreso).get(), hasLength(6));
    expect(await db.select(db.transferenciaCuenta).get(), isEmpty);

    await db.close();
  });
}
