import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

/// Estado del listado de Servicios — mismo shape que `ClientesListState`.
class ServiciosListState {
  const ServiciosListState({
    this.cargando = true,
    this.servicios = const [],
    this.errorCarga,
    this.busqueda = '',
  });

  final bool cargando;
  final List<ServicioListItem> servicios;
  final String? errorCarga;
  final String busqueda;

  /// Filtra por código, nombre, Cliente, Tipo de Servicio u
  /// observaciones — en memoria, sin volver a consultar la base de
  /// datos por cada letra tecleada (mismo patrón que
  /// `ClientesListState.clientesFiltrados`). Normaliza mayúsculas/
  /// minúsculas y espacios accidentales vía `trim()`+`toLowerCase()`.
  List<ServicioListItem> get serviciosFiltrados {
    final termino = busqueda.trim().toLowerCase();
    if (termino.isEmpty) return servicios;

    return servicios.where((item) {
      final observaciones = item.servicio.observaciones?.toLowerCase() ?? '';
      return item.servicio.codigo.toLowerCase().contains(termino) ||
          item.servicio.nombre.toLowerCase().contains(termino) ||
          item.clienteNombre.toLowerCase().contains(termino) ||
          item.tipoServicioNombre.toLowerCase().contains(termino) ||
          observaciones.contains(termino);
    }).toList();
  }

  ServiciosListState copyWith({
    bool? cargando,
    List<ServicioListItem>? servicios,
    String? errorCarga,
    String? busqueda,
  }) {
    return ServiciosListState(
      cargando: cargando ?? this.cargando,
      servicios: servicios ?? this.servicios,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}
