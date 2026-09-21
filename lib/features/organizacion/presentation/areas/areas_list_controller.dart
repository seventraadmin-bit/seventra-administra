import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show EstatusEmpleado;
import 'package:riseg_one/features/personal/personal_providers.dart';

import '../../organizacion_providers.dart';
import 'areas_list_state.dart';

part 'areas_list_controller.g.dart';

/// Controlador del listado de Áreas — carga, error, búsqueda y las
/// métricas reales de Puestos/Personal por Área. Las acciones (crear,
/// editar, activar, desactivar) se invocan directo desde la pantalla
/// vía sus propios casos de uso y luego llaman `recargar()`, mismo
/// patrón que `SucursalesListController`.
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

      // Puestos activos por Área — un solo listado completo, agrupado
      // en memoria (Etapa 16, tercera pasada visual).
      final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
      final puestosPorArea = <String, int>{};
      final areaPorPuestoId = <String, String>{};
      for (final p in puestos) {
        puestosPorArea[p.areaId] = (puestosPorArea[p.areaId] ?? 0) + 1;
        areaPorPuestoId[p.id] = p.areaId;
      }

      // Personal activo por Área — vía `Empleado.puestoId → Puesto.areaId`
      // (la única cadena real que conecta Personal con Área en el
      // esquema actual); un solo listado completo de Empleados
      // activos, agregado en memoria contra el mapa recién construido.
      final empleadosActivos = await ref.read(empleadoRepositoryProvider).listar(estatus: EstatusEmpleado.activo.name);
      final personalPorArea = <String, int>{};
      for (final e in empleadosActivos) {
        final puestoId = e.puestoId;
        if (puestoId == null) continue;
        final areaId = areaPorPuestoId[puestoId];
        if (areaId == null) continue;
        personalPorArea[areaId] = (personalPorArea[areaId] ?? 0) + 1;
      }

      state = state.copyWith(
        cargando: false,
        areas: areas,
        puestosPorArea: puestosPorArea,
        personalPorArea: personalPorArea,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  void actualizarBusqueda(String texto) {
    state = state.copyWith(busqueda: texto);
  }
}
