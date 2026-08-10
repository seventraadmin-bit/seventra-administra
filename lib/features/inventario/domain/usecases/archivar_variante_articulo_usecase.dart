import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';

sealed class ArchivarVarianteArticuloResultado {}

class ArchivarVarianteArticuloExitoso extends ArchivarVarianteArticuloResultado {
  ArchivarVarianteArticuloExitoso(this.variante);
  final ArticuloVarianteData variante;
}

class ArchivarVarianteArticuloErrorInesperado extends ArchivarVarianteArticuloResultado {
  ArchivarVarianteArticuloErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archiva una talla/variante — nunca la borra físicamente. Su
/// historial de movimientos/existencia ya capturado sigue intacto.
class ArchivarVarianteArticuloUseCase {
  ArchivarVarianteArticuloUseCase(this._repository);

  final ArticuloRepository _repository;

  Future<ArchivarVarianteArticuloResultado> ejecutar(String varianteId) async {
    try {
      final variante = await _repository.archivarVariante(varianteId);
      return ArchivarVarianteArticuloExitoso(variante);
    } catch (e) {
      return ArchivarVarianteArticuloErrorInesperado(e.toString());
    }
  }
}
