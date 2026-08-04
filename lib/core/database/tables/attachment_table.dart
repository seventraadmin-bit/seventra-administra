import 'package:drift/drift.dart';

/// Almacenamiento mínimo de archivos adjuntos — infraestructura, no el
/// módulo de Documentos.
///
/// Deliberadamente sin `uploadedBy` (no hay Usuario todavía), sin
/// `expiresAt`/`estadoFirma` (sin cumplimiento documental todavía), sin
/// versionado. Solo crear/consultar/relacionar: no existe ningún método
/// de eliminación física en [AttachmentRepository] — el reemplazo, baja y
/// versionado se resuelven cuando exista el módulo de Documentos.
///
/// No usa el mixin `AuditColumns`: un archivo no se "edita" (se
/// reemplaza con otro registro), así que no tiene `updatedAt` ni
/// `cicloVidaRegistro` — ninguno de los dos tendría un significado real
/// todavía.
class Attachment extends Table {
  TextColumn get id => text()();

  TextColumn get empresaId => text().nullable()();

  TextColumn get clienteId => text().nullable()();

  TextColumn get originalFileName => text()();

  TextColumn get storedFileName => text()();

  TextColumn get path => text()();

  TextColumn get mimeType => text()();

  IntColumn get sizeBytes => integer()();

  TextColumn get hash => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT',
        'FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT',
        'CHECK ('
            '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END) = 1'
            ')',
      ];
}
