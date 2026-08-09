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
/// Arco exclusivo tipado de 3 vías (Etapa 4I.2.2, Resolución 9 de
/// Marlon: nunca un `entityType`/`entityId` genérico) — exactamente uno
/// de `empresaId`/`clienteId`/`documentoPorEmitirId` no nulo. Las FK se
/// declaran como SQL crudo en `customConstraints` (no `.references()`)
/// para no crear un import circular con `empresa_table.dart` (que ya
/// importa este archivo para `logoAttachmentId`).
///
/// Deliberadamente sin `uploadedBy` (no hay Usuario todavía), sin
/// `expiresAt`/`estadoFirma` (sin cumplimiento documental todavía).
/// Tampoco usa el mixin `AuditColumns` completo: un archivo no se
/// "edita" en el sentido de `updatedAt`, se reemplaza con otra fila —
/// `estado` es el único campo de ciclo de vida que necesita.
class Attachment extends Table {
  TextColumn get id => text()();

  TextColumn get empresaId => text().nullable()();

  TextColumn get clienteId => text().nullable()();

  TextColumn get documentoPorEmitirId => text().nullable()();

  /// Solo aplica cuando `documentoPorEmitirId` no es nulo — `null` para
  /// adjuntos de Empresa/Cliente.
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

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT',
        'FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT',
        'FOREIGN KEY (documento_por_emitir_id) REFERENCES documento_por_emitir (id) ON DELETE CASCADE',
        'CHECK ('
            '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN documento_por_emitir_id IS NOT NULL THEN 1 ELSE 0 END) = 1'
            ')',
      ];
}
