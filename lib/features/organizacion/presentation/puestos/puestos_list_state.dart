import 'package:riseg_one/core/database/app_database.dart';

/// Estado de la pantalla de listado de Puestos.
class PuestosListState {
  const PuestosListState({
    this.cargando = true,
    this.puestos = const [],
    this.areas = const [],
    this.errorCarga,
    this.busqueda = '',
  });

  final bool cargando;
  final List<PuestoData> puestos;

  /// Necesario para mostrar el nombre de Área (no el id) en la tabla y
  /// para que el buscador también filtre por nombre de área.
  final List<AreaData> areas;

  final String? errorCarga;
  final String busqueda;

  String? nombreArea(String areaId) {
    for (final area in areas) {
      if (area.id == areaId) return area.nombre;
    }
    return null;
  }

  /// Filtra por código, nombre, área, tipo o descripción — en memoria,
  /// sin volver a consultar la base de datos por cada letra tecleada.
  ///
  /// El tipo se compara contra su valor crudo (`operativo`/
  /// `administrativo`, ya palabras en español legibles) para no
  /// necesitar `AppLocalizations` dentro de un objeto de estado puro —
  /// la etiqueta visible en la tabla sí pasa por l10n, en el widget.
  List<PuestoData> get puestosFiltrados {
    final termino = busqueda.trim().toLowerCase();
    if (termino.isEmpty) return puestos;

    return puestos.where((p) {
      final areaNombre = nombreArea(p.areaId)?.toLowerCase() ?? '';
      final descripcion = p.descripcion?.toLowerCase() ?? '';
      return p.codigo.toLowerCase().contains(termino) ||
          p.nombre.toLowerCase().contains(termino) ||
          areaNombre.contains(termino) ||
          p.tipo.toLowerCase().contains(termino) ||
          descripcion.contains(termino);
    }).toList();
  }

  PuestosListState copyWith({
    bool? cargando,
    List<PuestoData>? puestos,
    List<AreaData>? areas,
    String? errorCarga,
    String? busqueda,
  }) {
    return PuestosListState(
      cargando: cargando ?? this.cargando,
      puestos: puestos ?? this.puestos,
      areas: areas ?? this.areas,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}
