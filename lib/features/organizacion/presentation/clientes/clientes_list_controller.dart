import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../organizacion_providers.dart';
import 'clientes_list_state.dart';

part 'clientes_list_controller.g.dart';

/// Controlador del listado de Clientes comerciales — mismo shape que
/// `PuestosListController`.
@riverpod
class ClientesListController extends _$ClientesListController {
  @override
  ClientesListState build() {
    Future.microtask(_cargar);
    return const ClientesListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final clientes = await ref.read(listarClientesUseCaseProvider).ejecutar();
      state = state.copyWith(cargando: false, clientes: clientes, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  void actualizarBusqueda(String texto) {
    state = state.copyWith(busqueda: texto);
  }

  /// Se llama tras crear un Cliente desde el diálogo de alta, para que el
  /// listado lo refleje de inmediato.
  Future<void> recargar() => _cargar();
}
