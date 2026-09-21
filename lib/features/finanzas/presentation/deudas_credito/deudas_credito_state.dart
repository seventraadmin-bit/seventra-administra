import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Deudas y crédito (Etapa 19) — mismo shape que
/// `CuentasPorCobrarState`. Filtros por tipo/estatus/búsqueda se
/// resuelven server-side (`DeudaRepository.listar`).
class DeudasCreditoState {
  const DeudasCreditoState({
    this.cargando = true,
    this.deudas = const [],
    this.pagadoPorDeudaId = const {},
    this.errorCarga,
    this.tipo,
    this.estatus,
    this.busqueda,
  });

  final bool cargando;
  final List<DeudaData> deudas;

  /// Suma de `MovimientoDeuda` tipo `pago` por Deuda — fuente única de
  /// "Pagado" (nunca `importeOriginal - saldoActual`, ver el doc
  /// comment de `DeudaRepository.totalPagadoPorDeuda`).
  final Map<String, int> pagadoPorDeudaId;

  final String? errorCarga;
  final String? tipo;
  final String? estatus;
  final String? busqueda;

  DeudasCreditoState copyWith({
    bool? cargando,
    List<DeudaData>? deudas,
    Map<String, int>? pagadoPorDeudaId,
    String? errorCarga,
    String? tipo,
    String? estatus,
    String? busqueda,
    bool limpiarTipo = false,
    bool limpiarEstatus = false,
    bool limpiarBusqueda = false,
  }) {
    return DeudasCreditoState(
      cargando: cargando ?? this.cargando,
      deudas: deudas ?? this.deudas,
      pagadoPorDeudaId: pagadoPorDeudaId ?? this.pagadoPorDeudaId,
      errorCarga: errorCarga,
      tipo: limpiarTipo ? null : (tipo ?? this.tipo),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      busqueda: limpiarBusqueda ? null : (busqueda ?? this.busqueda),
    );
  }
}
