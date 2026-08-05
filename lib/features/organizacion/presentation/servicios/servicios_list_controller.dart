import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../organizacion_providers.dart';
import 'servicios_list_state.dart';

part 'servicios_list_controller.g.dart';

/// Controlador del listado de Servicios — mismo shape que
/// `ClientesListController`.
@riverpod
class ServiciosListController extends _$ServiciosListController {
  @override
  ServiciosListState build() {
    Future.microtask(_cargar);
    return const ServiciosListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final servicios = await ref.read(listarServiciosUseCaseProvider).ejecutar();
      state = state.copyWith(cargando: false, servicios: servicios, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  void actualizarBusqueda(String texto) {
    state = state.copyWith(busqueda: texto);
  }

  /// Se llama tras crear un Servicio desde el diálogo de alta, para que
  /// el listado lo refleje de inmediato.
  Future<void> recargar() => _cargar();
}
