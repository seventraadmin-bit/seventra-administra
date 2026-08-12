import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

class BuscarVehiculosUseCase {
  BuscarVehiculosUseCase(this._vehiculoRepository);

  final VehiculoRepository _vehiculoRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final vehiculos = await _vehiculoRepository.listar(soloActivos: false);
    final coincidencias = vehiculos.where((v) => coincideBusqueda(texto, [v.marca, v.modelo, v.placas, v.codigo]));

    return [
      for (final v in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: v.id,
          titulo: '${v.marca} ${v.modelo}',
          subtitulo: v.placas ?? v.codigo,
          ruta: '/vehiculos/flotilla/${v.id}',
        ),
    ];
  }
}
