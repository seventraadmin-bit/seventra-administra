import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/articulo_unidad_table.dart';
import '../repositories/inventario_repository.dart';

/// Cómo termina la estancia de una unidad en un destino intermedio.
///
/// Deliberadamente pequeño: lo único que el sistema necesita saber es si
/// el bien ya puede asignarse otra vez o no. No es un módulo de taller —
/// no hay órdenes de servicio, ni proveedores, ni costos de reparación.
enum DesenlaceRetornoUnidad {
  /// Volvió limpia / reparada: al anaquel.
  disponible(estatusFinal: EstatusArticuloUnidad.disponible),

  /// Sigue dañada tras el intento de reparación — queda fuera de
  /// existencias con el veredicto de siempre.
  danado(estatusFinal: EstatusArticuloUnidad.danado),

  /// Irreparable: pasa a esperar la baja física, que ejecuta
  /// `RegistrarBajaUnidadUseCase` — el ciclo oficial que ya existe.
  irreparable(estatusFinal: EstatusArticuloUnidad.pendienteDesecho);

  const DesenlaceRetornoUnidad({required this.estatusFinal});

  final EstatusArticuloUnidad estatusFinal;
}

sealed class RegistrarRetornoUnidadResultado {}

class RegistrarRetornoUnidadExitoso extends RegistrarRetornoUnidadResultado {
  RegistrarRetornoUnidadExitoso(this.unidad);
  final ArticuloUnidadData unidad;
}

class RegistrarRetornoUnidadNoExiste extends RegistrarRetornoUnidadResultado {}

/// La unidad no está en lavandería, reparación ni pendiente de desecho:
/// no hay nada de qué regresarla.
class RegistrarRetornoUnidadNoEstaEnProceso extends RegistrarRetornoUnidadResultado {
  RegistrarRetornoUnidadNoEstaEnProceso(this.estatusActual);
  final String estatusActual;
}

class RegistrarRetornoUnidadErrorInesperado extends RegistrarRetornoUnidadResultado {
  RegistrarRetornoUnidadErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Regresa una unidad de un destino intermedio — "Regresó de
/// lavandería", "Reparación terminada".
///
/// Es la contraparte obligatoria de haber dejado de mentir: si una
/// prenda enviada a la tintorería ya no aparece disponible, tiene que
/// existir la operación explícita que la devuelve al anaquel cuando
/// vuelve limpia. Sin ella, el bien quedaría atrapado.
///
/// Registra fecha, actor y condición final, y mueve la unidad al estado
/// que corresponda. **No toca dinero**: el costo de la limpieza o de la
/// reparación es una obligación aparte (`DescuentoProgramadoEmpleado`),
/// y que el trabajador la haya pagado o no NO determina si la camisa
/// regresó físicamente.
class RegistrarRetornoUnidadUseCase {
  RegistrarRetornoUnidadUseCase(this._repository);

  final InventarioRepository _repository;

  Future<RegistrarRetornoUnidadResultado> ejecutar({
    required String unidadId,
    required DesenlaceRetornoUnidad desenlace,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final unidad = await _repository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return RegistrarRetornoUnidadNoExiste();

    final actual = EstatusArticuloUnidad.values.byName(unidad.estatus);
    if (!actual.enDestinoIntermedio) return RegistrarRetornoUnidadNoEstaEnProceso(unidad.estatus);

    try {
      final actualizada = await _repository.actualizarEstatusUnidad(
        unidadId: unidadId,
        estatus: desenlace.estatusFinal.name,
        fecha: fecha,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarRetornoUnidadExitoso(actualizada);
    } catch (e) {
      return RegistrarRetornoUnidadErrorInesperado(e.toString());
    }
  }
}
