import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Ingresos (Etapa 4K.1) — mismo shape que
/// `PagosState`.
class IngresosState {
  const IngresosState({
    this.cargando = true,
    this.ingresos = const [],
    this.errorCarga,
    this.estatus,
    this.servicioId,
  });

  final bool cargando;
  final List<IngresoData> ingresos;
  final String? errorCarga;
  final String? estatus;
  final String? servicioId;

  IngresosState copyWith({
    bool? cargando,
    List<IngresoData>? ingresos,
    String? errorCarga,
    String? estatus,
    String? servicioId,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
  }) {
    return IngresosState(
      cargando: cargando ?? this.cargando,
      ingresos: ingresos ?? this.ingresos,
      errorCarga: errorCarga,
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      servicioId: limpiarServicioId ? null : (servicioId ?? this.servicioId),
    );
  }
}
