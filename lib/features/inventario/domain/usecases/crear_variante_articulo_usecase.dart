import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';

sealed class CrearVarianteArticuloResultado {}

class CrearVarianteArticuloExitoso extends CrearVarianteArticuloResultado {
  CrearVarianteArticuloExitoso(this.variante);
  final ArticuloVarianteData variante;
}

class CrearVarianteArticuloArticuloNoExiste extends CrearVarianteArticuloResultado {}

/// El Artículo referenciado tiene `manejaVariante == false` — nunca se
/// crea una talla/variante para un Artículo que no las maneja.
class CrearVarianteArticuloArticuloNoManejaVariante extends CrearVarianteArticuloResultado {}

class CrearVarianteArticuloValorRequerido extends CrearVarianteArticuloResultado {}

class CrearVarianteArticuloValorDuplicado extends CrearVarianteArticuloResultado {}

class CrearVarianteArticuloErrorInesperado extends CrearVarianteArticuloResultado {
  CrearVarianteArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta una talla/variante de un Artículo (Etapa 7A) — "artículo
/// + variante" en vez de un producto nuevo por talla (ver el doc
/// comment de `ArticuloVariante`).
class CrearVarianteArticuloUseCase {
  CrearVarianteArticuloUseCase(this._repository);

  final ArticuloRepository _repository;

  Future<CrearVarianteArticuloResultado> ejecutar({required String articuloId, required String valor}) async {
    final articulo = await _repository.obtenerPorId(articuloId);
    if (articulo == null) return CrearVarianteArticuloArticuloNoExiste();
    if (!articulo.manejaVariante) return CrearVarianteArticuloArticuloNoManejaVariante();
    if (valor.trim().isEmpty) return CrearVarianteArticuloValorRequerido();

    final existentes = await _repository.listarVariantes(articuloId);
    if (existentes.any((v) => v.valor.toLowerCase() == valor.trim().toLowerCase())) {
      return CrearVarianteArticuloValorDuplicado();
    }

    try {
      final variante = await _repository.crearVariante(articuloId: articuloId, valor: valor.trim());
      return CrearVarianteArticuloExitoso(variante);
    } catch (e) {
      return CrearVarianteArticuloErrorInesperado(e.toString());
    }
  }
}
