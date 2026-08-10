import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import 'empleado_table.dart';

/// Ficha técnica corporativa de un Empleado (Etapa 5E) — el PDF
/// profesional y reducido que se comparte con un cliente, siempre
/// generado a partir de información que ya existe en el expediente,
/// nunca una nueva captura.
///
/// Cada clic en "Generar ficha" inserta una fila **nueva** — nunca se
/// actualiza ni se sobrescribe una anterior (mismo criterio append-only
/// que `DocumentoPorEmitir`/`Pago`: el PDF ya generado es un snapshot
/// inmutable de lo que en ese momento se envió al cliente). Si después
/// cambia el servicio, el teléfono, la experiencia o una evaluación del
/// Empleado, las fichas ya generadas no se tocan — reflejan exactamente
/// lo que existía al momento de `createdAt` (Resolución 6 de Marlon).
///
/// `servicioId` es el Servicio vigente *al momento de generar* (puede
/// ser `null` — empleados administrativos adscritos a Sucursal, o sin
/// asignación vigente todavía tienen ficha válida). El Cliente nunca se
/// guarda aquí de forma redundante: se deriva en consulta vía
/// `servicioId -> Servicio.clienteId` (inmutable una vez creado el
/// Servicio) — mismo principio de 5D, "liga información, no la
/// duplica".
///
/// `attachmentId` es una FK directa (no una tabla puente como
/// `EmpleadoAttachment`): una Ficha es dueña exclusiva de exactamente
/// un PDF, relación 1:1, así que el patrón correcto es el mismo puntero
/// directo que `Empleado.fotografiaAttachmentId`, no el patrón de
/// junction table pensado para adjuntos múltiples/genéricos por dueño.
/// Nunca nulo: la fila solo se inserta una vez que el PDF ya existe
/// físicamente en disco (el use case genera el archivo primero, igual
/// que cualquier otro flujo de adjuntos del proyecto).
///
/// `camposExcluidos` guarda, separadas por coma, las secciones
/// opcionales que el usuario decidió **no** incluir en esa generación
/// puntual (ej. `'fotografia,antidoping'`) — necesario para que el
/// historial pueda explicar por qué dos fichas del mismo Empleado no
/// dicen lo mismo. `null`/vacío significa "se incluyó todo lo
/// disponible".
class FichaTecnicaEmpleado extends Table with AuditColumns {
  TextColumn get folio => text().unique()();

  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.restrict)();

  TextColumn get camposExcluidos => text().nullable()();
}
