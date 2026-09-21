import 'package:riseg_one/core/database/app_database.dart';

/// Estado del listado de Cuentas financieras (Etapa 19C) — muestra
/// activas e inactivas a la vez (con badge de estatus, nunca un filtro
/// server-side): a diferencia de Deudas, el universo esperado de
/// cuentas es pequeño (unas cuantas por empresa), así que no se
/// justifica paginación/filtros de servidor (Parte N, anti-sobre-
/// ingeniería).
class CuentasFinancierasState {
  const CuentasFinancierasState({
    this.cargando = true,
    this.cuentas = const [],
    this.saldosPorCuenta = const {},
    this.errorCarga,
  });

  final bool cargando;
  final List<CuentaFinancieraData> cuentas;
  final Map<String, int> saldosPorCuenta;
  final String? errorCarga;

  CuentasFinancierasState copyWith({
    bool? cargando,
    List<CuentaFinancieraData>? cuentas,
    Map<String, int>? saldosPorCuenta,
    String? errorCarga,
  }) {
    return CuentasFinancierasState(
      cargando: cargando ?? this.cargando,
      cuentas: cuentas ?? this.cuentas,
      saldosPorCuenta: saldosPorCuenta ?? this.saldosPorCuenta,
      errorCarga: errorCarga,
    );
  }
}
