import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';

/// Estado del Complemento de un Pago (pedido explícito: mostrarlo en el
/// listado, no solo en el detalle) — `noAplica` cuando ninguna
/// aplicación activa exige Complemento (método distinto de PPD, o la
/// Cuenta no lo requiere); `realizado` cuando ya existe un Complemento
/// real y vigente (nunca cancelado); `pendiente` en cualquier otro
/// caso. Misma regla exacta que `pagoRequiereComplemento`/
/// `complementoPendiente` (`complemento_pago_derivado.dart`), nunca una
/// segunda lógica — este enum solo nombra el resultado para la UI.
enum EstadoComplementoPago { noAplica, pendiente, realizado }

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
    this.rangoInicio,
    this.rangoFin,
    this.estadoComplementoPorPago = const {},
    this.nombres = const NombresContraparte.vacio(),
  });

  final bool cargando;
  final List<PagoData> pagos;
  final String? errorCarga;
  final String? clienteId;
  final String? formaPago;
  final String? estatus;

  /// Filtro de periodo (Etapa 17) — opcional, sobre `Pago.fechaPago`;
  /// el repositorio ya soportaba `rangoInicio`/`rangoFin`, esta pantalla
  /// simplemente lo expone.
  final DateTime? rangoInicio;
  final DateTime? rangoFin;

  /// Por `Pago.id` — resuelto en lote en `PagosController._cargar`
  /// (todas las aplicaciones activas, todas las Cuentas por cobrar y
  /// todos los Complementos, cada uno en una sola consulta), nunca una
  /// consulta por fila.
  final Map<String, EstadoComplementoPago> estadoComplementoPorPago;

  /// Nombres ya resueltos de las contrapartes de [pagos] — Clientes y
  /// solicitantes eventuales, en lote, mismo criterio que el mapa de
  /// arriba.
  final NombresContraparte nombres;

  PagosState copyWith({
    bool? cargando,
    List<PagoData>? pagos,
    String? errorCarga,
    String? clienteId,
    String? formaPago,
    String? estatus,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool limpiarClienteId = false,
    bool limpiarFormaPago = false,
    bool limpiarEstatus = false,
    bool limpiarRango = false,
    Map<String, EstadoComplementoPago>? estadoComplementoPorPago,
    NombresContraparte? nombres,
  }) {
    return PagosState(
      cargando: cargando ?? this.cargando,
      pagos: pagos ?? this.pagos,
      errorCarga: errorCarga,
      clienteId: limpiarClienteId ? null : (clienteId ?? this.clienteId),
      formaPago: limpiarFormaPago ? null : (formaPago ?? this.formaPago),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      rangoInicio: limpiarRango ? null : (rangoInicio ?? this.rangoInicio),
      rangoFin: limpiarRango ? null : (rangoFin ?? this.rangoFin),
      estadoComplementoPorPago: estadoComplementoPorPago ?? this.estadoComplementoPorPago,
      nombres: nombres ?? this.nombres,
    );
  }
}
