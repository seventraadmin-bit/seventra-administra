import 'package:riseg_one/core/database/app_database.dart';

/// Identidad mínima de la tarjeta que financió una Compra (Etapa 19B) —
/// solo lo necesario para la celda "Forma de pago"/"Financiamiento",
/// nunca la `DeudaData` completa (evita acoplar esta pantalla al
/// esquema interno de Deudas).
typedef TarjetaCompra = ({String deudaId, String nombre, String? ultimosDigitos});

/// Estado del listado de Compras (Etapa 10) — filtros combinables
/// (rango de fechas, folio, proveedor, artículo, estatus, forma de
/// pago) + resumen KPI (Etapa 19) derivado siempre de `compras`/
/// `totalesPorCompra`/`articulosPorCompra` ya cargados — nunca una
/// consulta nueva por indicador.
class ComprasState {
  const ComprasState({
    this.cargando = true,
    this.compras = const [],
    this.totalesPorCompra = const {},
    this.articulosPorCompra = const {},
    this.tarjetaPorCompra = const {},
    this.errorCarga,
    this.desde,
    this.hasta,
    this.folio,
    this.proveedor,
    this.articuloId,
    this.estatus,
    this.formaPago,
  });

  final bool cargando;
  final List<CompraData> compras;
  final Map<String, int> totalesPorCompra;

  /// Renglones `destino == inventario` de cada Compra — `articuloId` +
  /// `cantidad`, ver el doc comment de
  /// `CompraRepository.listarArticulosPorCompra`. El nombre del
  /// Artículo se resuelve en la pantalla contra el catálogo ya
  /// cargado, nunca aquí.
  final Map<String, List<({String articuloId, int cantidad})>> articulosPorCompra;

  /// Etapa 19B — tarjeta que financió cada Compra con `formaPago ==
  /// tarjeta`, llave = `Compra.id` (nunca `deudaId`, para no requerir
  /// un segundo mapeo al pintar la fila). Ausente para toda Compra
  /// pagada de contado.
  final Map<String, TarjetaCompra> tarjetaPorCompra;
  final String? errorCarga;
  final DateTime? desde;
  final DateTime? hasta;
  final String? folio;
  final String? proveedor;
  final String? articuloId;
  final String? estatus;
  final String? formaPago;

  bool get hayFiltrosActivos =>
      desde != null ||
      hasta != null ||
      (folio != null && folio!.trim().isNotEmpty) ||
      (proveedor != null && proveedor!.trim().isNotEmpty) ||
      articuloId != null ||
      estatus != null ||
      formaPago != null;

  /// = cantidad de registros `Compra` actualmente cargados (ya
  /// filtrados) — nunca una suma de partidas ni de unidades.
  int get resumenComprasDelPeriodo => compras.length;

  /// Suma de `totalesPorCompra` de las Compras `registrada` visibles —
  /// excluye `cancelada` sin importar el filtro de Estatus aplicado
  /// (mismo criterio conservador que ya usaba
  /// `CompraRepository.totalCompradoEnRango`: una compra cancelada no
  /// es dinero realmente gastado).
  int get resumenTotalComprado {
    var total = 0;
    for (final c in compras) {
      if (c.estatus != 'registrada') continue;
      total += totalesPorCompra[c.id] ?? 0;
    }
    return total;
  }

  /// Suma de cantidades en renglones `destino == inventario` de todas
  /// las Compras visibles — NO el número de Compras, NO el número de
  /// Artículos distintos (ver el doc comment de
  /// `CompraRepository.listarArticulosPorCompra`).
  int get resumenArticulosAdquiridos =>
      articulosPorCompra.values.fold(0, (s, renglones) => s + renglones.fold(0, (s2, r) => s2 + r.cantidad));

  /// Proveedores/establecimientos distintos entre las Compras visibles
  /// — `proveedor` es texto libre (sin catálogo), así que la regla de
  /// "distinto" es una normalización simple en memoria: recortar
  /// espacios y pasar a minúsculas antes de comparar. Nunca cuenta
  /// valores vacíos/nulos.
  int get resumenProveedoresDistintos {
    final normalizados = <String>{};
    for (final c in compras) {
      final p = (c.proveedor ?? '').trim().toLowerCase();
      if (p.isNotEmpty) normalizados.add(p);
    }
    return normalizados.length;
  }

  ComprasState copyWith({
    bool? cargando,
    List<CompraData>? compras,
    Map<String, int>? totalesPorCompra,
    Map<String, List<({String articuloId, int cantidad})>>? articulosPorCompra,
    Map<String, TarjetaCompra>? tarjetaPorCompra,
    String? errorCarga,
    DateTime? desde,
    DateTime? hasta,
    String? folio,
    String? proveedor,
    String? articuloId,
    String? estatus,
    String? formaPago,
    bool limpiarDesde = false,
    bool limpiarHasta = false,
    bool limpiarFolio = false,
    bool limpiarProveedor = false,
    bool limpiarArticuloId = false,
    bool limpiarEstatus = false,
    bool limpiarFormaPago = false,
  }) {
    return ComprasState(
      cargando: cargando ?? this.cargando,
      compras: compras ?? this.compras,
      totalesPorCompra: totalesPorCompra ?? this.totalesPorCompra,
      articulosPorCompra: articulosPorCompra ?? this.articulosPorCompra,
      tarjetaPorCompra: tarjetaPorCompra ?? this.tarjetaPorCompra,
      errorCarga: errorCarga,
      desde: limpiarDesde ? null : (desde ?? this.desde),
      hasta: limpiarHasta ? null : (hasta ?? this.hasta),
      folio: limpiarFolio ? null : (folio ?? this.folio),
      proveedor: limpiarProveedor ? null : (proveedor ?? this.proveedor),
      articuloId: limpiarArticuloId ? null : (articuloId ?? this.articuloId),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      formaPago: limpiarFormaPago ? null : (formaPago ?? this.formaPago),
    );
  }
}
