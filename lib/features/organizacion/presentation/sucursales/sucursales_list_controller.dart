import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../organizacion_providers.dart';
import 'sucursales_list_state.dart';

part 'sucursales_list_controller.g.dart';

/// Controlador de la pantalla de listado de Sucursales — carga, error,
/// texto de búsqueda. El filtrado en sí vive en `SucursalesListState`
/// (puro, sin efectos), no aquí.
@riverpod
class SucursalesListController extends _$SucursalesListController {
  @override
  SucursalesListState build() {
    Future.microtask(_cargar);
    return const SucursalesListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final sucursales = await ref.read(listarSucursalesUseCaseProvider).ejecutar();
      final tipos = await ref.read(listarTiposSucursalUseCaseProvider).ejecutar();
      state = state.copyWith(cargando: false, sucursales: sucursales, tipos: tipos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  void actualizarBusqueda(String texto) {
    state = state.copyWith(busqueda: texto);
  }

  /// Se llama tras crear una Sucursal desde el diálogo de alta, para que
  /// el listado la refleje de inmediato.
  Future<void> recargar() => _cargar();
}
