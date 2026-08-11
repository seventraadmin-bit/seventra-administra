import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';

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

class CambiarEquipoLineaTelefonicaErrorInesperado extends CambiarEquipoLineaTelefonicaResultado {
  CambiarEquipoLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Sustituye el teléfono asociado a una línea sin cambiar la línea en
/// sí (Etapa 9B, punto 9 del pedido original de Telefonía: "el cambio
/// de teléfono no crea una línea nueva"). Cierra el equipo vigente
/// (liberando su custodia en Inventario si coincide con el destino
/// actual de la línea) y asocia el nuevo (moviendo la custodia al mismo
/// destino, si la línea tiene uno) — una sola operación.
class CambiarEquipoLineaTelefonicaUseCase {
  CambiarEquipoLineaTelefonicaUseCase(this._lineaRepository, this._equipoRepository, this._inventarioRepository);

  final LineaTelefonicaRepository _lineaRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;
  final InventarioRepository _inventarioRepository;

  Future<CambiarEquipoLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    String? actor,
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
    if (EstatusArticuloUnidad.values.byName(unidad.estatus) != EstatusArticuloUnidad.disponible) {
      return CambiarEquipoLineaTelefonicaUnidadNoDisponible();
    }

    try {
      final equipo = await _equipoRepository.cambiar(
        lineaTelefonicaId: lineaTelefonicaId,
        nuevaUnidadId: nuevaUnidadId,
        fecha: fecha,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actor: actor,
      );
      return CambiarEquipoLineaTelefonicaExitoso(equipo);
    } catch (e) {
      return CambiarEquipoLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
