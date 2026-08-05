import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'servicio_table.dart';

/// Identidad estable de una línea comercial de un Servicio (Etapa 4G.1) —
/// ej. "Guardias 24×24" o "Jefe de turno". Deliberadamente sin puesto,
/// cantidad, turno, precio ni descripción propios: todo eso es
/// versionado y vive en [ServicioLineaComercialVigencia] — si cambiara
/// aquí, un cambio de puesto o precio dejaría de poder distinguirse de
/// una edición normal, exactamente lo que la vigencia existe para evitar.
///
/// `cicloVidaRegistro` casi nunca se usa en la práctica (una línea con
/// alguna vigencia registrada nunca se "archiva" a sí misma — se
/// discontinúa cerrando su vigencia vigente sin reemplazo, ver
/// `ServicioComercialRepository.cerrarVigenciaSinReemplazo`); se
/// mantiene solo por la convención de `AuditColumns` en toda tabla de
/// negocio, reservado para el caso excepcional de una línea creada por
/// error antes de tener alguna vigencia real.
class ServicioLineaComercial extends Table with AuditColumns {
  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();
}
