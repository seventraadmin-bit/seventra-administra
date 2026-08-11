import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

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
/// serializada") — unidades con `ArticuloUnidadTelefono` y `estatus ==
/// disponible`. Dependencia cruzada de solo lectura a `inventario`,
/// mismo patrón ya establecido en el proyecto.
class ObtenerEquiposDisponiblesLineaTelefonicaUseCase {
  ObtenerEquiposDisponiblesLineaTelefonicaUseCase(this._inventarioRepository);

  final InventarioRepository _inventarioRepository;

  Future<List<EquipoOpcionLineaTelefonica>> ejecutar() async {
    final unidades = await _inventarioRepository.listarUnidadesTelefono(estatus: EstatusArticuloUnidad.disponible.name);
    return [for (final u in unidades) _aOpcion(u.id, u.codigo, u.marca, u.modelo)];
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
