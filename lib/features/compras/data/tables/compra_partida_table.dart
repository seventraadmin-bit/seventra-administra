import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../inventario/data/tables/articulo_table.dart';
import '../../../inventario/data/tables/articulo_variante_table.dart';
import '../../../inventario/data/tables/movimiento_inventario_table.dart';
import 'compra_table.dart';

/// A dónde va una `CompraPartida` (Etapa 10) — el discriminador que
/// permite que una sola `Compra` mezcle renglones con destinos
/// distintos sin necesitar dos tablas ni dos flujos de captura. Un
/// renglón `inventario` siempre referencia un `Articulo` real del
/// catálogo (nunca texto libre); un renglón `gastoDirecto` nunca genera
/// `MovimientoInventario`, solo cuenta hacia el total de la Compra (y
/// por lo tanto hacia su Egreso).
enum DestinoCompraPartida { inventario, gastoDirecto }

/// Un renglón de una `Compra` (Etapa 10) — "qué se compró, cuánto, a
/// cuánto". Inmutable una vez creado: no existe ningún
/// `corregirPartida`; un error de cantidad/costo ya comprometido a
/// Inventario/Finanzas se corrige cancelando la `Compra` completa y
/// registrando una nueva (mismo criterio que `MovimientoInventario`
/// nunca se edita).
///
/// `varianteId` solo se valida contra `Articulo.manejaVariante` en el
/// caso de uso, nunca vía `CHECK` (no puede leer una columna de la
/// tabla padre — mismo criterio ya usado en todo el proyecto).
///
/// Para un Artículo serializado (`manejaSerie == true`), una partida
/// con `cantidad = N` representa la intención capturada ("3 radios"),
/// pero al confirmarse produce N filas en `ArticuloUnidad`/
/// `MovimientoInventario` (una por número de serie) — nunca una sola
/// fila con `cantidad = N`, porque `MovimientoInventario` ya exige
/// `unidad_id IS NULL OR cantidad = 1`. Ver `CompraPartidaMovimiento`
/// para cómo se resuelve esa relación 1→N.
class CompraPartida extends Table with AuditColumns {
  TextColumn get compraId => text().references(Compra, #id, onDelete: KeyAction.restrict)();

  TextColumn get destino => text()();

  TextColumn get articuloId => text().nullable().references(Articulo, #id, onDelete: KeyAction.restrict)();

  TextColumn get varianteId => text().nullable().references(ArticuloVariante, #id, onDelete: KeyAction.restrict)();

  /// Requerido si `destino == gastoDirecto`; `NULL` si `destino == inventario`.
  TextColumn get concepto => text().nullable()();

  IntColumn get cantidad => integer()();

  /// Centavos.
  IntColumn get costoUnitario => integer()();

  @override
  List<String> get customConstraints => [
        "CHECK (destino <> 'gastoDirecto' OR articulo_id IS NULL)",
        "CHECK (destino <> 'inventario' OR articulo_id IS NOT NULL)",
        'CHECK (cantidad > 0)',
        'CHECK (costo_unitario >= 0)',
      ];
}

/// Tabla puente CompraPartida↔MovimientoInventario (Etapa 10) — el
/// origen navegable "Origen: Compra COM-000001" que hoy no existe en
/// ningún lugar de Inventario. Deliberadamente **no** son columnas
/// nuevas en `MovimientoInventario`: esa tabla es el ledger central de
/// Inventario y ya sirve 4 flujos ajenos a Compras (bajas, ajustes,
/// cierres de Asignacion, devoluciones); contaminarla con un concepto
/// que solo aplica a veces es peor diseño que una tabla puente opcional
/// que no le cambia el esquema en absoluto.
///
/// `movimientoInventarioId` es la PK (no compuesta): un
/// `MovimientoInventario` pertenece a lo más a una `CompraPartida` — 1
/// fila por movimiento, N filas por partida serializada (una por
/// unidad adquirida).
class CompraPartidaMovimiento extends Table {
  TextColumn get compraPartidaId => text().references(CompraPartida, #id, onDelete: KeyAction.restrict)();

  TextColumn get movimientoInventarioId =>
      text().references(MovimientoInventario, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column> get primaryKey => {movimientoInventarioId};
}
