import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/categoria_articulo_repository.dart';

sealed class CrearCategoriaArticuloResultado {}

class CrearCategoriaArticuloExitoso extends CrearCategoriaArticuloResultado {
  CrearCategoriaArticuloExitoso(this.categoria);
  final CategoriaArticuloData categoria;
}

class CrearCategoriaArticuloNombreRequerido extends CrearCategoriaArticuloResultado {}

class CrearCategoriaArticuloErrorInesperado extends CrearCategoriaArticuloResultado {
  CrearCategoriaArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una categoría de artículo (Etapa 7A) — el catálogo nace
/// vacío, RISEG lo captura desde una pantalla propia.
class CrearCategoriaArticuloUseCase {
  CrearCategoriaArticuloUseCase(this._repository);

  final CategoriaArticuloRepository _repository;

  Future<CrearCategoriaArticuloResultado> ejecutar({required String nombre}) async {
    if (nombre.trim().isEmpty) {
      return CrearCategoriaArticuloNombreRequerido();
    }

    try {
      final categoria = await _repository.crear(nombre: nombre.trim());
      return CrearCategoriaArticuloExitoso(categoria);
    } catch (e) {
      return CrearCategoriaArticuloErrorInesperado(e.toString());
    }
  }
}
