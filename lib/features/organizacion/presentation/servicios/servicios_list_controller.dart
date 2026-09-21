import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/personal/personal_providers.dart';

import '../../organizacion_providers.dart';
import 'servicios_list_state.dart';

part 'servicios_list_controller.g.dart';

/// Controlador del listado de Servicios — mismo shape que
/// `ClientesListController`, más Personal asignado y Modalidad de
/// turno por Servicio (Etapa 16), ambos agregados en memoria sobre
/// listados completos ya cargados en una sola consulta cada uno.
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

      final logoIds = [
        for (final item in servicios)
          if (item.clienteLogoAttachmentId != null) item.clienteLogoAttachmentId!,
      ];
      final logos = await ref.read(attachmentRepositoryProvider).obtenerPorIds(logoIds);
      final logosPorAttachmentId = {for (final logo in logos) logo.id: logo.path};
      final logoPathPorClienteId = {
        for (final item in servicios)
          if (item.clienteLogoAttachmentId != null && logosPorAttachmentId.containsKey(item.clienteLogoAttachmentId))
            item.servicio.clienteId: logosPorAttachmentId[item.clienteLogoAttachmentId]!,
      };

      // Personal asignado y Modalidad de turno por Servicio (Etapa 16)
      // — una sola consulta en lote (`listarTodasActivas`, ya usada por
      // `ClientesListController`) más el catálogo completo de
      // Modalidades de turno (tabla de referencia pequeña, no escala
      // con el listado), nunca una consulta nueva por fila.
      final asignacionesActivas = await ref.read(asignacionServicioRepositoryProvider).listarTodasActivas();
      final turnos = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
      final nombrePorTurnoId = {for (final t in turnos) t.id: t.nombre};

      final personalPorServicio = <String, int>{};
      final turnosPorServicio = <String, Set<String>>{};
      for (final a in asignacionesActivas) {
        personalPorServicio[a.servicioId] = (personalPorServicio[a.servicioId] ?? 0) + 1;
        final nombreTurno = a.turnoId == null ? null : nombrePorTurnoId[a.turnoId];
        if (nombreTurno != null) {
          turnosPorServicio.putIfAbsent(a.servicioId, () => {}).add(nombreTurno);
        }
      }
      final turnoPorServicio = {
        for (final entry in turnosPorServicio.entries) entry.key: (entry.value.toList()..sort()).join(' / '),
      };

      state = state.copyWith(
        cargando: false,
        servicios: servicios,
        logoPathPorClienteId: logoPathPorClienteId,
        personalPorServicio: personalPorServicio,
        turnoPorServicio: turnoPorServicio,
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

  void cambiarFiltroCliente(String? clienteId) {
    state = state.copyWith(filtroClienteId: clienteId, limpiarFiltroCliente: clienteId == null);
  }

  void cambiarFiltroEstatus(String? estatus) {
    state = state.copyWith(filtroEstatus: estatus, limpiarFiltroEstatus: estatus == null);
  }

  void cambiarFiltroTipo(String? tipoServicioId) {
    state = state.copyWith(filtroTipoServicioId: tipoServicioId, limpiarFiltroTipo: tipoServicioId == null);
  }

  void cambiarGrupo(GrupoVigenciaServicio grupo) {
    state = state.copyWith(grupo: grupo);
  }

  void limpiarTodosLosFiltros() {
    state = state.copyWith(busqueda: '', limpiarFiltroCliente: true, limpiarFiltroEstatus: true, limpiarFiltroTipo: true);
  }

  /// Se llama tras crear un Servicio desde el diálogo de alta, para que
  /// el listado lo refleje de inmediato.
  Future<void> recargar() => _cargar();
}
