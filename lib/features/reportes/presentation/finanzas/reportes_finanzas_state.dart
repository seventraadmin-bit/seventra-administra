import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';

/// Un renglón resuelto de "Ingresos/Egresos por categoría" — ya con el
/// nombre de la categoría resuelto, `null` = sin categoría asignada.
class TotalPorCategoria {
  const TotalPorCategoria({required this.categoriaId, required this.nombreCategoria, required this.total});

  final String? categoriaId;
  final String nombreCategoria;
  final int total;
}

/// Estado de la pestaña Finanzas de Reportes (Etapa 12A).
class ReportesFinanzasState {
  const ReportesFinanzasState({
    this.cargando = true,
    this.rangoInicio,
    this.rangoFin,
    this.totalIngresos = 0,
    this.totalEgresos = 0,
    this.resultadoOperativo = 0,
    this.totalPagosRecibidos = 0,
    this.cuentasPorCobrarPorRango = const {},
    this.montoPorCobrarPorRango = const {},
    this.ingresosPorCategoria = const [],
    this.egresosPorCategoria = const [],
    this.egresosPorOrigen,
    this.errorCarga,
  });

  final bool cargando;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;

  final int totalIngresos;
  final int totalEgresos;
  final int resultadoOperativo;
  final int totalPagosRecibidos;

  /// Antigüedad de Cuentas por cobrar — cantidad y monto por rango
  /// (ver `RangoAntiguedadCuentaPorCobrar`), sobre TODAS las cuentas no
  /// pagadas actuales (no filtra por [rangoInicio]/[rangoFin]: la
  /// antigüedad es una foto de hoy, no del periodo).
  final Map<RangoAntiguedadCuentaPorCobrar, int> cuentasPorCobrarPorRango;
  final Map<RangoAntiguedadCuentaPorCobrar, int> montoPorCobrarPorRango;

  final List<TotalPorCategoria> ingresosPorCategoria;
  final List<TotalPorCategoria> egresosPorCategoria;

  final ResumenEgresosPorOrigen? egresosPorOrigen;

  final String? errorCarga;

  ReportesFinanzasState copyWith({
    bool? cargando,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    int? totalIngresos,
    int? totalEgresos,
    int? resultadoOperativo,
    int? totalPagosRecibidos,
    Map<RangoAntiguedadCuentaPorCobrar, int>? cuentasPorCobrarPorRango,
    Map<RangoAntiguedadCuentaPorCobrar, int>? montoPorCobrarPorRango,
    List<TotalPorCategoria>? ingresosPorCategoria,
    List<TotalPorCategoria>? egresosPorCategoria,
    ResumenEgresosPorOrigen? egresosPorOrigen,
    String? errorCarga,
  }) {
    return ReportesFinanzasState(
      cargando: cargando ?? this.cargando,
      rangoInicio: rangoInicio ?? this.rangoInicio,
      rangoFin: rangoFin ?? this.rangoFin,
      totalIngresos: totalIngresos ?? this.totalIngresos,
      totalEgresos: totalEgresos ?? this.totalEgresos,
      resultadoOperativo: resultadoOperativo ?? this.resultadoOperativo,
      totalPagosRecibidos: totalPagosRecibidos ?? this.totalPagosRecibidos,
      cuentasPorCobrarPorRango: cuentasPorCobrarPorRango ?? this.cuentasPorCobrarPorRango,
      montoPorCobrarPorRango: montoPorCobrarPorRango ?? this.montoPorCobrarPorRango,
      ingresosPorCategoria: ingresosPorCategoria ?? this.ingresosPorCategoria,
      egresosPorCategoria: egresosPorCategoria ?? this.egresosPorCategoria,
      egresosPorOrigen: egresosPorOrigen ?? this.egresosPorOrigen,
      errorCarga: errorCarga,
    );
  }
}
