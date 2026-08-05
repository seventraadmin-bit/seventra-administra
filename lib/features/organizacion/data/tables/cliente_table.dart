import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';

/// Ciclo comercial real de un Cliente — independiente de
/// `cicloVidaRegistro`. "activo" aquí significa "cliente vigente
/// comercialmente", no "registro no archivado"; ambos conceptos pueden
/// discrepar (un cliente `terminado` hace años sigue teniendo su fila
/// intacta, solo cambia de `cicloVidaRegistro` si algún día se archiva).
enum EstatusCliente { prospecto, activo, suspendido, terminado, descartado }

class Cliente extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  /// Nombre identificador del Cliente comercial — ya no `razonSocial`:
  /// esa (junto con el RFC) pertenece a Entidad fiscal (Etapa 4E.2), una
  /// entidad distinta y separada. Un Cliente comercial puede agrupar
  /// varias Entidades fiscales (ej. Sportium), así que no tiene sentido
  /// que Cliente cargue una única razón social/RFC propios.
  TextColumn get nombreComercial => text()();

  /// Dato maestro conservado desde la Etapa 4A — sin consumidor real
  /// todavía (segmentación comercial, cotizaciones, reportes, CRM), por
  /// eso no se expone en la interfaz de la Etapa 4E.1. Se conserva en el
  /// esquema para no tener que reintroducirlo con otra migración cuando
  /// sí exista ese consumidor.
  TextColumn get industriaId => text().nullable().references(Industria, #id)();

  // Literal en vez de referencia al enum: ver la nota en
  // `AuditColumns.cicloVidaRegistro` sobre por qué (mismo SQL resultante).
  TextColumn get estatus => text().withDefault(const Constant('prospecto'))();

  DateTimeColumn get fechaAlta => dateTime().withDefault(currentDateAndTime)();

  TextColumn get observaciones => text().nullable()();
}
