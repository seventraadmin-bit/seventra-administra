import '../error/failure.dart';
import '../error/result.dart';
import 'codigo_secuencia_service.dart';

/// Única fachada pública para obtener un número entero consecutivo
/// crudo (Etapa 6A) — mismo criterio que [GenerarCodigoUseCase], pero
/// para identificadores visibles que no llevan prefijo ni relleno de
/// ceros (ej. `Empleado.numeroEmpleado`: `1`, `2`, `3`...). Ningún
/// módulo debe llamar a [CodigoSecuenciaService] directamente.
class GenerarNumeroUseCase {
  GenerarNumeroUseCase(this._service);

  final CodigoSecuenciaService _service;

  Future<Result<int>> ejecutar(String entityType) async {
    try {
      final numero = await _service.siguienteNumero(entityType);
      return Result.ok(numero);
    } on StateError catch (e) {
      return Result.failure(ValidationFailure(e.message));
    }
  }
}
