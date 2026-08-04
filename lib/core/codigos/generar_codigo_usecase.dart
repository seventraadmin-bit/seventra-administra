import '../error/failure.dart';
import '../error/result.dart';
import 'codigo_secuencia_service.dart';

/// Única fachada pública para obtener un código visible.
///
/// Ningún módulo debe llamar a [CodigoSecuenciaService] directamente —
/// pasan todos por aquí. No conoce reglas particulares de ningún módulo
/// ni de UI: solo valida que el tipo de entidad exista y devuelve el
/// código.
class GenerarCodigoUseCase {
  GenerarCodigoUseCase(this._service);

  final CodigoSecuenciaService _service;

  Future<Result<String>> ejecutar(String entityType) async {
    try {
      final codigo = await _service.siguienteCodigo(entityType);
      return Result.ok(codigo);
    } on StateError catch (e) {
      return Result.failure(ValidationFailure(e.message));
    }
  }
}
