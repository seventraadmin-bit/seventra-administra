import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

import '../../personal_providers.dart';
import 'personal_activo_state.dart';

part 'personal_activo_controller.g.dart';

/// Controlador de "Personal activo" (Etapa 15, rediseño de
/// Personal/Bajas) — mismo diseño que `EmpleadosListController`, con
/// la Asignación de Servicio vigente resuelta en una sola consulta por
/// lote (`listarTodasActivas`, nunca N+1 por Empleado).
@riverpod
class PersonalActivoController extends _$PersonalActivoController {
  @override
  PersonalActivoState build() {
    Future.microtask(_cargar);
    return const PersonalActivoState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final empleadoRepo = ref.read(empleadoRepositoryProvider);
      final asignacionRepo = ref.read(asignacionServicioRepositoryProvider);
      final servicioRepo = ref.read(servicioRepositoryProvider);
      final catalogoRepo = ref.read(catalogoRepositoryProvider);
      final puestoRepo = ref.read(puestoRepositoryProvider);

      final empleados = await empleadoRepo.listar(estatus: 'activo');
      final empleadoIds = empleados.map((e) => e.id).toSet();

      // Fotografías (Etapa 16, evolución visual) — misma fuente real
      // que el expediente (`Empleado.fotografiaAttachmentId`), resuelta
      // en lote para no consultar `Attachment` fila por fila.
      final fotografiaIds = [
        for (final e in empleados)
          if (e.fotografiaAttachmentId != null) e.fotografiaAttachmentId!,
      ];
      final fotografias = await ref.read(attachmentRepositoryProvider).obtenerPorIds(fotografiaIds);
      final fotografiaPorAttachmentId = {for (final f in fotografias) f.id: f.path};
      final fotografiaPathPorEmpleadoId = {
        for (final e in empleados)
          if (e.fotografiaAttachmentId != null && fotografiaPorAttachmentId.containsKey(e.fotografiaAttachmentId))
            e.id: fotografiaPorAttachmentId[e.fotografiaAttachmentId]!,
      };

      final todasActivas = await asignacionRepo.listarTodasActivas();
      final asignacionPorEmpleado = {
        for (final a in todasActivas)
          if (empleadoIds.contains(a.empleadoId)) a.empleadoId: a,
      };

      final servicios = await servicioRepo.listar();
      final servicioNombrePorId = {for (final s in servicios) s.servicio.id: s.servicio.nombre};
      // Etapa 16, evolución visual — único cambio permitido en
      // "Plantilla activa": ubicación bajo el Servicio, SOLO cuando ya
      // existe estructurado en su Dirección (`servicios` ya viene con
      // este join, sin consulta nueva); nunca derivado del nombre.
      final ubicacionPorServicioId = {
        for (final s in servicios)
          if (s.municipioAlcaldia != null && s.estado != null) s.servicio.id: '${s.municipioAlcaldia}, ${s.estado}',
      };

      final turnos = await catalogoRepo.listarModalidadesTurno();
      final turnoNombrePorId = {for (final t in turnos) t.id: t.nombre};

      final puestos = await puestoRepo.listarActivos();

      // Sucursales: el destino de la plantilla ADMINISTRATIVA, que
      // hasta ahora no se cargaba y por eso el listado no tenía cómo
      // nombrarlo. Dos consultas en lote, nunca una por empleado.
      // `listarTodas` incluye archivadas: alguien puede seguir adscrito
      // a una que ya se archivó, y un guion ahí parecería falta de
      // destino.
      final sucursalRepo = ref.read(sucursalRepositoryProvider);
      final sucursalesTodas = await sucursalRepo.listarTodas();
      final sucursalNombrePorId = {for (final s in sucursalesTodas) s.id: s.nombre};
      final direcciones = await sucursalRepo.listarDireccionesPrincipales(sucursalesTodas.map((s) => s.id).toList());
      final ubicacionPorSucursalId = {
        for (final entrada in direcciones.entries)
          if (entrada.value.municipioAlcaldia.isNotEmpty && entrada.value.estado.isNotEmpty)
            entrada.key: '${entrada.value.municipioAlcaldia}, ${entrada.value.estado}',
      };
      // El selector sólo ofrece las activas: archivar una Sucursal la
      // retira como destino elegible, aunque siga nombrándose arriba.
      final sucursales = [
        for (final s in sucursalesTodas)
          if (s.cicloVidaRegistro == CicloVidaRegistro.activo.name) s,
      ];

      // Clasificación desde la fuente de verdad ÚNICA — la misma que
      // consume el Dashboard. Esta pantalla nunca vuelve a decidir
      // quién es operativo o administrativo.
      final plantilla = await ref.read(obtenerPlantillaPersonalUseCaseProvider).ejecutar();
      final clasificacionPorEmpleado = {for (final c in plantilla.clasificaciones) c.empleado.id: c};

      state = state.copyWith(
        cargando: false,
        empleados: empleados,
        asignacionPorEmpleado: asignacionPorEmpleado,
        clasificacionPorEmpleado: clasificacionPorEmpleado,
        servicioNombrePorId: servicioNombrePorId,
        sucursalNombrePorId: sucursalNombrePorId,
        turnoNombrePorId: turnoNombrePorId,
        ubicacionPorServicioId: ubicacionPorServicioId,
        ubicacionPorSucursalId: ubicacionPorSucursalId,
        puestos: puestos,
        servicios: servicios,
        sucursales: sucursales,
        turnos: turnos,
        fotografiaPathPorEmpleadoId: fotografiaPathPorEmpleadoId,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  void aplicarFiltros({
    String? texto,
    String? puestoId,
    DestinoFiltro? destino,
    String? turnoId,
    FiltroPlantilla? estadoAsignacion,
    bool limpiarTexto = false,
    bool limpiarPuestoId = false,
    bool limpiarDestino = false,
    bool limpiarTurnoId = false,
  }) {
    state = state.copyWith(
      texto: texto,
      puestoId: puestoId,
      destino: destino,
      turnoId: turnoId,
      estadoAsignacion: estadoAsignacion,
      limpiarTexto: limpiarTexto,
      limpiarPuestoId: limpiarPuestoId,
      limpiarDestino: limpiarDestino,
      limpiarTurnoId: limpiarTurnoId,
    );
  }

  void limpiarTodosLosFiltros() {
    state = state.copyWith(
      limpiarTexto: true,
      limpiarPuestoId: true,
      limpiarDestino: true,
      limpiarTurnoId: true,
      estadoAsignacion: FiltroPlantilla.todos,
    );
  }
}
