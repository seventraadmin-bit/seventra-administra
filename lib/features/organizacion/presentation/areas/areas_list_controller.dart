import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../organizacion_providers.dart';
import 'areas_list_state.dart';

part 'areas_list_controller.g.dart';

/// Controlador del listado de Áreas — solo carga/error/recarga. Las
/// acciones (crear, editar, activar, desactivar) se invocan directo
/// desde la pantalla vía sus propios casos de uso y luego llaman
/// `recargar()`, mismo patrón que `SucursalesListController`.
@riverpod
class AreasListController extends _$AreasListController {
  @override
  AreasListState build() {
    Future.microtask(_cargar);
    return const AreasListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final areas = await ref.read(listarAreasUseCaseProvider).ejecutar();
      state = state.copyWith(cargando: false, areas: areas, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();
}
