import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

/// A diferencia de las otras 7 búsquedas, `CompraRepository.listar`
/// ya filtra por `folio`/`proveedor` — se reutiliza tal cual, sin
/// duplicar el filtrado en Dart.
class BuscarComprasUseCase {
  BuscarComprasUseCase(this._compraRepository);

  final CompraRepository _compraRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final porFolio = await _compraRepository.listar(folio: texto);
    final porProveedor = await _compraRepository.listar(proveedor: texto);
    final combinadas = {for (final c in [...porFolio, ...porProveedor]) c.id: c}.values;

    return [
      for (final c in combinadas.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: c.id,
          titulo: c.folioCompra,
          subtitulo: c.proveedor ?? '—',
          ruta: '/compras/${c.id}',
        ),
    ];
  }
}
