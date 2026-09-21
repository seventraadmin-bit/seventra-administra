import 'package:drift/drift.dart';

import '../../../usuarios/data/tables/usuario_table.dart';
import 'descuento_programado_cuota_table.dart';
import 'descuento_programado_empleado_table.dart';

/// Historial append-only de una obligación programada (Etapa 15) —
/// mismo criterio exacto que `NominaEvento`/`EmpleadoEvento`/
/// `PagoNominaEvento`: nunca se sobrescribe, solo se inserta.
/// `cuotaId` nulo significa un evento a nivel de la obligación completa
/// (`otorgamiento`, `cancelacion`); no nulo, un evento de una cuota
/// específica (`cuotaReservada`/`cuotaAplicada`/`cuotaRevertida`).
enum TipoMovimientoDescuentoProgramado {
  otorgamiento,
  cuotaReservada,
  cuotaAplicada,
  cuotaRevertida,
  reprogramacion,
  cancelacion,
  /// Etapa 5 — corrección de campos administrativos y/o del monto
  /// total de la obligación (`CorregirDescuentoProgramadoUseCase`),
  /// siempre con `estadoAnterior`/`estadoNuevo` poblados vía
  /// `DiffEvento` y motivo obligatorio.
  correccion,
}

class DescuentoProgramadoMovimiento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get descuentoProgramadoId =>
      text().references(
        DescuentoProgramadoEmpleado,
        #id,
        onDelete: KeyAction.cascade,
      )();

  TextColumn get cuotaId =>
      text().nullable().references(
        DescuentoProgramadoCuota,
        #id,
        onDelete: KeyAction.cascade,
      )();

  DateTimeColumn get fechaHora => dateTime()();

  // Literal en vez de referencia al enum — mismo motivo de siempre.
  TextColumn get tipoMovimiento => text()();

  IntColumn get importe => integer().nullable()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId =>
      text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  /// JSON — usado sobre todo por `reprogramacion` (plan anterior + plan
  /// nuevo), mismo patrón que `NominaEvento.datosRelevantes`.
  TextColumn get datosRelevantes => text().nullable()();

  /// Etapa 5 — convención de auditoría de Etapa 2, vía `DiffEvento`:
  /// únicamente los campos administrativos/monto que realmente
  /// cambiaron en una corrección (`tipoMovimiento == correccion`).
  /// `null` en todo movimiento histórico anterior a esta etapa —
  /// migración aditiva, nunca se rellena retroactivamente.
  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();
}
