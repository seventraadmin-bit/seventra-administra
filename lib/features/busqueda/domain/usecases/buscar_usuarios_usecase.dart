import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/usuarios/domain/repositories/usuario_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

/// Busca por nombre/nombre de usuario — **nunca** `passwordHash`. No
/// existía ninguna proyección segura de Usuario antes de esta etapa;
/// esta es la primera.
class BuscarUsuariosUseCase {
  BuscarUsuariosUseCase(this._usuarioRepository);

  final UsuarioRepository _usuarioRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final usuarios = await _usuarioRepository.listar(cicloVidaRegistro: CicloVidaRegistro.activo.name);
    final coincidencias = usuarios.where((u) => coincideBusqueda(texto, [u.nombre, u.nombreUsuario]));

    return [
      for (final u in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: u.id,
          titulo: u.nombre,
          subtitulo: u.nombreUsuario,
          ruta: '/configuracion/usuarios',
        ),
    ];
  }
}
