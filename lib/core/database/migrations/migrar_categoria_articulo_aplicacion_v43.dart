import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 9D, segundo ajuste posterior a la aprobación
/// inicial (`schemaVersion` 42 → 43): agrega
/// `CategoriaArticulo.aplicacionEspecializada`.
///
/// Causa raíz corregida aquí: comprar un artículo con `manejaSerie:
/// false` ("SMARTPHONE" en la prueba real de Marlon) siempre generó
/// (correctamente, según su configuración) existencia por cantidad —
/// eso nunca fue un bug del flujo de Compras. El hueco real era que
/// Telefonía no tenía forma ESTRUCTURADA de distinguir "esta unidad
/// serializada es candidata a teléfono" de cualquier otra unidad
/// serializada (radios, laptops, etc.) — el filtro de "Configurar
/// equipo" solo verificaba `Articulo.manejaSerie`, sin acotar por
/// categoría. Esta columna lo resuelve sin convertir "Telefonía" en
/// una clasificación de Inventario: `null` = categoría genérica (el
/// 100% de las categorías existentes hoy), `'telefonia'` = únicamente
/// cuando alguien la marca explícitamente. Puramente aditiva, cero
/// cambio de comportamiento para datos existentes.
Future<void> migrarCategoriaArticuloAplicacionV43(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('categoria_articulo')").get();
    final yaExiste = columnas.any((fila) => fila.data['name'] == 'aplicacion_especializada');
    if (!yaExiste) {
      await m.addColumn(db.categoriaArticulo, db.categoriaArticulo.aplicacionEspecializada);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 43: foreign_key_check reportó '
        '${violacionesFk.length} violación(es) tras la migración. Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración a schemaVersion 43: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
