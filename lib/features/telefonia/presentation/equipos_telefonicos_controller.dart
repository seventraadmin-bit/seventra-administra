import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import '../telefonia_providers.dart';
import 'equipos_telefonicos_state.dart';

part 'equipos_telefonicos_controller.g.dart';

/// Controlador del listado de Equipos telefónicos (Etapa 9D, corrección
/// de invalidación) — antes de esta corrección, `EquiposTelefonicosListScreen`
/// mantenía esta misma consulta como estado local (`setState`, cargado
/// solo en `initState`), por lo que ninguna mutación (Configurar
/// equipo, editar IMEI, asignar/retirar, asociar/cambiar/retirar
/// equipo de una línea, etc.) podía refrescar la fila visible sin
/// forzar un remount completo de la pantalla (cambiar de pestaña y
/// volver). Mismo patrón exacto que `TelefoniaController` (líneas):
/// un controlador Riverpod único, invalidado explícitamente por cada
/// mutador real de Telefonía que cambie algo visible aquí.
@riverpod
class EquiposTelefonicosController extends _$EquiposTelefonicosController {
  @override
  EquiposTelefonicosState build() {
    Future.microtask(_cargar);
    return const EquiposTelefonicosState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final inventarioRepo = ref.read(inventarioRepositoryProvider);
      final lineaEquipoRepo = ref.read(lineaTelefonicaEquipoRepositoryProvider);
      final lineaRepo = ref.read(lineaTelefonicaRepositoryProvider);
      final asignacionRepo = ref.read(asignacionRepositoryProvider);
      final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);

      final unidades = await inventarioRepo.listarUnidadesTelefono();

      final telefonoPorUnidad = <String, ArticuloUnidadTelefonoData>{};
      final lineaPorUnidad = <String, LineaTelefonicaData>{};
      final asignacionPorUnidad = <String, AsignacionData>{};
      for (final unidad in unidades) {
        final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
        if (telefono != null) telefonoPorUnidad[unidad.id] = telefono;

        final equipoActual = await lineaEquipoRepo.obtenerActualPorUnidad(unidad.id);
        if (equipoActual != null) {
          final linea = await lineaRepo.obtenerPorId(equipoActual.lineaTelefonicaId);
          if (linea != null) lineaPorUnidad[unidad.id] = linea;
        }

        final asignacion = await asignacionRepo.obtenerActivaPorUnidad(unidad.id);
        if (asignacion != null) asignacionPorUnidad[unidad.id] = asignacion;
      }

      final empleados = await opciones.obtenerEmpleados();
      final servicios = await opciones.obtenerServicios();

      state = state.copyWith(
        cargando: false,
        unidades: unidades,
        telefonoPorUnidad: telefonoPorUnidad,
        lineaPorUnidad: lineaPorUnidad,
        asignacionPorUnidad: asignacionPorUnidad,
        empleadosPorId: {for (final e in empleados) e.id: e.nombre},
        serviciosPorId: {for (final s in servicios) s.id: s.nombre},
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> recargar() => _cargar();
}
