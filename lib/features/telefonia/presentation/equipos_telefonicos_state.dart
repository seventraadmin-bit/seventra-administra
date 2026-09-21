import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Equipos telefónicos (Etapa 9D, corrección de
/// invalidación) — "Equipo" nunca es una tabla propia, es una vista
/// compuesta sobre `ArticuloUnidad`/`ArticuloUnidadTelefono`
/// (Inventario) + `LineaTelefonicaEquipo`/`Asignacion`; este estado es
/// el snapshot ya ensamblado que consume `EquiposTelefonicosListScreen`.
class EquiposTelefonicosState {
  const EquiposTelefonicosState({
    this.cargando = true,
    this.unidades = const [],
    this.telefonoPorUnidad = const {},
    this.lineaPorUnidad = const {},
    this.asignacionPorUnidad = const {},
    this.empleadosPorId = const {},
    this.serviciosPorId = const {},
    this.errorCarga,
  });

  final bool cargando;
  final List<ArticuloUnidadData> unidades;
  final Map<String, ArticuloUnidadTelefonoData> telefonoPorUnidad;
  final Map<String, LineaTelefonicaData> lineaPorUnidad;
  final Map<String, AsignacionData> asignacionPorUnidad;
  final Map<String, String> empleadosPorId;
  final Map<String, String> serviciosPorId;
  final String? errorCarga;

  EquiposTelefonicosState copyWith({
    bool? cargando,
    List<ArticuloUnidadData>? unidades,
    Map<String, ArticuloUnidadTelefonoData>? telefonoPorUnidad,
    Map<String, LineaTelefonicaData>? lineaPorUnidad,
    Map<String, AsignacionData>? asignacionPorUnidad,
    Map<String, String>? empleadosPorId,
    Map<String, String>? serviciosPorId,
    String? errorCarga,
  }) {
    return EquiposTelefonicosState(
      cargando: cargando ?? this.cargando,
      unidades: unidades ?? this.unidades,
      telefonoPorUnidad: telefonoPorUnidad ?? this.telefonoPorUnidad,
      lineaPorUnidad: lineaPorUnidad ?? this.lineaPorUnidad,
      asignacionPorUnidad: asignacionPorUnidad ?? this.asignacionPorUnidad,
      empleadosPorId: empleadosPorId ?? this.empleadosPorId,
      serviciosPorId: serviciosPorId ?? this.serviciosPorId,
      errorCarga: errorCarga,
    );
  }
}
