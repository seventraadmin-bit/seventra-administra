import 'package:riseg_one/core/database/app_database.dart';

import '../domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';

/// Una fila del listado global — el registro más los nombres ya
/// resueltos que la tabla en sí no almacena (Servicio, turno, quien
/// cubre) y el monto total (tiempo extra + costos adicionales).
class TiempoExtraResumen {
  const TiempoExtraResumen({
    required this.tiempoExtra,
    required this.servicioNombre,
    this.empleadoAusenteNombre,
    this.vacanteEtiqueta,
    required this.nombreCubre,
    required this.turnoNombre,
    required this.montoTotal,
  });

  final TiempoExtraData tiempoExtra;
  final String servicioNombre;
  /// Sólo con `origenCobertura == ausenciaEmpleado`: en una vacante
  /// no falta nadie, y en "otro" tampoco.
  final String? empleadoAusenteNombre;

  /// Sólo con `origenCobertura == vacante` — "Guardia — Nocturno".
  /// Se resuelve también para vacantes ya cubiertas: un TiempoExtra
  /// histórico debe seguir diciendo qué plaza cubrió.
  final String? vacanteEtiqueta;
  final String nombreCubre;
  final String turnoNombre;
  final int montoTotal;
}

class TiemposExtraState {
  const TiemposExtraState({
    this.cargando = true,
    this.registros = const [],
    this.resumen = const ResumenTiemposExtraDetalle(totalRegistros: 0, gastoTotal: 0, porServicio: []),
    this.servicioId,
    this.estatus,
    this.rangoInicio,
    this.rangoFin,
    this.errorCarga,
  });

  final bool cargando;
  final List<TiempoExtraResumen> registros;
  final ResumenTiemposExtraDetalle resumen;
  final String? servicioId;
  final String? estatus;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final String? errorCarga;

  TiemposExtraState copyWith({
    bool? cargando,
    List<TiempoExtraResumen>? registros,
    ResumenTiemposExtraDetalle? resumen,
    String? servicioId,
    String? estatus,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool limpiarServicioId = false,
    bool limpiarEstatus = false,
    bool limpiarRango = false,
    String? errorCarga,
  }) {
    return TiemposExtraState(
      cargando: cargando ?? this.cargando,
      registros: registros ?? this.registros,
      resumen: resumen ?? this.resumen,
      servicioId: limpiarServicioId ? null : (servicioId ?? this.servicioId),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      rangoInicio: limpiarRango ? null : (rangoInicio ?? this.rangoInicio),
      rangoFin: limpiarRango ? null : (rangoFin ?? this.rangoFin),
      errorCarga: errorCarga,
    );
  }
}
