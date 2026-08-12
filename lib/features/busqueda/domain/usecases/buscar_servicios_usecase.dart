import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

class BuscarServiciosUseCase {
  BuscarServiciosUseCase(this._servicioRepository);

  final ServicioRepository _servicioRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final servicios = await _servicioRepository.listar();
    final coincidencias = servicios.where(
      (s) => coincideBusqueda(texto, [s.servicio.nombre, s.servicio.codigo, s.clienteNombre]),
    );

    return [
      for (final s in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: s.servicio.id,
          titulo: s.servicio.nombre,
          subtitulo: s.clienteNombre,
          ruta: '/comercial/servicios/${s.servicio.id}',
        ),
    ];
  }
}
