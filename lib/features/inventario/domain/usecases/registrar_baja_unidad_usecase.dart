import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../repositories/inventario_repository.dart';

sealed class RegistrarBajaUnidadResultado {}

class RegistrarBajaUnidadExitoso extends RegistrarBajaUnidadResultado {
  RegistrarBajaUnidadExitoso(this.unidad);
  final ArticuloUnidadData unidad;
}

class RegistrarBajaUnidadNoExiste extends RegistrarBajaUnidadResultado {}

/// La unidad ya está dada de baja — nunca se vuelve a dar de baja.
class RegistrarBajaUnidadYaDeBaja extends RegistrarBajaUnidadResultado {}

class RegistrarBajaUnidadObservacionesRequeridas extends RegistrarBajaUnidadResultado {}

class RegistrarBajaUnidadErrorInesperado extends RegistrarBajaUnidadResultado {
  RegistrarBajaUnidadErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de baja definitivamente una unidad serializada (Etapa 7A) —
/// marca su `estatus` en `baja` y registra el movimiento
/// correspondiente. Siempre requiere `observaciones`.
class RegistrarBajaUnidadUseCase {
  RegistrarBajaUnidadUseCase(this._repository);

  final InventarioRepository _repository;

  Future<RegistrarBajaUnidadResultado> ejecutar({
    required String unidadId,
    required String observaciones,
    String? actorUsuarioId,
  }) async {
    final unidad = await _repository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return RegistrarBajaUnidadNoExiste();
    if (EstatusArticuloUnidad.values.byName(unidad.estatus) == EstatusArticuloUnidad.baja) {
      return RegistrarBajaUnidadYaDeBaja();
    }
    if (observaciones.trim().isEmpty) return RegistrarBajaUnidadObservacionesRequeridas();

    try {
      final actualizada = await _repository.registrarBajaUnidad(
        unidadId: unidadId,
        observaciones: observaciones.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarBajaUnidadExitoso(actualizada);
    } catch (e) {
      return RegistrarBajaUnidadErrorInesperado(e.toString());
    }
  }
}
