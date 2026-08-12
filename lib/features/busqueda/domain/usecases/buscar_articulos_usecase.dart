import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

class BuscarArticulosUseCase {
  BuscarArticulosUseCase(this._articuloRepository);

  final ArticuloRepository _articuloRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final articulos = await _articuloRepository.listar(soloActivos: false);
    final coincidencias = articulos.where((a) => coincideBusqueda(texto, [a.nombre, a.folio]));

    return [
      for (final a in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(id: a.id, titulo: a.nombre, subtitulo: a.folio, ruta: '/inventario/articulos/${a.id}'),
    ];
  }
}
