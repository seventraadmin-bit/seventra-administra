import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';

/// Estado del listado de Cuentas por cobrar (Etapa 4J.1) — mismo shape
/// que `AgendaState`, con filtros propios. Sin rango de fechas: a
/// diferencia de la Agenda, aquí no hay una ventana temporal por
/// defecto (§13 del plan: la consulta principal es por
/// Cliente/estatus/vencidas, no por periodo).
class CuentasPorCobrarState {
  const CuentasPorCobrarState({
    this.cargando = true,
    this.cuentas = const [],
    this.errorCarga,
    this.clienteId,
    this.estatus,
    this.soloVencidas = false,
    this.nombres = const NombresContraparte.vacio(),
  });

  final bool cargando;
  final List<CuentaPorCobrarData> cuentas;
  final String? errorCarga;
  final String? clienteId;
  final String? estatus;
  final bool soloVencidas;

  /// Nombres ya resueltos de las contrapartes de [cuentas] — Clientes y
  /// solicitantes eventuales. Se resuelven en el controlador, en lote,
  /// para que la tabla nunca dispare una consulta por renglón.
  final NombresContraparte nombres;

  CuentasPorCobrarState copyWith({
    bool? cargando,
    List<CuentaPorCobrarData>? cuentas,
    String? errorCarga,
    String? clienteId,
    String? estatus,
    bool? soloVencidas,
    NombresContraparte? nombres,
    bool limpiarClienteId = false,
    bool limpiarEstatus = false,
  }) {
    return CuentasPorCobrarState(
      cargando: cargando ?? this.cargando,
      cuentas: cuentas ?? this.cuentas,
      errorCarga: errorCarga,
      clienteId: limpiarClienteId ? null : (clienteId ?? this.clienteId),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      soloVencidas: soloVencidas ?? this.soloVencidas,
      nombres: nombres ?? this.nombres,
    );
  }
}
