import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/categoria_financiera_repository.dart';

sealed class ArchivarCategoriaFinancieraResultado {}

class ArchivarCategoriaFinancieraExitoso extends ArchivarCategoriaFinancieraResultado {
  ArchivarCategoriaFinancieraExitoso(this.categoria);
  final CategoriaFinancieraData categoria;
}

class ArchivarCategoriaFinancieraNoExiste extends ArchivarCategoriaFinancieraResultado {}

class ArchivarCategoriaFinancieraErrorInesperado extends ArchivarCategoriaFinancieraResultado {
  ArchivarCategoriaFinancieraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archiva una categoría financiera — nunca la borra físicamente
/// (`cicloVidaRegistro = archivado`), mismo criterio que cualquier
/// otro catálogo del proyecto.
class ArchivarCategoriaFinancieraUseCase {
  ArchivarCategoriaFinancieraUseCase(this._repository);

  final CategoriaFinancieraRepository _repository;

  Future<ArchivarCategoriaFinancieraResultado> ejecutar(String categoriaId) async {
    final categoria = await _repository.obtenerPorId(categoriaId);
    if (categoria == null) {
      return ArchivarCategoriaFinancieraNoExiste();
    }

    try {
      final actualizada = await _repository.archivar(categoriaId);
      return ArchivarCategoriaFinancieraExitoso(actualizada);
    } catch (e) {
      return ArchivarCategoriaFinancieraErrorInesperado(e.toString());
    }
  }
}
