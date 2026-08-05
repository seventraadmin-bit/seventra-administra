import 'package:riseg_one/core/database/app_database.dart';

/// Estado de la pantalla de listado de Clientes comerciales.
class ClientesListState {
  const ClientesListState({
    this.cargando = true,
    this.clientes = const [],
    this.errorCarga,
    this.busqueda = '',
  });

  final bool cargando;
  final List<ClienteData> clientes;
  final String? errorCarga;
  final String busqueda;

  /// Filtra por código, nombre comercial u observaciones — en memoria,
  /// sin volver a consultar la base de datos por cada letra tecleada.
  List<ClienteData> get clientesFiltrados {
    final termino = busqueda.trim().toLowerCase();
    if (termino.isEmpty) return clientes;

    return clientes.where((c) {
      final observaciones = c.observaciones?.toLowerCase() ?? '';
      return c.codigo.toLowerCase().contains(termino) ||
          c.nombreComercial.toLowerCase().contains(termino) ||
          observaciones.contains(termino);
    }).toList();
  }

  ClientesListState copyWith({
    bool? cargando,
    List<ClienteData>? clientes,
    String? errorCarga,
    String? busqueda,
  }) {
    return ClientesListState(
      cargando: cargando ?? this.cargando,
      clientes: clientes ?? this.clientes,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}
