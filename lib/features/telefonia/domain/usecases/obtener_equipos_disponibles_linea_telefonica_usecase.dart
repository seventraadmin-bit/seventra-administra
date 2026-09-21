import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/linea_telefonica_equipo_repository.dart';

/// Opción mínima para el selector de equipo — la UI de Telefonía nunca
/// conoce el tipo real `ArticuloUnidadData`, siempre vía este caso de
/// uso (mismo criterio de aislamiento cruzado que
/// `ObtenerOpcionesAsignacionLineaTelefonicaUseCase`).
class EquipoOpcionLineaTelefonica {
  const EquipoOpcionLineaTelefonica({required this.unidadId, required this.codigo, required this.descripcion});
  final String unidadId;
  final String codigo;
  final String descripcion;
}

/// Unidades de Inventario elegibles como equipo de una línea telefónica
/// (Etapa 9B, punto 4: "solo deben ser seleccionables unidades que
/// realmente sean teléfono... rechazar cualquier otra unidad
/// serializada"). Dependencia cruzada de solo lectura a `inventario`.
///
/// **`asignado` también es elegible** desde la Rebanada 2. Antes sólo
/// se listaban las `disponible`, porque Telefonía movía la custodia
/// después; ahora el orden correcto es el inverso —Inventario entrega
/// el aparato y luego se le asocia la SIM—, así que un teléfono ya
/// entregado tiene que poder seleccionarse. Lo que sigue fuera es todo
/// lo que no puede traer una SIM: baja, perdido, dañado y los destinos
/// intermedios.
///
/// Se excluyen además las unidades que YA traen una línea vigente: un
/// teléfono trae una SIM a la vez.
class ObtenerEquiposDisponiblesLineaTelefonicaUseCase {
  ObtenerEquiposDisponiblesLineaTelefonicaUseCase(this._inventarioRepository, this._equipoRepository);

  final InventarioRepository _inventarioRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;

  static const _elegibles = {EstatusArticuloUnidad.disponible, EstatusArticuloUnidad.asignado};

  Future<List<EquipoOpcionLineaTelefonica>> ejecutar() async {
    final unidades = await _inventarioRepository.listarUnidadesTelefono();
    final yaConLinea = (await _equipoRepository.obtenerActualesPorTodasLasLineas())
        .values
        .map((e) => e.unidadId)
        .toSet();
    return [
      for (final u in unidades)
        if (_elegibles.contains(EstatusArticuloUnidad.values.byName(u.estatus)) && !yaConLinea.contains(u.id))
          _aOpcion(u.id, u.codigo, u.marca, u.modelo),
    ];
  }

  /// Resuelve la info de despliegue de una unidad ya asociada (o
  /// histórica) — a diferencia de [ejecutar], no filtra por
  /// disponibilidad: una unidad ya asociada puede legítimamente estar
  /// `asignado` en Inventario en este momento.
  Future<EquipoOpcionLineaTelefonica?> obtenerInfo(String unidadId) async {
    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return null;
    return _aOpcion(unidad.id, unidad.codigo, unidad.marca, unidad.modelo);
  }

  EquipoOpcionLineaTelefonica _aOpcion(String unidadId, String codigo, String? marca, String? modelo) {
    return EquipoOpcionLineaTelefonica(
      unidadId: unidadId,
      codigo: codigo,
      descripcion: [marca, modelo].whereType<String>().where((p) => p.trim().isNotEmpty).join(' '),
    );
  }
}
