import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

sealed class RegistrarBajaResultado {}

class RegistrarBajaExitoso extends RegistrarBajaResultado {
  RegistrarBajaExitoso(this.movimiento);
  final MovimientoInventarioData movimiento;
}

class RegistrarBajaArticuloNoExiste extends RegistrarBajaResultado {}

class RegistrarBajaArticuloManejaSerie extends RegistrarBajaResultado {}

class RegistrarBajaVarianteInvalida extends RegistrarBajaResultado {}

class RegistrarBajaCantidadInvalida extends RegistrarBajaResultado {}

/// `cantidad` excede el Disponible actual — nunca se da de baja más
/// de lo que existe.
class RegistrarBajaSobrepasaDisponible extends RegistrarBajaResultado {
  RegistrarBajaSobrepasaDisponible(this.disponible);
  final int disponible;
}

class RegistrarBajaObservacionesRequeridas extends RegistrarBajaResultado {}

class RegistrarBajaErrorInesperado extends RegistrarBajaResultado {
  RegistrarBajaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de baja definitivamente cantidad de un Artículo (Etapa 7A) —
/// única operación que reduce el Total real (ver el doc comment de
/// `MovimientoInventario`). Siempre requiere `observaciones` (por qué
/// se dio de baja) — nunca queda como un número suelto sin
/// justificación.
class RegistrarBajaUseCase {
  RegistrarBajaUseCase(this._inventarioRepository, this._articuloRepository);

  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;

  Future<RegistrarBajaResultado> ejecutar({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required String observaciones,
    String? actorUsuarioId,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return RegistrarBajaArticuloNoExiste();
    if (articulo.manejaSerie) return RegistrarBajaArticuloManejaSerie();
    if (articulo.manejaVariante != (varianteId != null)) return RegistrarBajaVarianteInvalida();
    if (cantidad <= 0) return RegistrarBajaCantidadInvalida();
    if (observaciones.trim().isEmpty) return RegistrarBajaObservacionesRequeridas();

    final existencia = await _inventarioRepository.calcularExistencia(articuloId: articuloId, varianteId: varianteId);
    if (cantidad > existencia.disponible) return RegistrarBajaSobrepasaDisponible(existencia.disponible);

    try {
      final movimiento = await _inventarioRepository.registrarBaja(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        observaciones: observaciones.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarBajaExitoso(movimiento);
    } catch (e) {
      return RegistrarBajaErrorInesperado(e.toString());
    }
  }
}
