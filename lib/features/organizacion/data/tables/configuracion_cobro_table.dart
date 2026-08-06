import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'servicio_table.dart';

/// Identidad estable de la Configuración de cobro de un Servicio (Etapa
/// 4H.1) — a diferencia de las líneas comerciales (que pueden ser
/// varias por Servicio), un Servicio tiene una sola forma de cobrarse:
/// `servicioId` lleva un `.unique()` real, 1:1. Sin datos propios más
/// allá de `AuditColumns` — mismo motivo que `ServicioLineaComercial`:
/// todo lo real vive versionado en `ConfiguracionCobroVigencia`.
class ConfiguracionCobro extends Table with AuditColumns {
  TextColumn get servicioId =>
      text().unique().references(Servicio, #id, onDelete: KeyAction.restrict)();
}
