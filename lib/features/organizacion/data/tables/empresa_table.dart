import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';

/// Empresa operadora de RISEG ONE.
///
/// RISEG ONE opera con una sola empresa activa a la vez — garantizado por
/// el índice único parcial sobre `cicloVidaRegistro = 'activo'`, no por
/// una arquitectura multiempresa. La tabla sigue abierta a más de una
/// fila (un escenario de holding futuro no rompería el esquema), pero
/// `EmpresaRepository.obtenerActiva()` siempre espera encontrar
/// exactamente una.
///
/// Sin campo `estado` propio — `cicloVidaRegistro` ya expresa "activa/no
/// activa" y es literalmente el mecanismo del singleton; un campo de
/// negocio separado solo duplicaría el mismo concepto con otro nombre.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_empresa_activa_unica '
  "ON empresa (ciclo_vida_registro) WHERE ciclo_vida_registro = 'activo'",
)
class Empresa extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get razonSocial => text().nullable()();

  TextColumn get nombreComercial => text()();

  TextColumn get rfc => text().nullable().unique()();

  TextColumn get representanteLegal => text().nullable()();

  TextColumn get eslogan => text().nullable()();

  TextColumn get logoAttachmentId =>
      text().nullable().references(Attachment, #id, onDelete: KeyAction.restrict)();
}
