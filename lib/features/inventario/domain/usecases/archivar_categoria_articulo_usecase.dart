import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/categoria_articulo_repository.dart';

sealed class ArchivarCategoriaArticuloResultado {}

class ArchivarCategoriaArticuloExitoso extends ArchivarCategoriaArticuloResultado {
  ArchivarCategoriaArticuloExitoso(this.categoria);
  final CategoriaArticuloData categoria;
}

class ArchivarCategoriaArticuloNoExiste extends ArchivarCategoriaArticuloResultado {}

class ArchivarCategoriaArticuloErrorInesperado extends ArchivarCategoriaArticuloResultado {
  ArchivarCategoriaArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archiva una categoría de artículo — nunca la borra físicamente
/// (`cicloVidaRegistro = archivado`), mismo criterio que cualquier
/// otro catálogo del proyecto.
class ArchivarCategoriaArticuloUseCase {
  ArchivarCategoriaArticuloUseCase(this._repository);

  final CategoriaArticuloRepository _repository;

  Future<ArchivarCategoriaArticuloResultado> ejecutar(String categoriaId) async {
    final categoria = await _repository.obtenerPorId(categoriaId);
    if (categoria == null) {
      return ArchivarCategoriaArticuloNoExiste();
    }

    try {
      final actualizada = await _repository.archivar(categoriaId);
      return ArchivarCategoriaArticuloExitoso(actualizada);
    } catch (e) {
      return ArchivarCategoriaArticuloErrorInesperado(e.toString());
    }
  }
}
