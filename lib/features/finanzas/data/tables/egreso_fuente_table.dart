import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'cuenta_financiera_table.dart';
import 'egreso_table.dart';

/// De qué cuenta(s) salió realmente el dinero de un `Egreso`
/// (schemaVersion 91) — **la fuente canónica** del efecto de un Egreso
/// sobre las cuentas financieras.
///
/// Todo Egreso financiado desde `CuentaFinanciera` tiene al menos una
/// fila aquí, incluso cuando la cuenta es una sola:
///
/// ```
/// Egreso $1,000  ──→ EgresoFuente(BBVA, $1,000)
/// Egreso $9,800  ──→ EgresoFuente(BBVA, $4,698.67)
///                └─→ EgresoFuente(Klar, $5,101.33)
/// ```
///
/// **Invariante:** `SUM(importe) == Egreso.monto` para todo Egreso cuyo
/// origen financiero sea una cuenta. La garantiza
/// `EgresoRepositoryImpl`, el único punto de escritura de Egresos del
/// proyecto, dentro de la misma transacción — no un `CHECK`, que no
/// puede expresar una suma agregada sobre otra tabla.
///
/// **Un gasto financiado con TDC no tiene fuentes.** Ese peso no sale
/// de ninguna cuenta al comprar: sale después, al pagar la tarjeta
/// (`RegistrarPagoDeudaUseCase`), y ese pago sí es un Egreso con su
/// propia fuente. `Egreso.deudaId` conserva intacta su arquitectura.
///
/// **Relación con `Egreso.cuentaFinancieraId`.** Esa columna queda como
/// *legacy* (ver su doc comment): se sigue escribiendo para no romper a
/// sus consumidores actuales, pero **ningún cálculo de saldo la usa**.
/// `calcularSaldos` lee exclusivamente esta tabla, así que una salida
/// se cuenta exactamente una vez y nunca se suman ambas.
class EgresoFuente extends Table with AuditColumns {
  TextColumn get egresoId => text().references(Egreso, #id, onDelete: KeyAction.cascade)();

  /// `restrict`, igual que el resto de las referencias a cuentas: una
  /// cuenta con movimientos no se borra, se desactiva.
  TextColumn get cuentaFinancieraId =>
      text().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  /// Centavos, siempre `> 0`. Que la suma cuadre con `Egreso.monto` es
  /// responsabilidad del repositorio; que cada renglón sea positivo se
  /// puede exigir aquí y se exige.
  IntColumn get importe => integer()();

  @override
  List<String> get customConstraints => [
        'CHECK (importe > 0)',
        // Una cuenta no puede aparecer dos veces en el mismo Egreso:
        // dos renglones de la misma cuenta son un solo renglón con la
        // suma, y permitirlo abriría la puerta a distribuciones
        // ambiguas que después nadie sabe corregir.
        'UNIQUE (egreso_id, cuenta_financiera_id)',
      ];
}
