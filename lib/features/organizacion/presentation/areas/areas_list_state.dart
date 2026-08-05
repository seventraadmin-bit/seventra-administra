import 'package:riseg_one/core/database/app_database.dart';

/// Estado de la pantalla de listado de Áreas — sin buscador (el alcance
/// aprobado no lo pide para Áreas, a diferencia de Puestos).
class AreasListState {
  const AreasListState({this.cargando = true, this.areas = const [], this.errorCarga});

  final bool cargando;
  final List<AreaData> areas;
  final String? errorCarga;

  AreasListState copyWith({bool? cargando, List<AreaData>? areas, String? errorCarga}) {
    return AreasListState(
      cargando: cargando ?? this.cargando,
      areas: areas ?? this.areas,
      errorCarga: errorCarga,
    );
  }
}
