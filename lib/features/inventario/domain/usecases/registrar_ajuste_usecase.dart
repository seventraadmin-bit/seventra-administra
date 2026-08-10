import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

sealed class RegistrarAjusteResultado {}

class RegistrarAjusteExitoso extends RegistrarAjusteResultado {
  RegistrarAjusteExitoso(this.movimiento);
  final MovimientoInventarioData movimiento;
}

class RegistrarAjusteArticuloNoExiste extends RegistrarAjusteResultado {}

class RegistrarAjusteArticuloManejaSerie extends RegistrarAjusteResultado {}

class RegistrarAjusteVarianteInvalida extends RegistrarAjusteResultado {}

class RegistrarAjusteCantidadInvalida extends RegistrarAjusteResultado {}

class RegistrarAjusteSobrepasaDisponible extends RegistrarAjusteResultado {
  RegistrarAjusteSobrepasaDisponible(this.disponible);
  final int disponible;
}

class RegistrarAjusteObservacionesRequeridas extends RegistrarAjusteResultado {}

class RegistrarAjusteErrorInesperado extends RegistrarAjusteResultado {
  RegistrarAjusteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrección de conteo físico/merma de un Artículo por cantidad
/// (Etapa 7A) — mismo efecto en el bucket Disponible que
/// `entrada`/`baja`, pero se reporta por separado (ver el doc comment
/// del enum `TipoMovimientoInventario`). Siempre requiere
/// `observaciones`.
class RegistrarAjusteUseCase {
  RegistrarAjusteUseCase(this._inventarioRepository, this._articuloRepository);

  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;

  Future<RegistrarAjusteResultado> ejecutar({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required bool esEntrada,
    required String observaciones,
    String? actor,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return RegistrarAjusteArticuloNoExiste();
    if (articulo.manejaSerie) return RegistrarAjusteArticuloManejaSerie();
    if (articulo.manejaVariante != (varianteId != null)) return RegistrarAjusteVarianteInvalida();
    if (cantidad <= 0) return RegistrarAjusteCantidadInvalida();
    if (observaciones.trim().isEmpty) return RegistrarAjusteObservacionesRequeridas();

    if (!esEntrada) {
      final existencia = await _inventarioRepository.calcularExistencia(articuloId: articuloId, varianteId: varianteId);
      if (cantidad > existencia.disponible) return RegistrarAjusteSobrepasaDisponible(existencia.disponible);
    }

    try {
      final movimiento = await _inventarioRepository.registrarAjuste(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        esEntrada: esEntrada,
        observaciones: observaciones.trim(),
        actor: actor,
      );
      return RegistrarAjusteExitoso(movimiento);
    } catch (e) {
      return RegistrarAjusteErrorInesperado(e.toString());
    }
  }
}
