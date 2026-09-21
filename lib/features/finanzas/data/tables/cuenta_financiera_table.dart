import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';

enum TipoCuentaFinanciera { banco, efectivo }

/// Fuente real de dinero de la empresa (Etapa 19C: Banco/Efectivo) —
/// NUNCA guarda un `saldoActual`: el saldo se deriva siempre como
/// `saldoInicial + SUM(Ingreso.monto) - SUM(Egreso.monto)` sobre los
/// movimientos vinculados con `fecha >= fechaSaldoInicial` (ver
/// `CuentaFinancieraRepository.calcularSaldo`) — igual que
/// `saldoPendiente` de CxC o `saldoActual` de Deuda: un campo
/// persistido que pudiera desincronizarse de sus movimientos es
/// exactamente lo que este proyecto evita.
///
/// `institucionId` reutiliza el catálogo `Banco` ya existente (Etapa
/// 6A, hoy exclusivo de datos bancarios del Empleado) — su propio doc
/// comment ya señalaba esta reutilización como candidata futura;
/// evita "BBVA"/"Bbva"/"bbva" como 3 valores de texto libre distintos.
/// Solo tiene sentido cuando `tipo == banco` — nunca poblado para
/// `efectivo`, mismo criterio condicional-por-tipo que los campos
/// `tarjetaXxx` de `Deuda`.
///
/// Activar/desactivar usa `cicloVidaRegistro` (de `AuditColumns`) — no
/// se agrega una columna `activa` redundante, mismo criterio que el
/// resto de entidades con un ciclo de vida simple "existe/no existe".
class CuentaFinanciera extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get nombre => text()();

  TextColumn get tipo => text()();

  TextColumn get institucionId => text().nullable().references(Banco, #id, onDelete: KeyAction.restrict)();

  TextColumn get ultimosDigitos => text().nullable()();

  /// Centavos — "lo que había" a la fecha [fechaSaldoInicial]. Nunca se
  /// corrige libremente una vez que la cuenta ya tiene movimientos
  /// reales asociados (mismo criterio que `Deuda.importeOriginal`) —
  /// ver `CuentaFinancieraRepository.corregir`.
  IntColumn get saldoInicial => integer()();

  DateTimeColumn get fechaSaldoInicial => dateTime()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (saldo_inicial >= 0)'];
}
