import 'package:drift/drift.dart';

import '../../../usuarios/data/tables/usuario_table.dart';
import 'articulo_unidad_table.dart';

/// Bitácora de correcciones sensibles sobre la identidad de una
/// `ArticuloUnidad` (número de serie, marca, modelo, IMEI 1/IMEI 2) —
/// nace con `CorregirIdentidadUnidadUseCase`, la única vía que puede
/// escribir aquí. Una fila por cada campo que realmente cambió (nunca
/// una fila por corrección completa con varios campos mezclados) —
/// mismo criterio de columnas dedicadas `estadoAnterior`/`estadoNuevo`
/// ya usado por `CompraEvento`, en vez de un blob JSON. FK real a
/// `ArticuloUnidad` con `KeyAction.restrict` (la unidad siempre sigue
/// existiendo al momento de leer el evento — no es el caso especial de
/// `EliminacionFisicaEvento`), `actorUsuarioId` nullable con `SET NULL`
/// — mismo molde que `EquipoTelefonicoEvento`.
class ArticuloUnidadEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get unidadId => text().references(ArticuloUnidad, #id, onDelete: KeyAction.restrict)();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get fechaHora => dateTime()();

  // Literal en vez de referencia a enum — mismo motivo de siempre en
  // este proyecto. Un solo valor hoy ('correccionIdentidad'), pero deja
  // la puerta abierta a otros tipos de evento de Inventario sobre una
  // unidad sin tener que crear otra tabla.
  TextColumn get tipoEvento => text()();

  /// Cuál dato se corrigió: `'numeroSerie'` | `'marca'` | `'modelo'` |
  /// `'imei1'` | `'imei2'`.
  TextColumn get campo => text()();

  TextColumn get valorAnterior => text().nullable()();

  TextColumn get valorNuevo => text().nullable()();

  TextColumn get motivo => text()();
}
