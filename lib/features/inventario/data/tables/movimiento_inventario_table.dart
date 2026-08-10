import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'articulo_table.dart';
import 'articulo_unidad_table.dart';
import 'articulo_variante_table.dart';

/// Vocabulario fijo y pequeño de movimientos. `entrada` es la forma
/// normal de aumentar la existencia (con costo, de una compra); `baja`
/// es la forma normal de sacarla definitivamente del Total (decomiso,
/// daño/pérdida detectados antes de asignar). Sin `cantidad` con
/// signo: `ajusteEntrada`/`ajusteSalida` cubren correcciones (conteo
/// físico, mermas) con el mismo efecto en el bucket que `entrada`/
/// `baja` pero se reportan por separado — nunca se confunde una
/// compra real con una corrección de conteo.
///
/// `salidaAsignacion`/`entradaDevolucion`/`salidaDano`/`salidaPerdida`
/// (Etapa 7B) siempre se originan cerrando/creando una `Asignacion` —
/// nunca de forma suelta — y por eso siempre parten de/hacia el
/// bucket Asignado, nunca directo Disponible↔Dañado (ver
/// `AsignacionRepositoryImpl`). Agregarlos no requirió migración
/// (columna literal, sin `CHECK` que restrinja valores, mismo
/// criterio que el resto del proyecto).
enum TipoMovimientoInventario {
  entrada,
  baja,
  ajusteEntrada,
  ajusteSalida,
  salidaAsignacion,
  entradaDevolucion,
  salidaDano,
  salidaPerdida,
}

/// El ledger de existencias de Inventario (Etapa 7A) — la única fuente
/// de verdad de cuánto hay de un `Articulo`/`ArticuloVariante`, o en
/// qué bucket está una `ArticuloUnidad`. Nunca se guarda un total
/// aparte: "Disponible"/"Asignado"/"Dañado"/"Perdido"/"Total" se
/// derivan agregando estas filas (o, para unidades serializadas,
/// contando `ArticuloUnidad.estatus`) — ver
/// `InventarioRepository.calcularExistencia`.
///
/// `varianteId`/`unidadId` son mutuamente excluyentes: un movimiento
/// de un Artículo con variante trae `varianteId` (y `unidadId` nulo);
/// uno de una unidad serializada trae `unidadId` con `cantidad = 1`
/// (y `varianteId` nulo); uno de un Artículo simple (sin variante ni
/// serie) no trae ninguno de los dos.
///
/// Sin columna `actor` heredada de un patrón *Evento aparte: esta
/// tabla ya es en sí misma el historial/auditoría de Inventario (a
/// diferencia de `Pago`/`PagoNomina`, que delegan esa función a
/// `PagoEvento`/`PagoNominaEvento`), así que carga su propio `actor`
/// directamente.
class MovimientoInventario extends Table with AuditColumns {
  TextColumn get articuloId => text().references(Articulo, #id, onDelete: KeyAction.restrict)();

  TextColumn get varianteId => text().nullable().references(ArticuloVariante, #id, onDelete: KeyAction.restrict)();

  TextColumn get unidadId => text().nullable().references(ArticuloUnidad, #id, onDelete: KeyAction.restrict)();

  IntColumn get cantidad => integer()();

  // Literal en vez de referencia al enum — mismo motivo de siempre.
  TextColumn get tipoMovimiento => text()();

  DateTimeColumn get fecha => dateTime()();

  /// Solo tiene sentido en movimientos `entrada` — costo total nunca
  /// se guarda, se deriva como `cantidad × costoUnitario` donde se
  /// necesite mostrarlo.
  IntColumn get costoUnitario => integer().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get actor => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (variante_id IS NULL OR unidad_id IS NULL)',
        'CHECK (cantidad > 0)',
        'CHECK (unidad_id IS NULL OR cantidad = 1)',
        'CHECK (costo_unitario IS NULL OR costo_unitario >= 0)',
      ];
}
