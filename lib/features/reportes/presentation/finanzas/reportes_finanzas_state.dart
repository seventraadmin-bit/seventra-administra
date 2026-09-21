import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_cobranza_usecase.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_deuda_usecase.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_operativo_usecase.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_pagos_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';

import '../reportes_rango_controller.dart';

/// Secciones internas de la pestaña Finanzas.
///
/// No son pestañas anidadas: el módulo ya usa `RisegTabs` en su nivel
/// superior y anidar otro juego se lee mal. Es un selector de sección
/// —el mismo patrón visual que los presets de periodo— que evita la
/// pantalla kilométrica sin agregar un segundo nivel de navegación.
enum SeccionFinanzas { resumen, cuentasPorCobrar, pagos, deudas }

/// Un renglón resuelto de "Ingresos/Egresos por categoría" — ya con el
/// nombre de la categoría resuelto, `null` = sin categoría asignada.
class TotalPorCategoria {
  const TotalPorCategoria({required this.categoriaId, required this.nombreCategoria, required this.total});

  final String? categoriaId;
  final String nombreCategoria;
  final int total;
}

/// Estado de la pestaña Finanzas de Reportes.
class ReportesFinanzasState {
  const ReportesFinanzasState({
    required this.seleccion,
    this.seccion = SeccionFinanzas.resumen,
    this.filtroCobranza = const FiltroCobranza(),
    this.cargando = true,
    this.analisis,
    this.analisisAnterior,
    this.cobranza,
    this.pagos,
    this.deuda,
    this.ingresosPorCategoria = const [],
    this.egresosPorCategoria = const [],
    this.egresosPorOrigen,
    this.errorCarga,
  });

  final SeleccionRangoReportes seleccion;
  final SeccionFinanzas seccion;

  /// Filtros propios de la cartera. Son de **snapshot**: acotan qué
  /// cuentas se miran, nunca el periodo.
  final FiltroCobranza filtroCobranza;

  final bool cargando;

  /// KPI, serie temporal y composición del periodo — el mismo objeto que
  /// consume la pestaña General. Las dos pantallas no pueden mostrar
  /// resultados distintos porque leen del mismo cálculo.
  final AnalisisOperativoPeriodo? analisis;
  final AnalisisOperativoPeriodo? analisisAnterior;

  /// Cartera **a la fecha** — no se recorta con el periodo seleccionado.
  final AnalisisCobranza? cobranza;

  /// Pagos **del periodo**.
  final AnalisisPagos? pagos;

  /// Deuda: saldos a la fecha, movimientos del periodo.
  final AnalisisDeuda? deuda;

  final List<TotalPorCategoria> ingresosPorCategoria;
  final List<TotalPorCategoria> egresosPorCategoria;

  final ResumenEgresosPorOrigen? egresosPorOrigen;

  final String? errorCarga;

  DateTime get rangoInicio => seleccion.rango.inicio;
  DateTime get rangoFin => seleccion.rango.fin;

  int get totalIngresos => analisis?.ingresos ?? 0;

  /// La única definición de gasto operativo del sistema — ver
  /// [AnalisisOperativoPeriodo.gastoOperativo].
  int get gastoOperativo => analisis?.gastoOperativo ?? 0;

  int get salidasDeEfectivo => analisis?.salidasDeEfectivo ?? 0;
  int get pagosDeDeuda => analisis?.pagosDeDeuda ?? 0;
  int get cargosDeTarjeta => analisis?.cargosDeTarjeta ?? 0;
  int get resultadoOperativo => analisis?.resultadoOperativo ?? 0;

  /// Dinero recibido en el periodo. Sale del análisis de Pagos, no de
  /// una segunda suma — lo que se ve en la sección Pagos y lo que se ve
  /// aquí es el mismo número por construcción.
  int get totalPagosRecibidos => pagos?.importeRecibido ?? 0;

  /// Antigüedad de cartera, derivada del análisis único.
  ///
  /// Se conservan como mapas porque el renderizador de PDF los consume
  /// así; el cálculo, en cambio, ya no vive aquí. Antes el controller
  /// recorría las cuentas por su cuenta: eran dos aging distintos
  /// esperando divergir.
  Map<RangoAntiguedadCuentaPorCobrar, int> get montoPorCobrarPorRango =>
      {for (final c in cobranza?.aging ?? const []) c.cubeta: c.importe};

  Map<RangoAntiguedadCuentaPorCobrar, int> get cuentasPorCobrarPorRango =>
      {for (final c in cobranza?.aging ?? const []) c.cubeta: c.cuentas};

  ReportesFinanzasState copyWith({
    SeccionFinanzas? seccion,
    FiltroCobranza? filtroCobranza,
    bool? cargando,
    AnalisisOperativoPeriodo? analisis,
    AnalisisOperativoPeriodo? analisisAnterior,
    AnalisisCobranza? cobranza,
    AnalisisPagos? pagos,
    AnalisisDeuda? deuda,
    List<TotalPorCategoria>? ingresosPorCategoria,
    List<TotalPorCategoria>? egresosPorCategoria,
    ResumenEgresosPorOrigen? egresosPorOrigen,
    String? errorCarga,
  }) {
    return ReportesFinanzasState(
      seleccion: seleccion,
      seccion: seccion ?? this.seccion,
      filtroCobranza: filtroCobranza ?? this.filtroCobranza,
      cargando: cargando ?? this.cargando,
      analisis: analisis ?? this.analisis,
      analisisAnterior: analisisAnterior ?? this.analisisAnterior,
      cobranza: cobranza ?? this.cobranza,
      pagos: pagos ?? this.pagos,
      deuda: deuda ?? this.deuda,
      ingresosPorCategoria: ingresosPorCategoria ?? this.ingresosPorCategoria,
      egresosPorCategoria: egresosPorCategoria ?? this.egresosPorCategoria,
      egresosPorOrigen: egresosPorOrigen ?? this.egresosPorOrigen,
      errorCarga: errorCarga,
    );
  }
}
