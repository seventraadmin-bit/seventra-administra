import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/ubicacion_repository.dart';

import '../../organizacion_providers.dart';
import 'ubicaciones_arbol_state.dart';

part 'ubicaciones_arbol_controller.g.dart';

/// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
/// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
/// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
/// solo coordina el estado de la pantalla (carga, expandido/colapsado).
@riverpod
class UbicacionesArbolController extends _$UbicacionesArbolController {
  @override
  UbicacionesArbolState build(String sucursalId) {
    Future.microtask(_cargar);
    return const UbicacionesArbolState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerArbolUbicacionesDeSucursalUseCaseProvider).ejecutar(sucursalId);
    resultado.when(
      ok: (arbol) {
        state = state.copyWith(cargando: false, arbol: arbol, expandidos: _todosLosIds(arbol), errorCarga: null);
      },
      failure: (f) {
        state = state.copyWith(cargando: false, errorCarga: f.message);
      },
    );
  }

  Future<void> _recargarSilenciosa() async {
    final resultado = await ref.read(obtenerArbolUbicacionesDeSucursalUseCaseProvider).ejecutar(sucursalId);
    resultado.when(
      ok: (arbol) => state = state.copyWith(arbol: arbol, expandidos: _todosLosIds(arbol), errorCarga: null),
      failure: (f) => state = state.copyWith(errorCarga: f.message),
    );
  }

  Future<void> reintentarCarga() => _cargar();

  void expandirTodo() {
    final arbol = state.arbol;
    if (arbol == null) return;
    state = state.copyWith(expandidos: _todosLosIds(arbol));
  }

  void colapsarTodo() {
    state = state.copyWith(expandidos: const {});
  }

  void alternarExpandido(String nodoId) {
    final nuevo = Set<String>.from(state.expandidos);
    if (!nuevo.remove(nodoId)) nuevo.add(nodoId);
    state = state.copyWith(expandidos: nuevo);
  }

  Set<String> _todosLosIds(UbicacionArbol nodo) {
    final ids = <String>{nodo.nodo.id};
    for (final hijo in nodo.hijos) {
      ids.addAll(_todosLosIds(hijo));
    }
    return ids;
  }

  Future<bool> agregarUbicacion({
    required String parentId,
    required String nombre,
    required TipoUbicacion tipo,
  }) async {
    if (state.procesando) return false;
    state = state.copyWith(procesando: true);

    final resultado = await ref
        .read(crearUbicacionUseCaseProvider)
        .ejecutar(nombre: nombre, tipo: tipo, parentId: parentId);

    if (resultado.isOk) {
      await _recargarSilenciosa();
      state = state.copyWith(procesando: false);
      return true;
    }
    state = state.copyWith(procesando: false);
    return false;
  }

  Future<bool> moverUbicacion({required String ubicacionId, required String nuevoParentId}) async {
    if (state.procesando) return false;
    state = state.copyWith(procesando: true);

    final resultado = await ref
        .read(moverUbicacionUseCaseProvider)
        .ejecutar(ubicacionId: ubicacionId, nuevoParentId: nuevoParentId);

    if (resultado.isOk) {
      await _recargarSilenciosa();
      state = state.copyWith(procesando: false);
      return true;
    }
    state = state.copyWith(procesando: false);
    return false;
  }
}
