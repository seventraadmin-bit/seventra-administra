import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'articulo_table.dart';

/// Talla/variante de un `Articulo` con `manejaVariante == true` (Etapa
/// 7A) — "artículo + variante" en vez de un producto nuevo por talla
/// (Resolución explícita de Marlon: nunca `CamisaTallaM`/`CamisaTallaL`
/// como artículos separados). `valor` es texto libre ("M", "34", "27")
/// — una sola dimensión, sin matriz de variantes (color × talla, etc.)
/// porque RISEG no la necesita hoy.
///
/// La existencia se cuenta por el par `(articuloId, varianteId)` —
/// ver el doc comment de `MovimientoInventario`. Que `valor` solo
/// tenga sentido cuando el `Articulo` referenciado tiene
/// `manejaVariante == true` se valida en el caso de uso, no aquí (un
/// `CHECK` no puede leer una columna de la tabla padre).
class ArticuloVariante extends Table with AuditColumns {
  TextColumn get articuloId => text().references(Articulo, #id, onDelete: KeyAction.restrict)();

  TextColumn get valor => text()();

  @override
  List<String> get customConstraints => ['UNIQUE (articulo_id, valor)'];
}
