import '../repositories/area_repository.dart';
import 'guardar_area_resultado.dart';

class ActualizarAreaUseCase {
  ActualizarAreaUseCase(this._repository);

  final AreaRepository _repository;

  Future<GuardarAreaResultado> ejecutar({required String id, required String nombre, String? descripcion}) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) {
      return GuardarAreaNombreRequerido();
    }

    try {
      final descripcionLimpia = descripcion?.trim();
      final area = await _repository.actualizar(
        id: id,
        nombre: nombreLimpio,
        descripcion: (descripcionLimpia == null || descripcionLimpia.isEmpty) ? null : descripcionLimpia,
      );
      return GuardarAreaExitoso(area);
    } catch (e) {
      return GuardarAreaErrorInesperado(e.toString());
    }
  }
}
