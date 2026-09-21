import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/plantilla_personal.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart' show CatalogoItem;
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart' show ServicioListItem;

import 'empleados_list_screen.dart' show empleadoNombreCompleto;

/// Filtro por estado de asignación a Servicio — en memoria, sobre
/// `asignacionPorEmpleado` ya cargado en bloque (Etapa 17: nunca una
/// consulta nueva por opción de filtro).
/// Filtro de plantilla del listado "Personal activo" (Etapa "Plantilla
/// operativa vs. administrativa") — reemplaza al par asignado/sinAsignar,
/// que solo miraba el Servicio y por eso no podía distinguir a un
/// administrativo correctamente adscrito de alguien sin ningún destino.
///
/// Es una VISTA sobre la misma estructura laboral: nunca duplica
/// empleados ni crea registros distintos para la misma persona.
enum FiltroPlantilla { todos, operativo, administrativo, sinAsignacion }

/// Qué clase de destino filtra el selector de Asignación.
///
/// El listado mezcla los dos destinos reales de la empresa, así que
/// filtrar "por Servicio" dejaba invisible a todo el personal
/// administrativo. Se filtra por tipo de destino + id REAL, nunca por
/// nombre.
enum TipoDestinoFiltro { servicio, sucursal, sinAsignacion }

/// Opción elegida en el filtro de Asignación. `id` es `null` sólo para
/// `sinAsignacion`, que no apunta a ninguna entidad.
typedef DestinoFiltro = ({TipoDestinoFiltro tipo, String? id});

/// Estado de la vista "Personal activo" (Etapa 15, rediseño de
/// Personal/Bajas) — solo `Empleado.estatus == activo`; un empleado
/// dado de baja jamás aparece aquí (pasa de inmediato a la vista
/// Bajas, sin recargar).
class PersonalActivoState {
  const PersonalActivoState({
    this.cargando = true,
    this.empleados = const [],
    this.asignacionPorEmpleado = const {},
    this.clasificacionPorEmpleado = const {},
    this.servicioNombrePorId = const {},
    this.sucursalNombrePorId = const {},
    this.turnoNombrePorId = const {},
    this.ubicacionPorServicioId = const {},
    this.ubicacionPorSucursalId = const {},
    this.puestos = const [],
    this.servicios = const [],
    this.sucursales = const [],
    this.turnos = const [],
    this.fotografiaPathPorEmpleadoId = const {},
    this.texto,
    this.puestoId,
    this.destino,
    this.turnoId,
    this.estadoAsignacion = FiltroPlantilla.todos,
    this.errorCarga,
  });

  final bool cargando;
  final List<EmpleadoData> empleados;

  /// Asignación de Servicio VIGENTE por Empleado — solo empleados con
  /// una fila aquí cuentan como "asignado" (Resolución explícita de
  /// Marlon: nunca inferir Servicio/Turno por nombre ni duplicarlos en
  /// `Empleado`).
  final Map<String, AsignacionServicioData> asignacionPorEmpleado;
  final Map<String, String> servicioNombrePorId;

  /// Nombre de cada Sucursal, incluidas las archivadas — el destino de
  /// la plantilla administrativa se nombra igual que el de la operativa.
  final Map<String, String> sucursalNombrePorId;

  final Map<String, String> turnoNombrePorId;

  /// "Municipio, Estado" del Servicio, por `servicioId` (Etapa 16,
  /// evolución visual — único cambio permitido en "Plantilla activa")
  /// — SOLO presente cuando el Servicio ya tiene ambos campos
  /// estructurados en su Dirección; nunca derivado del nombre del
  /// Servicio. Sin entrada, la 2ª línea de ubicación simplemente no
  /// se muestra (nunca un placeholder en esta fila densa).
  final Map<String, String> ubicacionPorServicioId;

  /// Misma idea para la Sucursal, desde su Dirección principal — nunca
  /// derivada del nombre, y ausente cuando no está capturada.
  final Map<String, String> ubicacionPorSucursalId;

  final List<PuestoData> puestos;
  final List<ServicioListItem> servicios;

  /// Sucursales activas — el otro destino real del selector de
  /// Asignación.
  final List<SucursalData> sucursales;
  final List<CatalogoItem> turnos;

  /// Ruta real en disco de la fotografía vigente, por Empleado (Etapa
  /// 16, evolución visual) — misma fuente que el expediente
  /// (`Empleado.fotografiaAttachmentId`), resuelta en lote.
  final Map<String, String> fotografiaPathPorEmpleadoId;

  final String? texto;
  final String? puestoId;
  final DestinoFiltro? destino;
  final String? turnoId;
  final FiltroPlantilla estadoAsignacion;

  /// Clasificación de cada empleado activo, resuelta por
  /// `ObtenerPlantillaPersonalUseCase` — la MISMA fuente que consume el
  /// Dashboard. Esta pantalla no reimplementa la regla Servicio/Sucursal.
  final Map<String, ClasificacionEmpleado> clasificacionPorEmpleado;
  final String? errorCarga;

  int get personalActivo => empleados.length;

  /// Asignado = tiene destino estructural vigente, sea Servicio
  /// (operativo) o Sucursal (administrativo).
  ///
  /// Antes esto contaba `asignacionPorEmpleado`, que sólo trae
  /// Servicios: un administrativo correctamente adscrito a su Sucursal
  /// entraba al denominador sin poder entrar jamás al numerador, y el
  /// indicador no podía llegar a 100% (el bug del 94%). La regla se
  /// consume de `ObtenerPlantillaPersonalUseCase`, nunca se rehace.
  int get personalAsignado =>
      empleados.where((e) => clasificacionPorEmpleado[e.id]?.estaAsignado ?? false).length;

  /// Estrictamente los que no tienen NINGÚN destino. Un empleado con
  /// Servicio y Sucursal a la vez no cabe aquí: no le falta destino,
  /// le sobra — se cuenta en [personalInconsistente].
  int get personalSinAsignar => empleados
      .where((e) => clasificacionPorEmpleado[e.id]?.asignacion == AsignacionEstructural.sinAsignacion)
      .length;

  /// Servicio Y Sucursal simultáneamente. Se muestra sólo cuando
  /// existe, para no esconder un dato roto detrás de un porcentaje.
  int get personalInconsistente =>
      empleados.where((e) => clasificacionPorEmpleado[e.id]?.esInconsistente ?? false).length;

  double get porcentajeAsignado => personalActivo == 0 ? 0 : personalAsignado / personalActivo * 100;

  /// Etapa 15, rediseño visual — solo para que "Limpiar filtros" adquiera
  /// protagonismo cuando de verdad hay algo que limpiar; no afecta el
  /// filtrado en sí (ver [visibles]).
  bool get hayFiltrosActivos =>
      (texto != null && texto!.trim().isNotEmpty) ||
      puestoId != null ||
      destino != null ||
      turnoId != null ||
      estadoAsignacion != FiltroPlantilla.todos;

  List<EmpleadoData> get visibles {
    final textoNormalizado = texto?.trim().toLowerCase();
    return empleados.where((e) {
      if (textoNormalizado != null && textoNormalizado.isNotEmpty) {
        final coincideTexto = empleadoNombreCompleto(e).toLowerCase().contains(textoNormalizado) ||
            e.numeroEmpleado.toString().contains(textoNormalizado);
        if (!coincideTexto) return false;
      }
      if (puestoId != null && e.puestoId != puestoId) return false;
      final asignacion = asignacionPorEmpleado[e.id];
      if (turnoId != null && asignacion?.turnoId != turnoId) return false;
      // Filtro de Asignación: por tipo de destino + id real, sobre la
      // clasificación de dominio. Nunca por nombre, y nunca sólo por
      // Servicio — eso dejaba fuera a toda la plantilla administrativa.
      final destinoElegido = destino;
      if (destinoElegido != null) {
        final c = clasificacionPorEmpleado[e.id];
        switch (destinoElegido.tipo) {
          case TipoDestinoFiltro.servicio:
            if (c?.servicioId != destinoElegido.id) return false;
          case TipoDestinoFiltro.sucursal:
            if (c?.sucursalId != destinoElegido.id) return false;
          case TipoDestinoFiltro.sinAsignacion:
            if (c?.asignacion != AsignacionEstructural.sinAsignacion) return false;
        }
      }
      // La clasificación viene ya resuelta de la fuente de verdad
      // única (`ObtenerPlantillaPersonalUseCase`) — esta pantalla nunca
      // vuelve a decidir quién es operativo o administrativo.
      final clasificacion = clasificacionPorEmpleado[e.id];
      switch (estadoAsignacion) {
        case FiltroPlantilla.todos:
          break;
        case FiltroPlantilla.operativo:
          if (clasificacion?.plantilla != PlantillaPersonal.operativa) return false;
        case FiltroPlantilla.administrativo:
          if (clasificacion?.plantilla != PlantillaPersonal.administrativa) return false;
        case FiltroPlantilla.sinAsignacion:
          if (clasificacion?.asignacion != AsignacionEstructural.sinAsignacion) return false;
      }
      return true;
    }).toList();
  }

  PersonalActivoState copyWith({
    bool? cargando,
    List<EmpleadoData>? empleados,
    Map<String, AsignacionServicioData>? asignacionPorEmpleado,
    Map<String, ClasificacionEmpleado>? clasificacionPorEmpleado,
    Map<String, String>? servicioNombrePorId,
    Map<String, String>? sucursalNombrePorId,
    Map<String, String>? turnoNombrePorId,
    Map<String, String>? ubicacionPorServicioId,
    Map<String, String>? ubicacionPorSucursalId,
    List<PuestoData>? puestos,
    List<ServicioListItem>? servicios,
    List<SucursalData>? sucursales,
    List<CatalogoItem>? turnos,
    Map<String, String>? fotografiaPathPorEmpleadoId,
    String? texto,
    String? puestoId,
    DestinoFiltro? destino,
    String? turnoId,
    FiltroPlantilla? estadoAsignacion,
    bool limpiarTexto = false,
    bool limpiarPuestoId = false,
    bool limpiarDestino = false,
    bool limpiarTurnoId = false,
    String? errorCarga,
  }) {
    return PersonalActivoState(
      cargando: cargando ?? this.cargando,
      empleados: empleados ?? this.empleados,
      asignacionPorEmpleado: asignacionPorEmpleado ?? this.asignacionPorEmpleado,
      clasificacionPorEmpleado: clasificacionPorEmpleado ?? this.clasificacionPorEmpleado,
      servicioNombrePorId: servicioNombrePorId ?? this.servicioNombrePorId,
      sucursalNombrePorId: sucursalNombrePorId ?? this.sucursalNombrePorId,
      turnoNombrePorId: turnoNombrePorId ?? this.turnoNombrePorId,
      ubicacionPorServicioId: ubicacionPorServicioId ?? this.ubicacionPorServicioId,
      ubicacionPorSucursalId: ubicacionPorSucursalId ?? this.ubicacionPorSucursalId,
      puestos: puestos ?? this.puestos,
      servicios: servicios ?? this.servicios,
      sucursales: sucursales ?? this.sucursales,
      turnos: turnos ?? this.turnos,
      fotografiaPathPorEmpleadoId: fotografiaPathPorEmpleadoId ?? this.fotografiaPathPorEmpleadoId,
      texto: limpiarTexto ? null : (texto ?? this.texto),
      puestoId: limpiarPuestoId ? null : (puestoId ?? this.puestoId),
      destino: limpiarDestino ? null : (destino ?? this.destino),
      turnoId: limpiarTurnoId ? null : (turnoId ?? this.turnoId),
      estadoAsignacion: estadoAsignacion ?? this.estadoAsignacion,
      errorCarga: errorCarga,
    );
  }
}
