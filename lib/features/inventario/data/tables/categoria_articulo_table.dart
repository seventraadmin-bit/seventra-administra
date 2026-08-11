import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// Qué módulo especializado (ajeno a Inventario) consume esta Categoría
/// — Etapa 9D, ajuste posterior a la aprobación inicial. Estructurado
/// (nunca se compara `nombre` como texto libre — Marlon fue explícito:
/// "si depender del texto de la categoría sería frágil, no lo hagas").
/// "Serializado" (`Articulo.manejaSerie`) sigue siendo una capacidad
/// genérica de Inventario; esto es un campo ortogonal y opcional que
/// solo importa cuando un dominio ajeno (hoy Telefonía) necesita saber
/// "¿las unidades de esta categoría son candidatas a mi flujo?". Un
/// solo valor hoy — extensible el día que exista un caso real
/// (radiocomunicación, cómputo) sin volver a tocar el modelo.
enum AplicacionEspecializadaCategoriaArticulo { telefonia }

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

  /// Nullable — `null` = categoría genérica, sin cambio de
  /// comportamiento (Etapa 9D, ajuste posterior).
  TextColumn get aplicacionEspecializada => text().nullable()();
}
