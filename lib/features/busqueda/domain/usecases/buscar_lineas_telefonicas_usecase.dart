import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

/// Busca por número/código de Línea — **nunca** importa
/// `EquipoTelefonicoRepository`/`RevelarCredencialEquipoTelefonicoUseCase`/
/// `CredentialCipher`, mismo límite estructural que Reportes (12D) y
/// Dashboard (13).
class BuscarLineasTelefonicasUseCase {
  BuscarLineasTelefonicasUseCase(this._lineaTelefonicaRepository);

  final LineaTelefonicaRepository _lineaTelefonicaRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final lineas = await _lineaTelefonicaRepository.listar(soloActivos: false);
    final coincidencias = lineas.where((l) => coincideBusqueda(texto, [l.numero, l.codigo]));

    return [
      for (final l in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: l.id,
          titulo: l.numero ?? l.codigo,
          subtitulo: l.codigo,
          ruta: '/telefonia/lineas/${l.id}',
        ),
    ];
  }
}
