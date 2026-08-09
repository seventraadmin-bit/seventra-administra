import 'package:drift/drift.dart';

/// Estado del ciclo de vida propio de un adjunto (Etapa 4I.2.2) — eje
/// deliberadamente separado de `CicloVidaRegistro` (ver
/// `audit_columns.dart`): ese eje es "¿el registro técnico sigue
/// contando?", este es "¿esta versión física del archivo sigue siendo
/// la vigente?". Solo `activo`/`archivado` por ahora (lo mínimo pedido
/// por Marlon) — texto libre, así que agregar `reemplazado`/
/// `obsoleto`/`error` más adelante es solo un nuevo valor de enum, sin
/// migración.
enum EstadoAdjunto { activo, archivado }

/// Categoría de un adjunto de `DocumentoPorEmitir` (Etapa 4I.2.2) —
/// `null` para adjuntos de Empresa/Cliente (no aplica). `otroSoporte`
/// deliberadamente sin restricción de tipo de archivo (Resolución 7 de
/// Marlon).
enum CategoriaAdjuntoDocumentoPorEmitir { cfdiPdf, cfdiXml, reciboPdf, otroSoporte }

/// Almacenamiento de archivos adjuntos — infraestructura compartida,
/// no un módulo de Documentos propio.
///
/// Desde la Etapa 5A ya **no** declara ninguna columna de dueño. Nació
/// como "arco exclusivo" (una columna nullable + FK por cada posible
/// dueño, con un `CHECK` de "exactamente uno no nulo"), y se extendió
/// así 4 veces seguidas (4I.2.2 → 4J.2 → 4J.3 → 4K.1, hasta 7 vías).
/// Ante el roadmap completo de RISEG ONE (Personal, Inventario,
/// Vehículos, Compras, Uniformes, Equipos, Credenciales...) — muchos
/// más dueños futuros —, Marlon aprobó migrar a un diseño de tabla
/// puente por dominio: cada dueño tiene su propia tabla de unión
/// pequeña (ej. `PagoAttachment(attachmentId, pagoId)`, en
/// `features/finanzas/data/tables/`), cada una con FK reales en ambos
/// lados y `attachmentId` como llave primaria (equivalente a
/// `UNIQUE(attachmentId)` — un Attachment pertenece a lo más a un dueño
/// dentro de esa tabla puente). La exclusividad *entre* tablas puente
/// distintas ya no es un único `CHECK` declarativo — es un invariante
/// de aplicación: cada flujo de "adjuntar" inserta el `Attachment` y su
/// única fila de unión dentro de la misma transacción, nunca en dos
/// pasos independientes. A cambio, toda extensión futura (un dueño más)
/// vuelve a ser una migración puramente aditiva (`m.createTable`) —
/// nunca más una recreación estructural de esta tabla.
///
/// `Empresa.logoAttachmentId` sigue siendo la única referencia *hacia*
/// esta tabla (un puntero directo, no una relación de dueño) — no se
/// toca con este cambio.
///
/// Deliberadamente sin `uploadedBy` (no hay Usuario todavía), sin
/// `expiresAt`/`estadoFirma` (sin cumplimiento documental todavía).
/// Tampoco usa el mixin `AuditColumns` completo: un archivo no se
/// "edita" en el sentido de `updatedAt`, se reemplaza con otra fila —
/// `estado` es el único campo de ciclo de vida que necesita.
class Attachment extends Table {
  TextColumn get id => text()();

  /// Solo aplica cuando el dueño es `DocumentoPorEmitir`/
  /// `ComplementoPago` — `null` para el resto (sin categorías propias
  /// todavía).
  TextColumn get categoria => text().nullable()();

  TextColumn get originalFileName => text()();

  TextColumn get storedFileName => text()();

  TextColumn get path => text()();

  TextColumn get mimeType => text()();

  IntColumn get sizeBytes => integer()();

  TextColumn get hash => text().nullable()();

  TextColumn get estado => text().withDefault(const Constant('activo'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
