import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../busqueda_providers.dart';
import 'busqueda_state.dart';

part 'busqueda_controller.g.dart';

const _minimoCaracteres = 2;
const _debounce = Duration(milliseconds: 300);

/// Controlador de Búsqueda global (Etapa 14A) — igual que Reportes/
/// Dashboard, la guardia real de permiso vive aquí: cada grupo solo se
/// consulta si la sesión tiene su `hasCode(...)` correspondiente, antes
/// de invocar `BuscarGlobalUseCase`. Menos de 2 caracteres nunca
/// dispara ninguna consulta.
@riverpod
class BusquedaController extends _$BusquedaController {
  Timer? _debounceTimer;

  @override
  BusquedaState build() {
    ref.onDispose(() => _debounceTimer?.cancel());
    return const BusquedaState();
  }

  void actualizarTexto(String texto) {
    _debounceTimer?.cancel();

    if (texto.trim().length < _minimoCaracteres) {
      state = BusquedaState(texto: texto);
      return;
    }

    state = state.copyWith(texto: texto, cargando: true);
    _debounceTimer = Timer(_debounce, () => _buscar(texto));
  }

  Future<void> _buscar(String texto) async {
    final permissionService = ref.read(permissionServiceProvider);
    bool tiene(String codigo) => permissionService.hasCode(codigo);

    final resultados = await ref.read(buscarGlobalUseCaseProvider).ejecutar(
          texto.trim(),
          incluirPersonal: tiene('personal.ver'),
          incluirComercial: tiene('comercial.ver'),
          incluirInventario: tiene('inventario.ver'),
          incluirCompras: tiene('compras.ver'),
          incluirVehiculos: tiene('vehiculos.ver'),
          incluirTelefonia: tiene('telefonia.ver'),
          incluirUsuarios: tiene('usuarios.administrar'),
        );

    // El texto pudo cambiar mientras esta búsqueda estaba en vuelo
    // (otra tecla disparó un debounce más nuevo) — un resultado viejo
    // nunca debe pisar al más reciente.
    if (texto != state.texto) return;
    state = state.copyWith(resultados: resultados, cargando: false);
  }

  void limpiar() {
    _debounceTimer?.cancel();
    state = const BusquedaState();
  }
}
