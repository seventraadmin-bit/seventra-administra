import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';

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

class AsociarEquipoLineaTelefonicaUnidadNoDisponible extends AsociarEquipoLineaTelefonicaResultado {}

class AsociarEquipoLineaTelefonicaErrorInesperado extends AsociarEquipoLineaTelefonicaResultado {
  AsociarEquipoLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asocia un teléfono físico de Inventario a una línea sin equipo
/// (Etapa 9B) — si la línea tiene una asignación vigente, sincroniza la
/// custodia del equipo en Inventario hacia ese mismo destino (ver el
/// doc comment de `LineaTelefonicaEquipoRepository`).
class AsociarEquipoLineaTelefonicaUseCase {
  AsociarEquipoLineaTelefonicaUseCase(this._lineaRepository, this._equipoRepository, this._inventarioRepository);

  final LineaTelefonicaRepository _lineaRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;
  final InventarioRepository _inventarioRepository;

  Future<AsociarEquipoLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    String? actor,
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
    if (EstatusArticuloUnidad.values.byName(unidad.estatus) != EstatusArticuloUnidad.disponible) {
      return AsociarEquipoLineaTelefonicaUnidadNoDisponible();
    }

    try {
      final equipo = await _equipoRepository.asociar(
        lineaTelefonicaId: lineaTelefonicaId,
        unidadId: unidadId,
        fechaInicio: fechaInicio,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actor: actor,
      );
      return AsociarEquipoLineaTelefonicaExitoso(equipo);
    } catch (e) {
      return AsociarEquipoLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
