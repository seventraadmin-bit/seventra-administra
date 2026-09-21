import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart' show EstatusServicio;
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show EstatusEmpleado;
import 'package:riseg_one/features/personal/personal_providers.dart';

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
      final sucursalRepo = ref.read(sucursalRepositoryProvider);
      final sucursales = await ref.read(listarSucursalesUseCaseProvider).ejecutar();
      final tipos = await ref.read(listarTiposSucursalUseCaseProvider).ejecutar();

      final ids = [for (final s in sucursales) s.id];
      final direccionPorSucursalId = await sucursalRepo.listarDireccionesPrincipales(ids);

      // Personal y Servicios por Sucursal (Etapa 16, tercera pasada
      // visual) — relaciones reales ya existentes en el esquema
      // (`Empleado.sucursalId`/`Servicio.sucursalAdministrativaId`),
      // agregadas en memoria sobre los listados completos ya cargados
      // en una sola consulta cada uno — nunca una consulta nueva por
      // tarjeta. Sin relación real Sucursal↔Área en el esquema actual,
      // ese tercer contador del pedido se omite deliberadamente.
      final empleadosActivos = await ref.read(empleadoRepositoryProvider).listar(estatus: EstatusEmpleado.activo.name);
      final personalPorSucursal = <String, int>{};
      for (final e in empleadosActivos) {
        final sucursalId = e.sucursalId;
        if (sucursalId == null) continue;
        personalPorSucursal[sucursalId] = (personalPorSucursal[sucursalId] ?? 0) + 1;
      }

      final servicios = await ref.read(servicioRepositoryProvider).listar();
      final serviciosPorSucursal = <String, int>{};
      for (final item in servicios) {
        final sucursalId = item.servicio.sucursalAdministrativaId;
        if (sucursalId == null || item.servicio.estatus != EstatusServicio.activo.name) continue;
        serviciosPorSucursal[sucursalId] = (serviciosPorSucursal[sucursalId] ?? 0) + 1;
      }

      state = state.copyWith(
        cargando: false,
        sucursales: sucursales,
        tipos: tipos,
        direccionPorSucursalId: direccionPorSucursalId,
        personalPorSucursal: personalPorSucursal,
        serviciosPorSucursal: serviciosPorSucursal,
        errorCarga: null,
      );
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
