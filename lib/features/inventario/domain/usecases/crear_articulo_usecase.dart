import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/categoria_articulo_repository.dart';

sealed class CrearArticuloResultado {}

class CrearArticuloExitoso extends CrearArticuloResultado {
  CrearArticuloExitoso(this.articulo);
  final ArticuloData articulo;
}

class CrearArticuloNombreRequerido extends CrearArticuloResultado {}

class CrearArticuloCategoriaNoExiste extends CrearArticuloResultado {}

class CrearArticuloCostoInvalido extends CrearArticuloResultado {}

class CrearArticuloErrorInesperado extends CrearArticuloResultado {
  CrearArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta un Artículo en el catálogo (Etapa 7A). `manejaVariante`/
/// `manejaSerie` quedan fijas desde aquí — nunca se cambian después
/// (ver `CorregirArticuloUseCase`), para no dejar existencias/unidades
/// ya capturadas bajo una estructura distinta a la que tenían al
/// crearse.
class CrearArticuloUseCase {
  CrearArticuloUseCase(this._articuloRepository, this._categoriaRepository, this._generarCodigo);

  final ArticuloRepository _articuloRepository;
  final CategoriaArticuloRepository _categoriaRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<CrearArticuloResultado> ejecutar({
    required String categoriaId,
    required String nombre,
    String? descripcion,
    String? unidadMedida,
    bool manejaVariante = false,
    bool manejaSerie = false,
    int? costoReferencia,
  }) async {
    if (nombre.trim().isEmpty) return CrearArticuloNombreRequerido();
    if (await _categoriaRepository.obtenerPorId(categoriaId) == null) return CrearArticuloCategoriaNoExiste();
    if (costoReferencia != null && costoReferencia < 0) return CrearArticuloCostoInvalido();

    try {
      final folioResultado = await _generarCodigo.ejecutar('articulo');
      final String folio;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return CrearArticuloErrorInesperado(f.message);
      }

      final articulo = await _articuloRepository.crear(
        folio: folio,
        categoriaId: categoriaId,
        nombre: nombre.trim(),
        descripcion: descripcion?.trim().isEmpty ?? true ? null : descripcion!.trim(),
        unidadMedida: unidadMedida?.trim().isEmpty ?? true ? null : unidadMedida!.trim(),
        manejaVariante: manejaVariante,
        manejaSerie: manejaSerie,
        costoReferencia: costoReferencia,
      );
      return CrearArticuloExitoso(articulo);
    } catch (e) {
      return CrearArticuloErrorInesperado(e.toString());
    }
  }
}
