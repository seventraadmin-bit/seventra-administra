import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Compras (Etapa 10) — filtros combinables
/// (rango de fechas, folio, proveedor, artículo, estatus) + el total
/// comprado dentro del rango consultado, siempre derivado (nunca
/// guardado), mismo criterio que `EgresosState`.
class ComprasState {
  const ComprasState({
    this.cargando = true,
    this.compras = const [],
    this.totalesPorCompra = const {},
    this.totalRango = 0,
    this.errorCarga,
    this.desde,
    this.hasta,
    this.folio,
    this.proveedor,
    this.articuloId,
    this.estatus,
  });

  final bool cargando;
  final List<CompraData> compras;
  final Map<String, int> totalesPorCompra;
  final int totalRango;
  final String? errorCarga;
  final DateTime? desde;
  final DateTime? hasta;
  final String? folio;
  final String? proveedor;
  final String? articuloId;
  final String? estatus;

  ComprasState copyWith({
    bool? cargando,
    List<CompraData>? compras,
    Map<String, int>? totalesPorCompra,
    int? totalRango,
    String? errorCarga,
    DateTime? desde,
    DateTime? hasta,
    String? folio,
    String? proveedor,
    String? articuloId,
    String? estatus,
    bool limpiarDesde = false,
    bool limpiarHasta = false,
    bool limpiarFolio = false,
    bool limpiarProveedor = false,
    bool limpiarArticuloId = false,
    bool limpiarEstatus = false,
  }) {
    return ComprasState(
      cargando: cargando ?? this.cargando,
      compras: compras ?? this.compras,
      totalesPorCompra: totalesPorCompra ?? this.totalesPorCompra,
      totalRango: totalRango ?? this.totalRango,
      errorCarga: errorCarga,
      desde: limpiarDesde ? null : (desde ?? this.desde),
      hasta: limpiarHasta ? null : (hasta ?? this.hasta),
      folio: limpiarFolio ? null : (folio ?? this.folio),
      proveedor: limpiarProveedor ? null : (proveedor ?? this.proveedor),
      articuloId: limpiarArticuloId ? null : (articuloId ?? this.articuloId),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
    );
  }
}
