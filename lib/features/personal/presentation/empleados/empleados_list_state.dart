import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Empleados (Etapa 5A) — mismo shape que
/// `IngresosState`.
class EmpleadosListState {
  const EmpleadosListState({
    this.cargando = true,
    this.empleados = const [],
    this.errorCarga,
    this.estatus,
    this.puestoId,
  });

  final bool cargando;
  final List<EmpleadoData> empleados;
  final String? errorCarga;
  final String? estatus;
  final String? puestoId;

  EmpleadosListState copyWith({
    bool? cargando,
    List<EmpleadoData>? empleados,
    String? errorCarga,
    String? estatus,
    String? puestoId,
    bool limpiarEstatus = false,
    bool limpiarPuestoId = false,
  }) {
    return EmpleadosListState(
      cargando: cargando ?? this.cargando,
      empleados: empleados ?? this.empleados,
      errorCarga: errorCarga,
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      puestoId: limpiarPuestoId ? null : (puestoId ?? this.puestoId),
    );
  }
}
