import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart' show EstatusServicio;
import 'package:riseg_one/features/personal/personal_providers.dart';

import '../../organizacion_providers.dart';
import 'clientes_list_state.dart';

part 'clientes_list_controller.g.dart';

/// Controlador del listado de Clientes comerciales — mismo shape que
/// `PuestosListController`, más las métricas reales de Comercial
/// (Etapa 16): Servicios activos y Personal asignado por Cliente,
/// ambos agregados en memoria sobre listados completos ya cargados en
/// una sola consulta cada uno.
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

      final logoIds = [for (final c in clientes) if (c.logoAttachmentId != null) c.logoAttachmentId!];
      final logos = await ref.read(attachmentRepositoryProvider).obtenerPorIds(logoIds);
      final logosPorAttachmentId = {for (final logo in logos) logo.id: logo.path};
      final logoPathPorClienteId = {
        for (final c in clientes)
          if (c.logoAttachmentId != null && logosPorAttachmentId.containsKey(c.logoAttachmentId))
            c.id: logosPorAttachmentId[c.logoAttachmentId]!,
      };

      final ids = [for (final c in clientes) c.id];
      final direccionReferenciaPorClienteId = await ref.read(clienteRepositoryProvider).listarDireccionesReferencia(ids);

      // Servicios activos y Personal asignado por Cliente (Etapa 16) —
      // dos consultas en lote (Servicio y AsignacionServicio, ambas ya
      // existentes) compuestas en memoria, nunca una consulta nueva
      // por fila. "Personal asignado" cuenta empleados con asignación
      // vigente en CUALQUIERA de los Servicios del Cliente, sin
      // importar el estatus de ese Servicio — es un hecho actual real
      // ("¿cuánta gente tiene ahí ahora mismo?"), no una proyección.
      final servicios = await ref.read(servicioRepositoryProvider).listar();
      final clienteIdPorServicioId = {for (final s in servicios) s.servicio.id: s.servicio.clienteId};
      final serviciosActivosPorCliente = <String, int>{};
      for (final s in servicios) {
        if (s.servicio.estatus != EstatusServicio.activo.name) continue;
        serviciosActivosPorCliente[s.servicio.clienteId] = (serviciosActivosPorCliente[s.servicio.clienteId] ?? 0) + 1;
      }

      final asignacionesActivas = await ref.read(asignacionServicioRepositoryProvider).listarTodasActivas();
      final personalPorCliente = <String, int>{};
      final empleadosContadosPorCliente = <String, Set<String>>{};
      for (final a in asignacionesActivas) {
        final clienteId = clienteIdPorServicioId[a.servicioId];
        if (clienteId == null) continue;
        final yaContado = empleadosContadosPorCliente.putIfAbsent(clienteId, () => {});
        if (yaContado.add(a.empleadoId)) {
          personalPorCliente[clienteId] = (personalPorCliente[clienteId] ?? 0) + 1;
        }
      }

      state = state.copyWith(
        cargando: false,
        clientes: clientes,
        logoPathPorClienteId: logoPathPorClienteId,
        direccionReferenciaPorClienteId: direccionReferenciaPorClienteId,
        serviciosActivosPorCliente: serviciosActivosPorCliente,
        personalPorCliente: personalPorCliente,
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

  void cambiarFiltroEstado(String? estatus) {
    state = state.copyWith(filtroEstado: estatus, limpiarFiltroEstado: estatus == null);
  }

  void cambiarFiltroServicios(FiltroServiciosCliente filtro) {
    state = state.copyWith(filtroServicios: filtro);
  }

  void cambiarGrupo(GrupoComercialCliente grupo) {
    state = state.copyWith(grupo: grupo);
  }

  void limpiarTodosLosFiltros() {
    state = state.copyWith(busqueda: '', limpiarFiltroEstado: true, filtroServicios: FiltroServiciosCliente.todos);
  }

  /// Se llama tras crear un Cliente desde el diálogo de alta, para que el
  /// listado lo refleje de inmediato.
  Future<void> recargar() => _cargar();
}
