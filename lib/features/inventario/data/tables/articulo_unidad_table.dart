import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'articulo_table.dart';

/// Estado de una unidad serializada — mantenido transaccionalmente en
/// cada `MovimientoInventario`/asignación que la toca (mismo criterio
/// que `NominaEmpleado.estatusPago`, Etapa 6D: existe por performance
/// de lectura, `MovimientoInventario` sigue siendo la fuente de verdad
/// por debajo). `asignado` no tiene comportamiento propio todavía —
/// `Asignacion` (Etapa 7B) es quien lo escribe.
/// Dónde está físicamente una unidad y si puede asignarse.
///
/// `enLavanderia`/`enReparacion`/`pendienteDesecho` se agregaron en la
/// etapa de conciliación de bajas: un bien recuperado del empleado pero
/// que todavía está en un destino intermedio NO está disponible. Antes,
/// enviar una prenda a lavandería la dejaba `disponible` — es decir,
/// reasignable mientras seguía en la tintorería.
///
/// Son estados de UBICACIÓN, no de condición: `danado` sigue siendo el
/// veredicto sobre el bien y `enReparacion` es dónde está mientras se
/// resuelve. Tres valores, no un ERP de taller: lo único que el sistema
/// necesita saber es dónde está y si puede asignarse.
///
/// `pendienteDesecho` es una DECISIÓN, no el hecho consumado: el
/// desecho real lo ejecuta `RegistrarBajaUnidadUseCase` —el ciclo
/// oficial de Inventario, que ya existía— y deja la unidad en `baja`.
enum EstatusArticuloUnidad {
  disponible,
  asignado,
  enLavanderia,
  enReparacion,
  pendienteDesecho,
  danado,
  perdido,
  baja;

  /// Recuperada del empleado pero todavía no asignable — el bien está
  /// en manos de RISEG, en un destino intermedio.
  bool get enDestinoIntermedio =>
      this == enLavanderia || this == enReparacion || this == pendienteDesecho;
}

/// Una unidad individualmente identificable de un `Articulo` con
/// `manejaSerie == true` (Etapa 7A) — radios, teléfonos: cada una se
/// cuenta y se rastrea por separado, nunca como cantidad (ver el doc
/// comment de `MovimientoInventario`).
///
/// `codigo` es una referencia corta interna de RISEG (vía
/// `CodigoSecuencia`, ej. `UNI-000123`), deliberadamente distinta de
/// `numeroSerie` (el número real de fábrica) — el mismo criterio que
/// separa `Empleado.numeroEmpleado` de `Empleado.curp`: uno es para
/// referirse a la unidad rápido en la operación diaria, el otro es el
/// dato real e inmutable del fabricante.
///
/// Que `Articulo.manejaSerie` sea `true` para poder crear una fila
/// aquí se valida en el caso de uso, no con un `CHECK` (no puede leer
/// una columna de la tabla padre).
class ArticuloUnidad extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get articuloId => text().references(Articulo, #id, onDelete: KeyAction.restrict)();

  TextColumn get numeroSerie => text().unique()();

  TextColumn get marca => text().nullable()();

  TextColumn get modelo => text().nullable()();

  // Literal en vez de referencia al enum — mismo motivo de siempre en
  // este proyecto (ver `AuditColumns.cicloVidaRegistro`).
  TextColumn get estatus => text().withDefault(const Constant('disponible'))();
}
