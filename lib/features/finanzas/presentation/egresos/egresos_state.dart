import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Egresos (Etapa 4K.1) — mismo shape que
/// `IngresosState`.
class EgresosState {
  const EgresosState({
    this.cargando = true,
    this.egresos = const [],
    this.errorCarga,
    this.estatus,
    this.servicioId,
  });

  final bool cargando;
  final List<EgresoData> egresos;
  final String? errorCarga;
  final String? estatus;
  final String? servicioId;

  EgresosState copyWith({
    bool? cargando,
    List<EgresoData>? egresos,
    String? errorCarga,
    String? estatus,
    String? servicioId,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
  }) {
    return EgresosState(
      cargando: cargando ?? this.cargando,
      egresos: egresos ?? this.egresos,
      errorCarga: errorCarga,
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      servicioId: limpiarServicioId ? null : (servicioId ?? this.servicioId),
    );
  }
}
