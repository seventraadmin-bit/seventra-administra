import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Vehículos (Etapa 8A) — mismo shape que
/// `ArticulosState` en Inventario.
class VehiculosState {
  const VehiculosState({this.cargando = true, this.vehiculos = const [], this.errorCarga});

  final bool cargando;
  final List<VehiculoData> vehiculos;
  final String? errorCarga;

  VehiculosState copyWith({bool? cargando, List<VehiculoData>? vehiculos, String? errorCarga}) {
    return VehiculosState(
      cargando: cargando ?? this.cargando,
      vehiculos: vehiculos ?? this.vehiculos,
      errorCarga: errorCarga,
    );
  }
}
