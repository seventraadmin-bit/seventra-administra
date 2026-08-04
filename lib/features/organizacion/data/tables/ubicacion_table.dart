import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'servicio_table.dart';
import 'sucursal_table.dart';

/// Tipo de un nodo de [Ubicacion]. `sucursal`/`servicio` son los tipos que
/// puede tener únicamente un nodo raíz; el resto son de nodos hijos.
/// Deliberadamente sin "Vehículo" ni "En poder de empleado" — esos son
/// dimensiones independientes de `SituacionRecurso` (custodio, vehículo
/// asignado), no tipos de lugar físico.
enum TipoUbicacion {
  sucursal,
  oficina,
  almacen,
  servicio,
  areaInternaServicio,
  taller,
  resguardo,
  bajaTemporal,
}

/// Nodo del árbol de ubicaciones físicas de una Sucursal o Servicio.
///
/// Sin columna `ubicacionRaizId` en `Sucursal`/`Servicio`: la raíz se
/// identifica por ser el único nodo con `parentId IS NULL` para ese
/// dueño, resuelta por consulta desde `UbicacionRepository`.
///
/// El contexto de dueño (`sucursalId`/`servicioId`) se guarda **solo en
/// el nodo raíz** — los hijos lo heredan recorriendo `parentId` hacia
/// arriba, nunca lo repiten. Esto evita que un hijo quede inconsistente
/// con su padre por tener su propia copia (posiblemente distinta) del
/// dueño. La regla exacta (raíz con exactamente un dueño, hijo con
/// ambos nulos) es un `CHECK` de tabla, no solo una convención de la
/// capa de aplicación.
class Ubicacion extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get nombre => text()();

  TextColumn get tipoUbicacion => text()();

  TextColumn get parentId =>
      text().nullable().references(Ubicacion, #id, onDelete: KeyAction.restrict)();

  TextColumn get sucursalId =>
      text().nullable().unique().references(Sucursal, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId =>
      text().nullable().unique().references(Servicio, #id, onDelete: KeyAction.restrict)();

  @override
  List<String> get customConstraints => [
        // Una ubicación nunca puede ser su propio padre.
        'CHECK (parent_id IS NULL OR parent_id != id)',
        // Raíz: exactamente un dueño. Hijo: ningún dueño propio (lo hereda).
        'CHECK ('
            '(parent_id IS NULL AND ('
            '(sucursal_id IS NOT NULL AND servicio_id IS NULL) OR '
            '(sucursal_id IS NULL AND servicio_id IS NOT NULL)'
            ')) '
            'OR '
            '(parent_id IS NOT NULL AND sucursal_id IS NULL AND servicio_id IS NULL)'
            ')',
      ];
}
