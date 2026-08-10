import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/categoria_articulo_repository.dart';

sealed class CorregirArticuloResultado {}

class CorregirArticuloExitoso extends CorregirArticuloResultado {
  CorregirArticuloExitoso(this.articulo);
  final ArticuloData articulo;
}

class CorregirArticuloNoExiste extends CorregirArticuloResultado {}

class CorregirArticuloCategoriaNoExiste extends CorregirArticuloResultado {}

class CorregirArticuloCostoInvalido extends CorregirArticuloResultado {}

class CorregirArticuloErrorInesperado extends CorregirArticuloResultado {
  CorregirArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos de un Artículo — nunca `manejaVariante`/
/// `manejaSerie` (ver el doc comment de `CrearArticuloUseCase`).
class CorregirArticuloUseCase {
  CorregirArticuloUseCase(this._articuloRepository, this._categoriaRepository);

  final ArticuloRepository _articuloRepository;
  final CategoriaArticuloRepository _categoriaRepository;

  Future<CorregirArticuloResultado> ejecutar({
    required String articuloId,
    String? categoriaId,
    String? nombre,
    String? descripcion,
    String? unidadMedida,
    int? costoReferencia,
    bool limpiarDescripcion = false,
    bool limpiarCostoReferencia = false,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return CorregirArticuloNoExiste();
    if (categoriaId != null && await _categoriaRepository.obtenerPorId(categoriaId) == null) {
      return CorregirArticuloCategoriaNoExiste();
    }
    if (costoReferencia != null && costoReferencia < 0) return CorregirArticuloCostoInvalido();

    try {
      final actualizado = await _articuloRepository.corregir(
        articuloId: articuloId,
        categoriaId: categoriaId,
        nombre: nombre,
        descripcion: descripcion,
        unidadMedida: unidadMedida,
        costoReferencia: costoReferencia,
        limpiarDescripcion: limpiarDescripcion,
        limpiarCostoReferencia: limpiarCostoReferencia,
      );
      return CorregirArticuloExitoso(actualizado);
    } catch (e) {
      return CorregirArticuloErrorInesperado(e.toString());
    }
  }
}
