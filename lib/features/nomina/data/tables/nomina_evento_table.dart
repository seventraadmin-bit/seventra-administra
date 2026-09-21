import 'package:drift/drift.dart';

import '../../../usuarios/data/tables/usuario_table.dart';
import 'nomina_empleado_table.dart';
import 'nomina_table.dart';

/// Tipo de evento del historial de una Nómina — cubre tanto eventos de
/// periodo completo (`nominaEmpleadoId == null`) como de un renglón
/// específico, en la misma tabla append-only (mismo criterio que
/// `EmpleadoEvento`/`PagoEvento`).
enum TipoEventoNomina {
  generada,
  actualizadaDesdePersonal,
  movimientoModificado,
  distribucionModificada,
  cerrada,
  /// Etapa 4 — corrección de un renglón mientras la Nómina ya está
  /// `cerrada`/`pagada` (nunca en Borrador, ahí sigue siendo
  /// `movimientoModificado`/`distribucionModificada`) — siempre con
  /// `estadoAnterior`/`estadoNuevo` y motivo obligatorio.
  corregida,
  /// Etapa 4 — la Nómina cruzó automáticamente de `cerrada` a `pagada`
  /// (todos los renglones reportan `pagado`) — ver
  /// `PagoNominaRepositoryImpl._evaluarNominaPagada`.
  pagada,
  /// Etapa 4 — la Nómina regresó de `pagada` a `cerrada` (una
  /// cancelación de pago o una corrección reabrió saldo pendiente).
  reabierta,
  /// Etapa 4 — un renglón se eliminó por completo (solo posible desde
  /// "Actualizar desde Personal", nunca con movimientos manuales
  /// capturados) — `datosRelevantes` conserva sus valores clave, ya
  /// que la fila en sí desaparece.
  renglonEliminado,
  /// Etapa 4 — la Nómina completa se canceló (`CancelarNominaUseCase`,
  /// solo Borrador o Cerrada-sin-pagos).
  cancelada,
}

/// Historial append-only de una Nómina (Etapa 6C) — tabla de solo
/// inserción, mismo criterio que `EmpleadoEvento`/`PagoEvento`/
/// `IngresoEvento`/`ComplementoPagoEvento`.
///
/// `nominaEmpleadoId` nulo significa un evento de la Nómina completa
/// (`generada`, `actualizadaDesdePersonal`, `cerrada`); no nulo, un
/// evento de un renglón específico (`movimientoModificado`,
/// `distribucionModificada`) — una sola tabla en vez de dos, mismo
/// criterio de simplicidad ya usado en el diseño aprobado.
class NominaEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get nominaId => text().references(Nomina, #id, onDelete: KeyAction.cascade)();

  TextColumn get nominaEmpleadoId => text().nullable().references(NominaEmpleado, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  // Literal en vez de referencia al enum — mismo motivo de siempre.
  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();

  /// **Legacy (Etapa 11D)** — nunca se pobló con un valor real; se
  /// conserva la columna físicamente por seguridad de migración pero
  /// ningún código desde 11D en adelante la lee ni la escribe. La única
  /// fuente funcional de "quién" es `actorUsuarioId`.
  TextColumn get actor => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get datosRelevantes => text().nullable()();

  /// Etapa 4 (Nómina — corrección/cancelación/trazabilidad integral):
  /// convención de auditoría de Etapa 2, vía `DiffEvento` — únicamente
  /// los campos que realmente cambiaron, nunca un snapshot completo.
  /// `null` en filas históricas anteriores a esta etapa (migración
  /// aditiva, nunca se rellenan retroactivamente).
  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();
}
