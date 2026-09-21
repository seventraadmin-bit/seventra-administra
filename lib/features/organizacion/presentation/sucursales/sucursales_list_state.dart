import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';

/// Estado de la pantalla de listado de Sucursales.
class SucursalesListState {
  const SucursalesListState({
    this.cargando = true,
    this.sucursales = const [],
    this.tipos = const [],
    this.direccionPorSucursalId = const {},
    this.personalPorSucursal = const {},
    this.serviciosPorSucursal = const {},
    this.errorCarga,
    this.busqueda = '',
  });

  final bool cargando;
  final List<SucursalData> sucursales;

  /// Catálogo de Tipo de Sucursal — necesario para mostrar el nombre (no
  /// el id) en la tabla y para que el buscador también filtre por tipo.
  final List<CatalogoItem> tipos;

  /// Dirección principal por Sucursal (Etapa 16, tercera pasada visual)
  /// — resuelta en una sola consulta en lote, nunca una por tarjeta.
  final Map<String, DireccionData> direccionPorSucursalId;

  /// Personal activo (`Empleado.sucursalId`) y Servicios activos
  /// (`Servicio.sucursalAdministrativaId`) por Sucursal — relaciones
  /// reales ya existentes en el esquema, agregadas en memoria a partir
  /// de los listados completos ya cargados (nunca una consulta nueva
  /// por Sucursal). Sin relación real Sucursal↔Área en el esquema
  /// actual, ese tercer contador del pedido se omite (documentado en
  /// el reporte final).
  final Map<String, int> personalPorSucursal;
  final Map<String, int> serviciosPorSucursal;

  final String? errorCarga;
  final String busqueda;

  String? nombreTipo(String tipoSucursalId) {
    for (final tipo in tipos) {
      if (tipo.id == tipoSucursalId) return tipo.nombre;
    }
    return null;
  }

  /// "Municipio, Estado" de la dirección principal — `null` si no hay
  /// ninguna capturada (la tarjeta muestra "No registrada" en ese
  /// caso, nunca una ubicación inferida).
  String? ubicacionDe(String sucursalId) {
    final d = direccionPorSucursalId[sucursalId];
    if (d == null) return null;
    return '${d.municipioAlcaldia}, ${d.estado}';
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
    Map<String, DireccionData>? direccionPorSucursalId,
    Map<String, int>? personalPorSucursal,
    Map<String, int>? serviciosPorSucursal,
    String? errorCarga,
    String? busqueda,
  }) {
    return SucursalesListState(
      cargando: cargando ?? this.cargando,
      sucursales: sucursales ?? this.sucursales,
      tipos: tipos ?? this.tipos,
      direccionPorSucursalId: direccionPorSucursalId ?? this.direccionPorSucursalId,
      personalPorSucursal: personalPorSucursal ?? this.personalPorSucursal,
      serviciosPorSucursal: serviciosPorSucursal ?? this.serviciosPorSucursal,
      errorCarga: errorCarga,
      busqueda: busqueda ?? this.busqueda,
    );
  }
}
