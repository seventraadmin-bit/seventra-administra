import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/cuenta_financiera_table.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import '../../../inventario/data/tables/asignacion_table.dart';
import '../../../personal/data/tables/empleado_table.dart';

/// Tipo de obligación económica programada — catálogo abierto (texto
/// literal, no un `CHECK` cerrado): la arquitectura no debe quedar
/// limitada a préstamo/botas, un tipo futuro no requiere migración.
enum TipoDescuentoProgramado { prestamo, botas }

/// Ciclo de vida de la obligación completa (el padre de sus cuotas) —
/// distinto de `AuditColumns.cicloVidaRegistro` (ese es técnico; este es
/// el estado de negocio real).
enum EstatusDescuentoProgramado { activo, liquidado, cancelado }

/// Obligación económica programada de un Empleado (Etapa 15,
/// "Descuentos Programados al Personal") — préstamo, costo de botas, o
/// un tipo futuro. Fuente de verdad del COBRO; Inventario sigue siendo
/// la fuente de verdad de existencia/asignación/resguardo
/// ([asignacionOrigenId] es un vínculo opcional de solo lectura, nunca
/// una relación inferida por nombre de artículo).
///
/// [saldoPendiente] es un total cacheado — igual que
/// `NominaEmpleado.totalAPagar` — **nunca la única evidencia**: siempre
/// reconstruible desde `DescuentoProgramadoCuota` (cuotas no
/// `cancelada` sin `aplicada`) y el historial append-only en
/// `DescuentoProgramadoMovimiento`.
class DescuentoProgramadoEmpleado extends Table with AuditColumns {
  /// `PRE-000012`/`DES-000015` — vía `CodigoSecuenciaService`, un
  /// `entityType` distinto por [tipo] (`descuentoProgramadoPrestamo`/
  /// `descuentoProgramadoBotas`) para que cada uno tenga su propio
  /// prefijo y contador.
  TextColumn get folio => text().unique()();

  TextColumn get empleadoId =>
      text().references(Empleado, #id, onDelete: KeyAction.restrict)();

  // Literal en vez de referencia al enum — mismo motivo que
  // `AuditColumns.cicloVidaRegistro`: catálogo abierto, un tipo nuevo no
  // requiere migración.
  TextColumn get tipo => text()();

  DateTimeColumn get fechaRegistro => dateTime()();

  IntColumn get importeOriginal => integer()();

  IntColumn get saldoPendiente => integer()();

  TextColumn get descripcion => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('activo'))();

  /// Vínculo opcional a la `Asignacion` de Inventario que originó el
  /// cobro (ej. "estas botas entregadas") — nunca inferido por nombre
  /// de artículo, solo si el operador lo elige explícitamente al
  /// capturar. `restrict`: una `Asignacion` referenciada por un cobro
  /// real no puede desaparecer en silencio.
  TextColumn get asignacionOrigenId =>
      text().nullable().references(
        Asignacion,
        #id,
        onDelete: KeyAction.restrict,
      )();

  TextColumn get observaciones => text().nullable()();

  /// Origen financiero real del desembolso — presente SOLO cuando la
  /// obligación representó una entrega de dinero real (típicamente un
  /// préstamo pagado desde una cuenta), nunca cuando es una simple
  /// recuperación de un costo ya pagado en otro módulo (ej. botas ya
  /// compradas). La SEÑAL de "hubo desembolso" es la presencia de estas
  /// dos columnas — NUNCA el valor de [tipo] (catálogo abierto, no debe
  /// usarse para inferir semántica financiera).
  ///
  /// [egresoId] no lleva `.unique()` a nivel de columna: SQLite no
  /// permite agregar esa restricción vía `ALTER TABLE` a una tabla ya
  /// existente (mismo caso ya resuelto en
  /// `TiempoExtraCostoAdicional.egresoId`, ver su doc comment). La
  /// invariante "a lo más un DescuentoProgramado por Egreso" se cumple
  /// por construcción: `registrar()` siempre crea un Egreso nuevo,
  /// nunca reutiliza uno existente.
  TextColumn get cuentaFinancieraId => text().nullable().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  TextColumn get egresoId => text().nullable().references(Egreso, #id, onDelete: KeyAction.restrict)();

  @override
  List<String> get customConstraints => [
    'CHECK (importe_original > 0)',
    'CHECK (saldo_pendiente >= 0)',
    'CHECK (saldo_pendiente <= importe_original)',
  ];
}
