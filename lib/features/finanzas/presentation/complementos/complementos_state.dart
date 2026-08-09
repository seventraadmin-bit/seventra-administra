import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Complementos de pago (Etapa 4J.3) — mismo
/// shape que `PagosState`.
class ComplementosState {
  const ComplementosState({
    this.cargando = true,
    this.complementos = const [],
    this.errorCarga,
    this.clienteId,
    this.estatus,
  });

  final bool cargando;
  final List<ComplementoPagoData> complementos;
  final String? errorCarga;
  final String? clienteId;
  final String? estatus;

  ComplementosState copyWith({
    bool? cargando,
    List<ComplementoPagoData>? complementos,
    String? errorCarga,
    String? clienteId,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarEstatus = false,
  }) {
    return ComplementosState(
      cargando: cargando ?? this.cargando,
      complementos: complementos ?? this.complementos,
      errorCarga: errorCarga,
      clienteId: limpiarClienteId ? null : (clienteId ?? this.clienteId),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
    );
  }
}
