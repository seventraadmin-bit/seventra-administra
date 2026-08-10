import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';

sealed class ArchivarArticuloResultado {}

class ArchivarArticuloExitoso extends ArchivarArticuloResultado {
  ArchivarArticuloExitoso(this.articulo);
  final ArticuloData articulo;
}

class ArchivarArticuloNoExiste extends ArchivarArticuloResultado {}

class ArchivarArticuloErrorInesperado extends ArchivarArticuloResultado {
  ArchivarArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archiva un Artículo — nunca lo borra físicamente. No valida
/// existencia en cero a propósito: un Artículo archivado simplemente
/// deja de ofrecerse para nuevas entradas/asignaciones, pero su
/// historial y sus unidades ya creadas siguen intactas y consultables.
class ArchivarArticuloUseCase {
  ArchivarArticuloUseCase(this._repository);

  final ArticuloRepository _repository;

  Future<ArchivarArticuloResultado> ejecutar(String articuloId) async {
    final articulo = await _repository.obtenerPorId(articuloId);
    if (articulo == null) return ArchivarArticuloNoExiste();

    try {
      final actualizado = await _repository.archivar(articuloId);
      return ArchivarArticuloExitoso(actualizado);
    } catch (e) {
      return ArchivarArticuloErrorInesperado(e.toString());
    }
  }
}
