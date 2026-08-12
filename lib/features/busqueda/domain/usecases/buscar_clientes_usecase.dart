import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

class BuscarClientesUseCase {
  BuscarClientesUseCase(this._clienteRepository);

  final ClienteRepository _clienteRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final clientes = await _clienteRepository.listarActivos();
    final coincidencias = clientes.where((c) => coincideBusqueda(texto, [c.nombreComercial, c.codigo]));

    return [
      for (final c in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: c.id,
          titulo: c.nombreComercial,
          subtitulo: c.codigo,
          ruta: '/comercial/clientes/${c.id}',
        ),
    ];
  }
}
