import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/asignacion_repository.dart';
import '../repositories/inventario_repository.dart';
import '../../data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;

sealed class CrearAsignacionResultado {}

class CrearAsignacionExitoso extends CrearAsignacionResultado {
  CrearAsignacionExitoso(this.asignacion);
  final AsignacionData asignacion;
}

class CrearAsignacionArticuloNoExiste extends CrearAsignacionResultado {}

/// Ni `empleadoId` ni `servicioId` (o ambos) — exactamente uno de los
/// dos, nunca cero ni dos.
class CrearAsignacionDestinoInvalido extends CrearAsignacionResultado {}

class CrearAsignacionVarianteInvalida extends CrearAsignacionResultado {}

class CrearAsignacionUnidadInvalida extends CrearAsignacionResultado {}

class CrearAsignacionUnidadNoDisponible extends CrearAsignacionResultado {}

class CrearAsignacionCantidadInvalida extends CrearAsignacionResultado {}

class CrearAsignacionSobrepasaDisponible extends CrearAsignacionResultado {
  CrearAsignacionSobrepasaDisponible(this.disponible);
  final int disponible;
}

class CrearAsignacionErrorInesperado extends CrearAsignacionResultado {
  CrearAsignacionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Entrega un Artículo/variante/unidad a un Empleado o Servicio (Etapa
/// 7B) — nunca captura libre: la variante/unidad debe existir y, si es
/// serializada, estar `disponible` (protegido también a nivel de BD
/// por `idx_asignacion_unidad_activa`). Para artículos por cantidad,
/// nunca asigna más de lo `Disponible` actual.
class CrearAsignacionUseCase {
  CrearAsignacionUseCase(this._asignacionRepository, this._articuloRepository, this._inventarioRepository);

  final AsignacionRepository _asignacionRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;

  Future<CrearAsignacionResultado> ejecutar({
    required String articuloId,
    String? varianteId,
    String? unidadId,
    required int cantidad,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaEntrega,
    String? condicionEntrega,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return CrearAsignacionArticuloNoExiste();

    final unoSoloDestino = (empleadoId != null) != (servicioId != null);
    if (!unoSoloDestino) return CrearAsignacionDestinoInvalido();

    if (cantidad <= 0) return CrearAsignacionCantidadInvalida();

    if (articulo.manejaSerie) {
      if (unidadId == null || cantidad != 1) return CrearAsignacionUnidadInvalida();
      final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
      if (unidad == null || unidad.articuloId != articuloId) return CrearAsignacionUnidadInvalida();
      if (EstatusArticuloUnidad.values.byName(unidad.estatus) != EstatusArticuloUnidad.disponible) {
        return CrearAsignacionUnidadNoDisponible();
      }
    } else {
      if (unidadId != null) return CrearAsignacionUnidadInvalida();
      if (articulo.manejaVariante != (varianteId != null)) return CrearAsignacionVarianteInvalida();

      final existencia = await _inventarioRepository.calcularExistencia(articuloId: articuloId, varianteId: varianteId);
      if (cantidad > existencia.disponible) return CrearAsignacionSobrepasaDisponible(existencia.disponible);
    }

    try {
      final asignacion = await _asignacionRepository.crear(
        articuloId: articuloId,
        varianteId: varianteId,
        unidadId: unidadId,
        cantidad: cantidad,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaEntrega: fechaEntrega,
        condicionEntrega: condicionEntrega,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return CrearAsignacionExitoso(asignacion);
    } catch (e) {
      return CrearAsignacionErrorInesperado(e.toString());
    }
  }
}
