import 'package:riseg_one/core/database/app_database.dart';

import 'repositories/linea_telefonica_equipo_repository.dart';

/// A quién apunta una asignación — tipo + FK, **nunca el nombre
/// mostrado**. Dos destinos son el mismo solo si coinciden en ambos:
/// un `empleadoId` y un `servicioId` que accidentalmente compartieran
/// cadena son destinos distintos, no el mismo.
enum TipoDestinoTelefonia { empleado, servicio }

class DestinoTelefonia {
  const DestinoTelefonia.empleado(this.id) : tipo = TipoDestinoTelefonia.empleado;
  const DestinoTelefonia.servicio(this.id) : tipo = TipoDestinoTelefonia.servicio;

  final TipoDestinoTelefonia tipo;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is DestinoTelefonia && other.tipo == tipo && other.id == id;

  @override
  int get hashCode => Object.hash(tipo, id);

  @override
  String toString() => '${tipo.name}:$id';
}

/// Estado de la relación entre la asignación de una Línea y la
/// custodia física del equipo que la trae, en Inventario.
///
/// Es la ÚNICA clasificación del proyecto para esta pregunta: los casos
/// de uso que podrían producir una contradicción y la pantalla que la
/// muestra leen de aquí, para que "qué cuenta como incoherente" no se
/// decida por separado en cada sitio.
enum EstadoCoherenciaLineaEquipo {
  /// La línea no trae equipo. No hay nada que comparar — una SIM suelta
  /// es un estado perfectamente válido (§5).
  sinEquipo,

  /// Ambos sin destino, o ambos con el MISMO destino (§6, §9).
  coherente,

  /// El equipo está bajo custodia de alguien y la línea no está
  /// asignada — el caso real de MILOYILE (§7).
  lineaSinAsignacion,

  /// Mismo dibujo que [lineaSinAsignacion] —línea sin asignar, equipo
  /// en manos de alguien— pero por una razón legítima: la persona
  /// causó baja, su línea se liberó y el aparato quedó declarado
  /// `pendienteRecuperacionDesde` en la conciliación.
  ///
  /// **No es una inconsistencia.** Son dos ciclos de vida distintos
  /// avanzando correctamente, y forzarlos a coincidir sería inventar
  /// una asignación de línea a alguien que ya no trabaja aquí.
  equipoPendienteRecuperacion,

  /// La línea está asignada y el equipo no tiene custodia en
  /// Inventario. Asociar un teléfono NO significa que se entregó
  /// físicamente: Inventario manda (§8).
  equipoSinCustodia,

  /// Los dos tienen destino y no es el mismo (§10).
  destinosDistintos,
}

/// Resultado de evaluar la coherencia, con los dos destinos reales para
/// que quien la muestre no tenga que volver a consultarlos.
class CoherenciaLineaEquipo {
  const CoherenciaLineaEquipo({
    required this.estado,
    this.unidadId,
    this.destinoLinea,
    this.destinoEquipo,
    this.pendienteRecuperacionDesde,
  });

  final EstadoCoherenciaLineaEquipo estado;

  /// La unidad de Inventario asociada, cuando la hay.
  final String? unidadId;

  /// Destino vigente de la asignación de Línea.
  final DestinoTelefonia? destinoLinea;

  /// Custodia vigente del equipo en Inventario.
  final DestinoTelefonia? destinoEquipo;

  /// Desde cuándo el aparato está declarado pendiente de recuperación,
  /// cuando ése es el estado.
  final DateTime? pendienteRecuperacionDesde;

  /// Nada que explicar ni que corregir.
  bool get esCoherente =>
      estado == EstadoCoherenciaLineaEquipo.sinEquipo ||
      estado == EstadoCoherenciaLineaEquipo.coherente;

  /// Estado esperado, no error: hay que informarlo, no corregirlo.
  bool get esPendienteRecuperacion =>
      estado == EstadoCoherenciaLineaEquipo.equipoPendienteRecuperacion;

  /// Contradicción real que alguien tiene que resolver.
  bool get esInconsistencia => !esCoherente && !esPendienteRecuperacion;
}

/// La regla. Función pura: sin I/O, sin repositorios, sin fechas — todo
/// lo que necesita ya viene resuelto. Así una pantalla, un caso de uso
/// y una prueba la evalúan exactamente igual.
/// [pendienteRecuperacionDesde] es la marca real de Inventario sobre la
/// custodia vigente; sólo cambia la lectura del caso "línea sin
/// asignar + equipo custodiado".
CoherenciaLineaEquipo evaluarCoherenciaLineaEquipo({
  required String? unidadId,
  required DestinoTelefonia? destinoLinea,
  required DestinoTelefonia? destinoEquipo,
  DateTime? pendienteRecuperacionDesde,
}) {
  if (unidadId == null) {
    return CoherenciaLineaEquipo(
      estado: EstadoCoherenciaLineaEquipo.sinEquipo,
      destinoLinea: destinoLinea,
    );
  }

  final EstadoCoherenciaLineaEquipo estado;
  if (destinoLinea == null && destinoEquipo == null) {
    estado = EstadoCoherenciaLineaEquipo.coherente;
  } else if (destinoLinea == null) {
    estado = pendienteRecuperacionDesde != null
        ? EstadoCoherenciaLineaEquipo.equipoPendienteRecuperacion
        : EstadoCoherenciaLineaEquipo.lineaSinAsignacion;
  } else if (destinoEquipo == null) {
    estado = EstadoCoherenciaLineaEquipo.equipoSinCustodia;
  } else if (destinoLinea == destinoEquipo) {
    estado = EstadoCoherenciaLineaEquipo.coherente;
  } else {
    estado = EstadoCoherenciaLineaEquipo.destinosDistintos;
  }

  return CoherenciaLineaEquipo(
    estado: estado,
    unidadId: unidadId,
    destinoLinea: destinoLinea,
    destinoEquipo: destinoEquipo,
    pendienteRecuperacionDesde: pendienteRecuperacionDesde,
  );
}

/// El destino de una asignación de Línea vigente. `null` si no hay
/// asignación o si ya está cerrada.
DestinoTelefonia? destinoDeAsignacionLinea(AsignacionLineaTelefonicaData? asignacion) {
  if (asignacion == null || asignacion.fechaTermino != null) return null;
  return destinoDe(empleadoId: asignacion.empleadoId, servicioId: asignacion.servicioId);
}

/// El destino de la custodia vigente de una unidad en Inventario.
DestinoTelefonia? destinoDeCustodia(CustodiaInventarioLineaTelefonica? custodia) {
  if (custodia == null) return null;
  return destinoDe(empleadoId: custodia.empleadoId, servicioId: custodia.servicioId);
}

/// Empleado | Servicio, exclusivos. Si vinieran los dos —algo que el
/// `CHECK` de ambas tablas impide— gana la ausencia de destino antes
/// que inventar uno.
DestinoTelefonia? destinoDe({String? empleadoId, String? servicioId}) {
  final tieneEmpleado = (empleadoId ?? '').isNotEmpty;
  final tieneServicio = (servicioId ?? '').isNotEmpty;
  if (tieneEmpleado == tieneServicio) return null;
  return tieneEmpleado
      ? DestinoTelefonia.empleado(empleadoId!)
      : DestinoTelefonia.servicio(servicioId!);
}

/// Qué pasaría si la asignación de la línea pasara a [destinoPropuesto]
/// (`null` = retirarla), con el equipo y la custodia que hay hoy.
///
/// Es la guardia común de Asignar / Cambiar asignación / Retirar
/// asignación: las tres permiten exactamente lo mismo —terminar
/// coherente— y ninguna decide por su cuenta qué significa eso.
class CambioAsignacionLinea {
  const CambioAsignacionLinea({required this.antes, required this.despues});

  /// Coherencia con la asignación vigente, antes de tocar nada.
  final CoherenciaLineaEquipo antes;

  /// Coherencia que quedaría si la operación se aplicara.
  final CoherenciaLineaEquipo despues;

  /// La operación NO deja la línea y su equipo en un estado limpio: hay
  /// que rechazarla ANTES de persistir. Incluye el pendiente de
  /// recuperación: mientras el aparato siga sin recuperarse, la línea
  /// no se reasigna (y jamás se le asigna al ex-empleado).
  bool get dejariaContradiccion => !despues.esCoherente;

  /// Venía roto y queda bien: no es una operación cotidiana sino la
  /// corrección administrativa de una inconsistencia histórica — exige
  /// motivo y queda auditada (§22). Un pendiente de recuperación NO
  /// cuenta: ahí no hay nada que corregir.
  bool get esResolucionDeInconsistencia => antes.esInconsistencia && despues.esCoherente;
}

CambioAsignacionLinea evaluarCambioAsignacionLinea({
  required String? unidadId,
  required DestinoTelefonia? destinoLineaActual,
  required DestinoTelefonia? destinoEquipo,
  required DestinoTelefonia? destinoPropuesto,
  DateTime? pendienteRecuperacionDesde,
}) {
  return CambioAsignacionLinea(
    antes: evaluarCoherenciaLineaEquipo(
      unidadId: unidadId,
      destinoLinea: destinoLineaActual,
      destinoEquipo: destinoEquipo,
      pendienteRecuperacionDesde: pendienteRecuperacionDesde,
    ),
    despues: evaluarCoherenciaLineaEquipo(
      unidadId: unidadId,
      destinoLinea: destinoPropuesto,
      destinoEquipo: destinoEquipo,
      pendienteRecuperacionDesde: pendienteRecuperacionDesde,
    ),
  );
}
