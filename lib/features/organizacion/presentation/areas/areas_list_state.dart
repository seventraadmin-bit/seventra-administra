import 'package:riseg_one/core/database/app_database.dart';

/// Estado de la pantalla de listado de Áreas.
class AreasListState {
  const AreasListState({
    this.cargando = true,
    this.areas = const [],
    this.puestosPorArea = const {},
    this.personalPorArea = const {},
    this.errorCarga,
    this.busqueda = '',
  });

  final bool cargando;
  final List<AreaData> areas;

  /// Puestos activos por Área (`Puesto.areaId`) y Personal activo por
  /// Área (`Empleado.puestoId → Puesto.areaId`) — Etapa 16, tercera
  /// pasada visual: ambas son relaciones reales ya existentes en el
  /// esquema, agregadas en memoria sobre listados completos ya
  /// cargados una sola vez, nunca una consulta nueva por fila.
  final Map<String, int> puestosPorArea;
  final Map<String, int> personalPorArea;

  final String? errorCarga;
  final String busqueda;

  List<AreaData> get areasFiltradas {
    final termino = busqueda.trim().toLowerCase();
    if (termino.isEmpty) return areas;
    return areas.where((a) => a.codigo.toLowerCase().contains(termino) || a.nombre.toLowerCase().contains(termino)).toList();
  }

  AreasListState copyWith({
    bool? cargando,
    List<AreaData>? areas,
    Map<String, int>? puestosPorArea,
    Map<String, int>? personalPorArea,
    String? errorCarga,
    String? busqueda,
  }) {
    return AreasListState(
      cargando: cargando ?? this.cargando,
      areas: areas ?? this.areas,
      puestosPorArea: puestosPorArea ?? this.puestosPorArea,
      personalPorArea: personalPorArea ?? this.personalPorArea,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}
