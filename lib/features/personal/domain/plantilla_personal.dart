import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart' show TipoPuesto;

/// A qué plantilla PERTENECE un empleado — la estructura de la empresa
/// en la que cuenta, independientemente de si ya tiene destino.
enum PlantillaPersonal { operativa, administrativa }

/// Estado de ASIGNACIÓN estructural de un empleado activo.
///
/// Regla de negocio (fuente funcional, definida por Marlon):
/// - **Servicio** = operación que RISEG presta a un cliente
///   (Sportium Satélite, Morgan Atlacomulco, Residencial Tikal…).
/// - **Sucursal** = oficina/estructura interna propia de RISEG
///   (Sucursal Toluca).
///
/// Un elemento operativo NUNCA se adscribe a una Sucursal, y un
/// administrativo nunca ocupa una posición de Servicio. Por eso el
/// destino estructural clasifica por sí solo:
enum AsignacionEstructural {
  /// Asignación vigente a un Servicio → plantilla OPERATIVA asignada.
  servicio,

  /// Adscripción vigente a una Sucursal → plantilla ADMINISTRATIVA
  /// asignada.
  sucursal,

  /// Ni Servicio ni Sucursal. NO es un error: es un empleado activo que
  /// todavía no tiene destino. A qué plantilla pertenece lo resuelve
  /// [ClasificacionEmpleado.plantilla].
  sinAsignacion,

  /// Servicio Y Sucursal a la vez — contradice la regla de negocio.
  /// Nunca se resuelve "eligiendo uno" ni se reparte a conveniencia: se
  /// reporta como inconsistencia y se cuenta aparte.
  inconsistente,
}

/// Clasificación de UN empleado activo — puramente derivada, jamás
/// persistida. No existe ningún campo `tipoPlantilla` en `Empleado` ni
/// en `Puesto`: se resuelve en cada consulta a partir de la estructura
/// que ya existe.
class ClasificacionEmpleado {
  const ClasificacionEmpleado({
    required this.empleado,
    required this.asignacion,
    required this.plantilla,
    this.servicioId,
    this.sucursalId,
  });

  final EmpleadoData empleado;
  final AsignacionEstructural asignacion;

  /// A qué plantilla pertenece. Con destino se deduce de él; sin
  /// destino, de `Puesto.tipo` (ver [clasificarEmpleado]). `null`
  /// únicamente cuando no hay forma honesta de saberlo — un empleado
  /// sin destino Y sin puesto capturado.
  final PlantillaPersonal? plantilla;

  final String? servicioId;
  final String? sucursalId;

  bool get esOperativo => plantilla == PlantillaPersonal.operativa;
  bool get esAdministrativo => plantilla == PlantillaPersonal.administrativa;
  bool get estaAsignado =>
      asignacion == AsignacionEstructural.servicio || asignacion == AsignacionEstructural.sucursal;
  bool get esInconsistente => asignacion == AsignacionEstructural.inconsistente;
}

/// Clasifica un empleado activo. Única implementación de la regla en
/// todo el proyecto — Dashboard, Personal y Reportes la consumen, nunca
/// la reimplementan (antes había tres versiones distintas e
/// incompatibles: ver el doc comment de [PlantillaPersonalResumen]).
///
/// La ASIGNACIÓN sale siempre del destino estructural (Servicio /
/// Sucursal), tal como manda la regla de negocio. `Puesto.tipo`
/// interviene EXCLUSIVAMENTE para resolver a qué plantilla pertenece
/// alguien que todavía no tiene destino — decisión explícita de Marlon.
/// Nunca sobreescribe al destino: un empleado con puesto operativo
/// adscrito a una Sucursal es plantilla ADMINISTRATIVA, porque el
/// destino manda.
///
/// `Puesto.tipo` no se agrega para esto: es un `enum TipoPuesto
/// {operativo, administrativo}` que existe desde el inicio del proyecto
/// y ya está poblado.
ClasificacionEmpleado clasificarEmpleado({
  required EmpleadoData empleado,
  required String? servicioIdVigente,
  required TipoPuesto? tipoPuesto,
}) {
  final sucursalId = empleado.sucursalId;
  final tieneServicio = servicioIdVigente != null;
  final tieneSucursal = sucursalId != null;

  if (tieneServicio && tieneSucursal) {
    return ClasificacionEmpleado(
      empleado: empleado,
      asignacion: AsignacionEstructural.inconsistente,
      // Sin plantilla a propósito: elegir una sería exactamente la
      // "prioridad arbitraria" que la regla prohíbe inventar.
      plantilla: null,
      servicioId: servicioIdVigente,
      sucursalId: sucursalId,
    );
  }
  if (tieneServicio) {
    return ClasificacionEmpleado(
      empleado: empleado,
      asignacion: AsignacionEstructural.servicio,
      plantilla: PlantillaPersonal.operativa,
      servicioId: servicioIdVigente,
    );
  }
  if (tieneSucursal) {
    return ClasificacionEmpleado(
      empleado: empleado,
      asignacion: AsignacionEstructural.sucursal,
      plantilla: PlantillaPersonal.administrativa,
      sucursalId: sucursalId,
    );
  }
  return ClasificacionEmpleado(
    empleado: empleado,
    asignacion: AsignacionEstructural.sinAsignacion,
    plantilla: switch (tipoPuesto) {
      TipoPuesto.operativo => PlantillaPersonal.operativa,
      TipoPuesto.administrativo => PlantillaPersonal.administrativa,
      null => null,
    },
  );
}

/// Conteos de una plantilla (operativa o administrativa) — SNAPSHOT a
/// la fecha de consulta, nunca una métrica de periodo.
class ConteoPlantilla {
  const ConteoPlantilla({required this.activos, required this.asignados});

  /// Empleados activos que PERTENECEN a esta plantilla, tengan destino
  /// o no.
  final int activos;

  /// De esos, cuántos tienen destino estructural vigente.
  final int asignados;

  int get sinAsignar => activos - asignados;

  /// `100` cuando la plantilla está vacía — nunca división por cero,
  /// mismo criterio que `CoberturaServicio.porcentaje`.
  ///
  /// Clave: el denominador es la PROPIA plantilla, nunca el total de la
  /// empresa. Ese era exactamente el error del 94% (ver
  /// [PlantillaPersonalResumen]).
  double get porcentajeAsignados => activos == 0 ? 100 : (asignados / activos * 100).clamp(0, 100);
}

/// Fotografía completa de la plantilla activa — fuente de verdad única
/// de Dashboard, Personal y Reportes.
///
/// **Causa raíz que corrige (bug real del 94%).** Antes existían tres
/// clasificaciones independientes e incompatibles, y ninguna consultaba
/// las dos dimensiones a la vez:
///  - `DashboardController` calculaba `asignados / totalActivos`, donde
///    el numerador eran solo los de Servicio y el denominador TODOS los
///    activos. Un administrativo correctamente adscrito a su Sucursal
///    entraba al denominador sin poder entrar nunca al numerador, así
///    que el indicador no podía llegar a 100% ni existiendo cero
///    operativos sin asignar (caso real: MARLON, 15/16 = 93.75% ≈ 94%,
///    y "1 sin asignar" que en realidad estaba perfectamente asignado).
///  - `ObtenerResumenPersonalUseCase` (Reportes) contaba como
///    ADMINISTRATIVO a todo el que no tuviera Servicio, sin mirar
///    `sucursalId` — un empleado sin ningún destino se volvía
///    administrativo en silencio.
///  - El listado de Personal tenía su propio `filtroInicialSinAsignar`.
///
/// Aquí las poblaciones son disjuntas y suman siempre [totalActivos]:
/// `operativa.activos + administrativa.activos + inconsistentes +
/// sinPlantillaConocida`.
class PlantillaPersonalResumen {
  const PlantillaPersonalResumen({required this.clasificaciones});

  final List<ClasificacionEmpleado> clasificaciones;

  int get totalActivos => clasificaciones.length;

  ConteoPlantilla get operativa => _conteo(PlantillaPersonal.operativa);
  ConteoPlantilla get administrativa => _conteo(PlantillaPersonal.administrativa);

  ConteoPlantilla _conteo(PlantillaPersonal plantilla) {
    final propios = clasificaciones.where((c) => c.plantilla == plantilla);
    return ConteoPlantilla(
      activos: propios.length,
      asignados: propios.where((c) => c.estaAsignado).length,
    );
  }

  /// Activos sin Servicio ni Sucursal, sin importar a qué plantilla
  /// pertenezcan — la cifra que responde "¿a quién le falta destino?".
  List<ClasificacionEmpleado> get sinAsignacion =>
      clasificaciones.where((c) => c.asignacion == AsignacionEstructural.sinAsignacion).toList();

  /// Servicio Y Sucursal a la vez. Se exponen para mostrarlos, nunca
  /// para esconderlos y mejorar un porcentaje.
  List<ClasificacionEmpleado> get inconsistentes =>
      clasificaciones.where((c) => c.esInconsistente).toList();

  /// Sin destino y sin puesto capturado: no hay forma honesta de saber
  /// a qué plantilla pertenecen, así que no se inventa.
  List<ClasificacionEmpleado> get sinPlantillaConocida => clasificaciones
      .where((c) => c.plantilla == null && c.asignacion != AsignacionEstructural.inconsistente)
      .toList();

  List<ClasificacionEmpleado> deLaPlantilla(PlantillaPersonal plantilla) =>
      clasificaciones.where((c) => c.plantilla == plantilla).toList();
}
