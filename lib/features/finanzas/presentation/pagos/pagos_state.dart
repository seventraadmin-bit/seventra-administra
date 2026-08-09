import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Pagos (Etapa 4J.2) — mismo shape que
/// `CuentasPorCobrarState`.
class PagosState {
  const PagosState({
    this.cargando = true,
    this.pagos = const [],
    this.errorCarga,
    this.clienteId,
    this.formaPago,
    this.estatus,
  });

  final bool cargando;
  final List<PagoData> pagos;
  final String? errorCarga;
  final String? clienteId;
  final String? formaPago;
  final String? estatus;

  PagosState copyWith({
    bool? cargando,
    List<PagoData>? pagos,
    String? errorCarga,
    String? clienteId,
    String? formaPago,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarFormaPago = false,
    bool limpiarEstatus = false,
  }) {
    return PagosState(
      cargando: cargando ?? this.cargando,
      pagos: pagos ?? this.pagos,
      errorCarga: errorCarga,
      clienteId: limpiarClienteId ? null : (clienteId ?? this.clienteId),
      formaPago: limpiarFormaPago ? null : (formaPago ?? this.formaPago),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
    );
  }
}
