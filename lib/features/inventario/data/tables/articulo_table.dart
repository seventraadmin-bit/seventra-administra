import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'categoria_articulo_table.dart';

/// El catálogo central de Inventario (Etapa 7A) — "qué es", nunca
/// "cuánto hay" (eso se deriva de `MovimientoInventario`, ver el doc
/// comment de esa tabla) ni "cuál es la variante/unidad concreta" (ver
/// `ArticuloVariante`/`ArticuloUnidad`).
///
/// `manejaVariante`/`manejaSerie` son independientes a propósito — un
/// Artículo normalmente activa una sola de las dos (uniformes con
/// talla vs. equipo serializado), pero no se fuerza con un `CHECK` que
/// bloquee una combinación futura legítima que hoy no se conoce; la UI
/// solo habilita la sección correspondiente según las banderas.
///
/// Sin columna `estatus` propia: "activo/inactivo" es exactamente lo
/// que ya cubre `cicloVidaRegistro` (activo/archivado) — mismo
/// criterio que el doc comment de `AuditColumns` pide para cualquier
/// campo que solo necesite "existe / no existe".
class Articulo extends Table with AuditColumns {
  TextColumn get folio => text().unique()();

  TextColumn get categoriaId => text().references(CategoriaArticulo, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  TextColumn get descripcion => text().nullable()();

  /// Texto libre ("pieza", "par", "kit") — deliberadamente sin
  /// catálogo propio, la variedad real no justifica un catálogo más
  /// (Resolución explícita de Marlon: "no pedir campos que no aporten
  /// valor operativo").
  TextColumn get unidadMedida => text().nullable()();

  BoolColumn get manejaVariante => boolean().withDefault(const Constant(false))();

  BoolColumn get manejaSerie => boolean().withDefault(const Constant(false))();

  /// Orientativo, editable a mano — deja de usarse en cuanto existan
  /// entradas reales capturadas (ver `calcularCostoPromedioArticulo`),
  /// nunca participa en el cálculo de costo una vez que hay historial.
  IntColumn get costoReferencia => integer().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (costo_referencia IS NULL OR costo_referencia >= 0)'];
}
