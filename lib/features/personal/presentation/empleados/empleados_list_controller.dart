import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../personal_providers.dart';
import 'empleados_list_state.dart';

part 'empleados_list_controller.g.dart';

/// Controlador del listado de Empleados (Etapa 5A) — mismo diseño que
/// `IngresosController`.
@riverpod
class EmpleadosListController extends _$EmpleadosListController {
  @override
  EmpleadosListState build() {
    Future.microtask(_cargar);
    return const EmpleadosListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final empleados = await ref.read(empleadoRepositoryProvider).listar(
            estatus: state.estatus,
            puestoId: state.puestoId,
          );
      state = state.copyWith(cargando: false, empleados: empleados, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? estatus,
    String? puestoId,
    bool limpiarEstatus = false,
    bool limpiarPuestoId = false,
  }) async {
    state = state.copyWith(
      estatus: estatus,
      puestoId: puestoId,
      limpiarEstatus: limpiarEstatus,
      limpiarPuestoId: limpiarPuestoId,
    );
    await _cargar();
  }

  Future<void> recargar() => _cargar();
}
