import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../coherencia_linea_equipo.dart';
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';
import 'obtener_coherencia_linea_equipo_usecase.dart';

sealed class AsociarEquipoLineaTelefonicaResultado {}

class AsociarEquipoLineaTelefonicaExitoso extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaExitoso(this.equipo);
  final LineaTelefonicaEquipoData equipo;
}

class AsociarEquipoLineaTelefonicaLineaNoExiste extends AsociarEquipoLineaTelefonicaResultado {}

class AsociarEquipoLineaTelefonicaLineaDeBaja extends AsociarEquipoLineaTelefonicaResultado {}

/// La línea ya tiene un equipo vigente — usa
/// `CambiarEquipoLineaTelefonicaUseCase`.
class AsociarEquipoLineaTelefonicaYaTieneEquipo extends AsociarEquipoLineaTelefonicaResultado {}

class AsociarEquipoLineaTelefonicaUnidadNoExiste extends AsociarEquipoLineaTelefonicaResultado {}

/// La unidad seleccionada no tiene una fila `ArticuloUnidadTelefono` —
/// no es un teléfono (punto 4 de Marlon: "solo deben ser seleccionables
/// unidades que realmente sean teléfono").
class AsociarEquipoLineaTelefonicaUnidadNoEsTelefono extends AsociarEquipoLineaTelefonicaResultado {}

/// La unidad no está ni disponible ni en custodia de alguien: está de
/// baja, perdida, dañada o en un destino intermedio. Un aparato así no
/// puede traer una SIM.
class AsociarEquipoLineaTelefonicaUnidadNoDisponible extends AsociarEquipoLineaTelefonicaResultado {}

/// Un teléfono trae UNA SIM a la vez: esta unidad ya está asociada a
/// otra línea vigente. El selector ya las excluye, pero la regla vive
/// aquí — que la UI lo impida no basta.
class AsociarEquipoLineaTelefonicaUnidadYaTraeOtraLinea extends AsociarEquipoLineaTelefonicaResultado {}

/// §1A — el aparato está declarado pendiente de recuperación de alguien
/// que causó baja. No es un dato roto, pero tampoco un teléfono
/// disponible para traer una SIM: alinear la línea con esa custodia
/// sería asignársela a un ex-empleado.
class AsociarEquipoLineaTelefonicaEquipoPendienteRecuperacion extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaEquipoPendienteRecuperacion(this.custodia);
  final DestinoTelefonia custodia;
}

/// §7 — el equipo está bajo custodia de alguien y la línea no tiene
/// asignación. Asociarlos exige decidir explícitamente que la línea se
/// alinee con esa custodia: no se hace en silencio porque crea una
/// asignación de línea.
class AsociarEquipoLineaTelefonicaRequiereAlinearLinea extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaRequiereAlinearLinea(this.custodia);

  /// A quién tiene el aparato Inventario ahora mismo.
  final DestinoTelefonia custodia;
}

/// §8 — la línea está asignada y el aparato no tiene custodia en
/// Inventario. Asociar un teléfono NO es entregarlo: primero hay que
/// asignarlo en Inventario, que es quien manda sobre la custodia.
class AsociarEquipoLineaTelefonicaEquipoSinCustodia extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaEquipoSinCustodia(this.destinoLinea);
  final DestinoTelefonia destinoLinea;
}

/// §10 — los dos tienen destino y no es el mismo.
class AsociarEquipoLineaTelefonicaDestinosDistintos extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaDestinosDistintos(this.destinoLinea, this.custodia);
  final DestinoTelefonia destinoLinea;
  final DestinoTelefonia custodia;
}

class AsociarEquipoLineaTelefonicaErrorInesperado extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asocia un teléfono físico de Inventario a una línea sin equipo
/// (Etapa 9B).
///
/// **Nunca mueve la custodia** (Rebanada 2). Lo único que puede tocar
/// fuera de la asociación es la asignación de la LÍNEA, y sólo para
/// alinearla con la custodia que el aparato ya tiene, previa decisión
/// explícita de quien opera.
class AsociarEquipoLineaTelefonicaUseCase {
  AsociarEquipoLineaTelefonicaUseCase(
    this._lineaRepository,
    this._equipoRepository,
    this._inventarioRepository,
    AsignacionLineaTelefonicaRepository asignacionRepository,
  ) : _coherencia = ObtenerCoherenciaLineaEquipoUseCase(_equipoRepository, asignacionRepository);

  final LineaTelefonicaRepository _lineaRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;
  final InventarioRepository _inventarioRepository;
  final ObtenerCoherenciaLineaEquipoUseCase _coherencia;

  Future<AsociarEquipoLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    bool alinearLineaConCustodia = false,
    String? actorUsuarioId,
  }) async {
    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return AsociarEquipoLineaTelefonicaLineaNoExiste();
    if (linea.estatus == 'baja') return AsociarEquipoLineaTelefonicaLineaDeBaja();

    final equipoVigente = await _equipoRepository.obtenerActualPorLinea(lineaTelefonicaId);
    if (equipoVigente != null) return AsociarEquipoLineaTelefonicaYaTieneEquipo();

    final telefono = await _inventarioRepository.obtenerTelefono(unidadId);
    if (telefono == null) return AsociarEquipoLineaTelefonicaUnidadNoEsTelefono();

    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return AsociarEquipoLineaTelefonicaUnidadNoExiste();

    // `asignado` ahora también vale: es justamente el orden correcto —
    // Inventario entrega el aparato y después se le asocia la SIM.
    final estatus = EstatusArticuloUnidad.values.byName(unidad.estatus);
    if (estatus != EstatusArticuloUnidad.disponible && estatus != EstatusArticuloUnidad.asignado) {
      return AsociarEquipoLineaTelefonicaUnidadNoDisponible();
    }

    if (await _equipoRepository.obtenerActualPorUnidad(unidadId) != null) {
      return AsociarEquipoLineaTelefonicaUnidadYaTraeOtraLinea();
    }

    final destinoLinea = (await _coherencia.ejecutar(lineaTelefonicaId)).destinoLinea;
    final custodiaInventario = await _equipoRepository.obtenerCustodiaInventarioActual(unidadId);
    final custodia = destinoDeCustodia(custodiaInventario);
    final resultante = evaluarCoherenciaLineaEquipo(
      unidadId: unidadId,
      destinoLinea: destinoLinea,
      destinoEquipo: custodia,
      // Sin esto, un aparato pendiente de recuperación se leería como
      // una inconsistencia cualquiera y se le alinearía la línea.
      pendienteRecuperacionDesde: custodiaInventario?.pendienteRecuperacionDesde,
    );

    switch (resultante.estado) {
      case EstadoCoherenciaLineaEquipo.equipoSinCustodia:
        return AsociarEquipoLineaTelefonicaEquipoSinCustodia(destinoLinea!);
      case EstadoCoherenciaLineaEquipo.destinosDistintos:
        return AsociarEquipoLineaTelefonicaDestinosDistintos(destinoLinea!, custodia!);
      case EstadoCoherenciaLineaEquipo.equipoPendienteRecuperacion:
        return AsociarEquipoLineaTelefonicaEquipoPendienteRecuperacion(custodia!);
      case EstadoCoherenciaLineaEquipo.lineaSinAsignacion:
        if (!alinearLineaConCustodia) {
          return AsociarEquipoLineaTelefonicaRequiereAlinearLinea(custodia!);
        }
      case EstadoCoherenciaLineaEquipo.coherente:
      case EstadoCoherenciaLineaEquipo.sinEquipo:
        break;
    }

    final alinear = resultante.estado == EstadoCoherenciaLineaEquipo.lineaSinAsignacion;

    try {
      final equipo = await _equipoRepository.asociar(
        lineaTelefonicaId: lineaTelefonicaId,
        unidadId: unidadId,
        fechaInicio: fechaInicio,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        alinearLineaConEmpleadoId:
            alinear && custodia!.tipo == TipoDestinoTelefonia.empleado ? custodia.id : null,
        alinearLineaConServicioId:
            alinear && custodia!.tipo == TipoDestinoTelefonia.servicio ? custodia.id : null,
        actorUsuarioId: actorUsuarioId,
      );
      return AsociarEquipoLineaTelefonicaExitoso(equipo);
    } catch (e) {
      return AsociarEquipoLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
