import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../finanzas_providers.dart';
import 'categorias_list_state.dart';

part 'categorias_list_controller.g.dart';

/// Controlador del listado de Categorías financieras (Etapa 4K.1) —
/// mismo diseño que `AreasListController`: solo carga/error/recarga,
/// las acciones (crear, archivar) se invocan directo desde la pantalla.
@riverpod
class CategoriasListController extends _$CategoriasListController {
  @override
  CategoriasListState build() {
    Future.microtask(_cargar);
    return const CategoriasListState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar();
      state = state.copyWith(cargando: false, categorias: categorias, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();
}
