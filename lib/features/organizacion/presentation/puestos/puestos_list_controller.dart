import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../organizacion_providers.dart';
import 'puestos_list_state.dart';

part 'puestos_list_controller.g.dart';

/// Controlador de la pantalla de listado de Puestos — mismo shape que
/// `SucursalesListController`, con búsqueda que también cubre
/// descripción (no solo código/nombre/área/tipo).
@riverpod
class PuestosListController extends _$PuestosListController {
  @override
  PuestosListState build() {
    Future.microtask(_cargar);
    return const PuestosListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final puestos = await ref.read(listarPuestosUseCaseProvider).ejecutar();
      final areas = await ref.read(listarAreasUseCaseProvider).ejecutar();
      state = state.copyWith(cargando: false, puestos: puestos, areas: areas, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  void actualizarBusqueda(String texto) {
    state = state.copyWith(busqueda: texto);
  }

  /// Se llama tras crear un Puesto desde el diálogo de alta, para que el
  /// listado lo refleje de inmediato.
  Future<void> recargar() => _cargar();
}
