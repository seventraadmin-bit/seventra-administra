import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;

import '../repositories/categoria_articulo_repository.dart';

sealed class ActualizarCategoriaArticuloResultado {}

class ActualizarCategoriaArticuloExitoso extends ActualizarCategoriaArticuloResultado {
  ActualizarCategoriaArticuloExitoso(this.categoria);
  final CategoriaArticuloData categoria;
}

class ActualizarCategoriaArticuloNoExiste extends ActualizarCategoriaArticuloResultado {}

class ActualizarCategoriaArticuloNombreRequerido extends ActualizarCategoriaArticuloResultado {}

class ActualizarCategoriaArticuloErrorInesperado extends ActualizarCategoriaArticuloResultado {
  ActualizarCategoriaArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Edita nombre y/o clasificación de aplicación especializada de una
/// categoría existente (Etapa 9D, ajuste posterior) — el catálogo de
/// Categorías nació solo con alta/archivado (7A); este caso de uso es
/// la única forma de marcar una categoría ya existente como
/// `telefonia` sin tener que recrearla.
class ActualizarCategoriaArticuloUseCase {
  ActualizarCategoriaArticuloUseCase(this._repository);

  final CategoriaArticuloRepository _repository;

  Future<ActualizarCategoriaArticuloResultado> ejecutar({
    required String categoriaId,
    required String nombre,
    AplicacionEspecializadaCategoriaArticulo? aplicacionEspecializada,
    bool limpiarAplicacionEspecializada = false,
  }) async {
    if (nombre.trim().isEmpty) {
      return ActualizarCategoriaArticuloNombreRequerido();
    }

    final categoria = await _repository.obtenerPorId(categoriaId);
    if (categoria == null) {
      return ActualizarCategoriaArticuloNoExiste();
    }

    try {
      final actualizada = await _repository.actualizar(
        id: categoriaId,
        nombre: nombre.trim(),
        aplicacionEspecializada: aplicacionEspecializada,
        limpiarAplicacionEspecializada: limpiarAplicacionEspecializada,
      );
      return ActualizarCategoriaArticuloExitoso(actualizada);
    } catch (e) {
      return ActualizarCategoriaArticuloErrorInesperado(e.toString());
    }
  }
}
