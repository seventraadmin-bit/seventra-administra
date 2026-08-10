import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/asignacion_repository.dart';
import '../repositories/inventario_repository.dart';
import '../../data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../../data/tables/asignacion_table.dart' show EstatusAsignacion, MotivoCierreAsignacion;

sealed class ReemplazarAsignacionResultado {}

class ReemplazarAsignacionExitoso extends ReemplazarAsignacionResultado {
  ReemplazarAsignacionExitoso(this.nuevaAsignacion);
  final AsignacionData nuevaAsignacion;
}

class ReemplazarAsignacionNoExiste extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionYaCerrada extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionObservacionesRequeridas extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionAtribucionRequerida extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionDescuentoInvalido extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoArticuloNoExiste extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoDestinoInvalido extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoVarianteInvalida extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoUnidadInvalida extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoUnidadNoDisponible extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoCantidadInvalida extends ReemplazarAsignacionResultado {}

class ReemplazarAsignacionReemplazoSobrepasaDisponible extends ReemplazarAsignacionResultado {
  ReemplazarAsignacionReemplazoSobrepasaDisponible(this.disponible);
  final int disponible;
}

class ReemplazarAsignacionErrorInesperado extends ReemplazarAsignacionResultado {
  ReemplazarAsignacionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cierra una `Asignacion` vigente y crea de inmediato la Asignación
/// de reemplazo, seleccionada del inventario disponible (nunca texto
/// libre) — compone las mismas validaciones de
/// `CerrarAsignacionUseCase`/`CrearAsignacionUseCase`, una sola
/// transacción vía `AsignacionRepository.reemplazar`.
class ReemplazarAsignacionUseCase {
  ReemplazarAsignacionUseCase(this._asignacionRepository, this._articuloRepository, this._inventarioRepository);

  final AsignacionRepository _asignacionRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;

  Future<ReemplazarAsignacionResultado> ejecutar({
    required String asignacionId,
    required MotivoCierreAsignacion motivo,
    required DateTime fechaCierre,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    required String articuloIdReemplazo,
    String? varianteIdReemplazo,
    String? unidadIdReemplazo,
    required int cantidadReemplazo,
    String? condicionEntregaReemplazo,
    String? observacionesReemplazo,
    String? actor,
  }) async {
    final asignacion = await _asignacionRepository.obtenerPorId(asignacionId);
    if (asignacion == null) return ReemplazarAsignacionNoExiste();
    if (EstatusAsignacion.values.byName(asignacion.estatus) != EstatusAsignacion.activa) {
      return ReemplazarAsignacionYaCerrada();
    }

    final observaciones = observacionesCierre?.trim();
    if (motivo.requiereObservaciones && (observaciones == null || observaciones.isEmpty)) {
      return ReemplazarAsignacionObservacionesRequeridas();
    }
    if (motivo.disparaDanoPerdida && atribuibleAlEmpleado == null) {
      return ReemplazarAsignacionAtribucionRequerida();
    }
    if (generaDescuento) {
      if (!motivo.disparaDanoPerdida) return ReemplazarAsignacionDescuentoInvalido();
      if (importeDescuento == null || importeDescuento <= 0) return ReemplazarAsignacionDescuentoInvalido();
      if (empleadoResponsableDescuentoId == null || empleadoResponsableDescuentoId.isEmpty) {
        return ReemplazarAsignacionDescuentoInvalido();
      }
    }

    final articuloReemplazo = await _articuloRepository.obtenerPorId(articuloIdReemplazo);
    if (articuloReemplazo == null) return ReemplazarAsignacionReemplazoArticuloNoExiste();

    if (asignacion.empleadoId == null && asignacion.servicioId == null) {
      return ReemplazarAsignacionReemplazoDestinoInvalido();
    }

    if (cantidadReemplazo <= 0) return ReemplazarAsignacionReemplazoCantidadInvalida();

    if (articuloReemplazo.manejaSerie) {
      if (unidadIdReemplazo == null || cantidadReemplazo != 1) return ReemplazarAsignacionReemplazoUnidadInvalida();
      final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadIdReemplazo);
      if (unidad == null || unidad.articuloId != articuloIdReemplazo) {
        return ReemplazarAsignacionReemplazoUnidadInvalida();
      }
      if (EstatusArticuloUnidad.values.byName(unidad.estatus) != EstatusArticuloUnidad.disponible) {
        return ReemplazarAsignacionReemplazoUnidadNoDisponible();
      }
    } else {
      if (unidadIdReemplazo != null) return ReemplazarAsignacionReemplazoUnidadInvalida();
      if (articuloReemplazo.manejaVariante != (varianteIdReemplazo != null)) {
        return ReemplazarAsignacionReemplazoVarianteInvalida();
      }
      final existencia = await _inventarioRepository.calcularExistencia(
        articuloId: articuloIdReemplazo,
        varianteId: varianteIdReemplazo,
      );
      if (cantidadReemplazo > existencia.disponible) {
        return ReemplazarAsignacionReemplazoSobrepasaDisponible(existencia.disponible);
      }
    }

    try {
      final nueva = await _asignacionRepository.reemplazar(
        asignacionId: asignacionId,
        motivo: motivo.name,
        fechaCierre: fechaCierre,
        observacionesCierre: observaciones,
        atribuibleAlEmpleado: motivo.disparaDanoPerdida ? atribuibleAlEmpleado : null,
        generaDescuento: generaDescuento,
        importeDescuento: generaDescuento ? importeDescuento : null,
        empleadoResponsableDescuentoId: generaDescuento ? empleadoResponsableDescuentoId : null,
        articuloIdReemplazo: articuloIdReemplazo,
        varianteIdReemplazo: varianteIdReemplazo,
        unidadIdReemplazo: unidadIdReemplazo,
        cantidadReemplazo: cantidadReemplazo,
        condicionEntregaReemplazo: condicionEntregaReemplazo,
        observacionesReemplazo: observacionesReemplazo,
        actor: actor,
      );
      return ReemplazarAsignacionExitoso(nueva);
    } catch (e) {
      return ReemplazarAsignacionErrorInesperado(e.toString());
    }
  }
}
