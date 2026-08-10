import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// Catálogo administrable de categorías de artículo (Etapa 7A) — nace
/// vacío, RISEG lo captura desde una pantalla propia (mismo criterio
/// que `CategoriaFinanciera`, Etapa 4K.1: nunca un enum Dart rígido,
/// nunca una lista fija sembrada). Deliberadamente sin `codigo` ni
/// `tipo`/`tipoMovimiento` — a diferencia de `CategoriaFinanciera`,
/// una Categoría de artículo no necesita distinguir ingreso/egreso,
/// así que se queda con el mínimo campo que aporta valor: el nombre.
/// Sin eliminación física: `archivar` mueve `cicloVidaRegistro` a
/// `archivado`, nunca borra la fila.
class CategoriaArticulo extends Table with AuditColumns {
  TextColumn get nombre => text()();
}
