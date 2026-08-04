import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';

/// Estado de la pantalla de listado de Sucursales.
class SucursalesListState {
  const SucursalesListState({
    this.cargando = true,
    this.sucursales = const [],
    this.tipos = const [],
    this.errorCarga,
    this.busqueda = '',
  });

  final bool cargando;
  final List<SucursalData> sucursales;

  /// Catálogo de Tipo de Sucursal — necesario para mostrar el nombre (no
  /// el id) en la tabla y para que el buscador también filtre por tipo.
  final List<CatalogoItem> tipos;

  final String? errorCarga;
  final String busqueda;

  String? nombreTipo(String tipoSucursalId) {
    for (final tipo in tipos) {
      if (tipo.id == tipoSucursalId) return tipo.nombre;
    }
    return null;
  }

  /// Filtra por código, nombre o nombre de tipo — en memoria, sin volver
  /// a consultar la base de datos por cada letra tecleada.
  List<SucursalData> get sucursalesFiltradas {
    final termino = busqueda.trim().toLowerCase();
    if (termino.isEmpty) return sucursales;

    return sucursales.where((s) {
      final tipoNombre = nombreTipo(s.tipoSucursalId)?.toLowerCase() ?? '';
      return s.codigo.toLowerCase().contains(termino) ||
          s.nombre.toLowerCase().contains(termino) ||
          tipoNombre.contains(termino);
    }).toList();
  }

  SucursalesListState copyWith({
    bool? cargando,
    List<SucursalData>? sucursales,
    List<CatalogoItem>? tipos,
    String? errorCarga,
    String? busqueda,
  }) {
    return SucursalesListState(
      cargando: cargando ?? this.cargando,
      sucursales: sucursales ?? this.sucursales,
      tipos: tipos ?? this.tipos,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}
