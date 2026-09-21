import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../coherencia_linea_equipo.dart';
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';
import 'obtener_coherencia_linea_equipo_usecase.dart';

sealed class CambiarEquipoLineaTelefonicaResultado {}

class CambiarEquipoLineaTelefonicaExitoso extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaExitoso(this.equipo);
  final LineaTelefonicaEquipoData equipo;
}

class CambiarEquipoLineaTelefonicaLineaNoExiste extends CambiarEquipoLineaTelefonicaResultado {}

class CambiarEquipoLineaTelefonicaLineaDeBaja extends CambiarEquipoLineaTelefonicaResultado {}

/// La línea no tiene equipo vigente — usa
/// `AsociarEquipoLineaTelefonicaUseCase`.
class CambiarEquipoLineaTelefonicaSinEquipoVigente extends CambiarEquipoLineaTelefonicaResultado {}

class CambiarEquipoLineaTelefonicaUnidadNoExiste extends CambiarEquipoLineaTelefonicaResultado {}

class CambiarEquipoLineaTelefonicaUnidadNoEsTelefono extends CambiarEquipoLineaTelefonicaResultado {}

class CambiarEquipoLineaTelefonicaUnidadNoDisponible extends CambiarEquipoLineaTelefonicaResultado {}

/// Un teléfono trae UNA SIM a la vez: esta unidad ya está asociada a
/// otra línea vigente. El selector ya las excluye, pero la regla vive
/// aquí — que la UI lo impida no basta.
class CambiarEquipoLineaTelefonicaUnidadYaTraeOtraLinea extends CambiarEquipoLineaTelefonicaResultado {}

/// §1A — el aparato está declarado pendiente de recuperación de alguien
/// que causó baja. No es un dato roto, pero tampoco un teléfono
/// disponible para traer una SIM: alinear la línea con esa custodia
/// sería asignársela a un ex-empleado.
class CambiarEquipoLineaTelefonicaEquipoPendienteRecuperacion extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaEquipoPendienteRecuperacion(this.custodia);
  final DestinoTelefonia custodia;
}

/// §7, aplicado al equipo de reemplazo.
class CambiarEquipoLineaTelefonicaRequiereAlinearLinea extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaRequiereAlinearLinea(this.custodia);
  final DestinoTelefonia custodia;
}

/// §8 — el aparato nuevo no está en manos de nadie mientras la línea sí
/// tiene destino.
class CambiarEquipoLineaTelefonicaEquipoSinCustodia extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaEquipoSinCustodia(this.destinoLinea);
  final DestinoTelefonia destinoLinea;
}

/// §10 — la línea apunta a uno y el aparato nuevo está en manos de otro.
class CambiarEquipoLineaTelefonicaDestinosDistintos extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaDestinosDistintos(this.destinoLinea, this.custodia);
  final DestinoTelefonia destinoLinea;
  final DestinoTelefonia custodia;
}

class CambiarEquipoLineaTelefonicaErrorInesperado extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Sustituye el teléfono asociado a una línea sin cambiar la línea en
/// sí (Etapa 9B, punto 9 del pedido original de Telefonía: "el cambio
/// de teléfono no crea una línea nueva"). Cierra el periodo del equipo
/// vigente e inicia el del nuevo — el historial de ambos queda intacto.
///
/// **No toca la custodia de ninguno de los dos aparatos** (Rebanada 2):
/// que un teléfono deje de traer la SIM no lo devuelve a Inventario, y
/// que otro empiece a traerla no se la entrega a nadie.
class CambiarEquipoLineaTelefonicaUseCase {
  CambiarEquipoLineaTelefonicaUseCase(
    this._lineaRepository,
    this._equipoRepository,
    this._inventarioRepository,
    AsignacionLineaTelefonicaRepository asignacionRepository,
  ) : _coherencia = ObtenerCoherenciaLineaEquipoUseCase(_equipoRepository, asignacionRepository);

  final LineaTelefonicaRepository _lineaRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;
  final InventarioRepository _inventarioRepository;
  final ObtenerCoherenciaLineaEquipoUseCase _coherencia;

  Future<CambiarEquipoLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    bool alinearLineaConCustodia = false,
    String? actorUsuarioId,
  }) async {
    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return CambiarEquipoLineaTelefonicaLineaNoExiste();
    if (linea.estatus == 'baja') return CambiarEquipoLineaTelefonicaLineaDeBaja();

    final equipoVigente = await _equipoRepository.obtenerActualPorLinea(lineaTelefonicaId);
    if (equipoVigente == null) return CambiarEquipoLineaTelefonicaSinEquipoVigente();

    final telefono = await _inventarioRepository.obtenerTelefono(nuevaUnidadId);
    if (telefono == null) return CambiarEquipoLineaTelefonicaUnidadNoEsTelefono();

    final unidad = await _inventarioRepository.obtenerUnidadPorId(nuevaUnidadId);
    if (unidad == null) return CambiarEquipoLineaTelefonicaUnidadNoExiste();

    final estatus = EstatusArticuloUnidad.values.byName(unidad.estatus);
    if (estatus != EstatusArticuloUnidad.disponible && estatus != EstatusArticuloUnidad.asignado) {
      return CambiarEquipoLineaTelefonicaUnidadNoDisponible();
    }

    if (await _equipoRepository.obtenerActualPorUnidad(nuevaUnidadId) != null) {
      return CambiarEquipoLineaTelefonicaUnidadYaTraeOtraLinea();
    }

    final destinoLinea = (await _coherencia.ejecutar(lineaTelefonicaId)).destinoLinea;
    final custodiaInventario = await _equipoRepository.obtenerCustodiaInventarioActual(nuevaUnidadId);
    final custodia = destinoDeCustodia(custodiaInventario);
    final resultante = evaluarCoherenciaLineaEquipo(
      unidadId: nuevaUnidadId,
      destinoLinea: destinoLinea,
      destinoEquipo: custodia,
      // Sin esto, un aparato pendiente de recuperación se leería como
      // una inconsistencia cualquiera y se le alinearía la línea.
      pendienteRecuperacionDesde: custodiaInventario?.pendienteRecuperacionDesde,
    );

    switch (resultante.estado) {
      case EstadoCoherenciaLineaEquipo.equipoSinCustodia:
        return CambiarEquipoLineaTelefonicaEquipoSinCustodia(destinoLinea!);
      case EstadoCoherenciaLineaEquipo.destinosDistintos:
        return CambiarEquipoLineaTelefonicaDestinosDistintos(destinoLinea!, custodia!);
      case EstadoCoherenciaLineaEquipo.equipoPendienteRecuperacion:
        return CambiarEquipoLineaTelefonicaEquipoPendienteRecuperacion(custodia!);
      case EstadoCoherenciaLineaEquipo.lineaSinAsignacion:
        if (!alinearLineaConCustodia) {
          return CambiarEquipoLineaTelefonicaRequiereAlinearLinea(custodia!);
        }
      case EstadoCoherenciaLineaEquipo.coherente:
      case EstadoCoherenciaLineaEquipo.sinEquipo:
        break;
    }

    final alinear = resultante.estado == EstadoCoherenciaLineaEquipo.lineaSinAsignacion;

    try {
      final equipo = await _equipoRepository.cambiar(
        lineaTelefonicaId: lineaTelefonicaId,
        nuevaUnidadId: nuevaUnidadId,
        fecha: fecha,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        alinearLineaConEmpleadoId:
            alinear && custodia!.tipo == TipoDestinoTelefonia.empleado ? custodia.id : null,
        alinearLineaConServicioId:
            alinear && custodia!.tipo == TipoDestinoTelefonia.servicio ? custodia.id : null,
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarEquipoLineaTelefonicaExitoso(equipo);
    } catch (e) {
      return CambiarEquipoLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
