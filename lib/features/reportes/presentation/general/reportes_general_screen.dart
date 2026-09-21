import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../domain/analitica/comparacion_periodo.dart';
import '../../domain/analitica/obtener_analisis_operativo_usecase.dart';
import '../../domain/export/exportar_reporte_resultado.dart';
import '../../domain/usecases/obtener_resumen_general_usecase.dart';
import '../../reportes_providers.dart';
import '../widgets/analitica_labels.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/paneles_analiticos.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_general_controller.dart';

/// Reporte General — resumen ejecutivo del periodo.
///
/// Reemplaza la versión que ponía cada cifra en una tarjeta de ancho
/// completo. La estructura ahora es de lectura descendente: primero los
/// KPIs con su comparación contra el periodo anterior, luego el
/// comportamiento en el tiempo y su composición, luego la exposición
/// (cartera) y lo que exige decisión, y al final lo informativo.
///
/// Cada cifra sigue omitiéndose por completo cuando su campo llega en
/// `null` (sin autorización para esa sección) — nunca se muestra "$0"
/// en su lugar, que sería indistinguible de un cero real y autorizado.
class ReportesGeneralScreen extends ConsumerWidget {
  const ReportesGeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesGeneralControllerProvider);
    final resumen = state.resumen;

    Future<void> exportarPdf() async {
      if (resumen == null) return;
      final contexto = construirContextoExportacion(
        ref,
        nombreReporte: l10n.reportesNombreReporteGeneral,
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
      );
      final resultado =
          await ref.read(exportarReporteGeneralPdfUseCaseProvider).ejecutar(contexto: contexto, resumen: resumen);
      if (!context.mounted) return;
      switch (resultado) {
        case ExportarReporteExitoso():
          RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
        case ExportarReporteErrorInesperado():
          RisegFeedback.showError(context, l10n.reportesExportoError);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.reportesGeneralTitulo,
            description: l10n.reportesGeneralDescripcion,
            primaryAction: resumen == null
                ? null
                : ReporteExportButton(
                    label: l10n.reportesExportarPdf,
                    icon: Icons.picture_as_pdf_outlined,
                    onExportar: exportarPdf,
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          const ReportesFiltroBar(),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando && resumen == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorCarga != null)
            RisegEmptyState(
              icon: Icons.error_outline,
              title: l10n.reportesErrorCargaTitulo,
              message: state.errorCarga!,
            )
          else if (resumen == null || state.sinNingunaSeccionAutorizada)
            RisegEmptyState(
              icon: Icons.lock_outline,
              title: l10n.reportesSinSeccionesTitulo,
              message: l10n.reportesSinSeccionesMensaje,
            )
          else
            _Contenido(resumen: resumen),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.resumen});

  final ResumenGeneralReportes resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final analisis = resumen.analisis;

    final cartera = resumen.antiguedadCartera;
    final cubetasConSaldo = cartera == null
        ? 0
        : cartera.montoPorCubeta.values.where((monto) => monto != 0).length;

    // La fila comparte la altura del panel que más necesita — nunca un
    // número fijo que deje media tarjeta vacía.
    final altoFilaGrafica = alturaDeFila([
      alturaSerieTemporal,
      RisegCompositionChart.alturaPara(analisis?.composicion.length ?? 0),
    ]);
    final altoFilaExposicion = alturaDeFila([
      RisegAgingBars.alturaPara(cubetasConSaldo),
      alturaRenglonesHecho(_Focos.cuantos(resumen)),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kpis(resumen: resumen),
        if (analisis != null) ...[
          const SizedBox(height: AppSpacing.md),
          FilaPaneles(
            paneles: [
              PanelAnalitico(flex: 3, minAncho: 380, child: _Tendencia(analisis: analisis, altura: altoFilaGrafica)),
              PanelAnalitico(flex: 2, minAncho: 300, child: _Composicion(analisis: analisis, altura: altoFilaGrafica)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilaPaneles(
            paneles: [
              PanelAnalitico(flex: 3, minAncho: 340, child: _Cartera(cartera: cartera, altura: altoFilaExposicion)),
              PanelAnalitico(flex: 2, minAncho: 280, child: _Focos(resumen: resumen, altura: altoFilaExposicion)),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _PanelInformativo(resumen: resumen, titulo: l10n.reportesGeneralPanelInformativoTitulo),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.resumen});

  final ResumenGeneralReportes resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final analisis = resumen.analisis;
    final anterior = resumen.analisisAnterior;

    /// Construye el par delta/tono de un KPI comparable. Sin periodo
    /// anterior cargado no se inventa una comparación: la tarjeta se
    /// muestra sin `delta`.
    ({String texto, RisegStatusTone tono})? comparar(num actual, num? base, SentidoFavorable sentido) {
      if (base == null) return null;
      return deltaDeVariacion(l10n, VariacionPeriodo(actual: actual, anterior: base, sentido: sentido));
    }

    final tarjetas = <Widget>[];

    if (analisis != null) {
      final vIngresos = comparar(analisis.ingresos, anterior?.ingresos, SentidoFavorable.masEsMejor);
      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralIngresos,
        value: formatoCentavosPago(analisis.ingresos),
        icon: Icons.trending_up,
        delta: vIngresos?.texto,
        deltaTone: vIngresos?.tono,
      ));

      final vGasto = comparar(analisis.gastoOperativo, anterior?.gastoOperativo, SentidoFavorable.menosEsMejor);
      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralGastoOperativo,
        value: formatoCentavosPago(analisis.gastoOperativo),
        icon: Icons.trending_down,
        delta: vGasto?.texto,
        deltaTone: vGasto?.tono,
      ));

      final vResultado = comparar(analisis.resultadoOperativo, anterior?.resultadoOperativo, SentidoFavorable.masEsMejor);
      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralResultadoOperativo,
        value: formatoCentavosPago(analisis.resultadoOperativo),
        icon: Icons.balance,
        delta: vResultado?.texto ??
            (analisis.resultadoOperativo >= 0
                ? l10n.reportesGeneralResultadoPositivo
                : l10n.reportesGeneralResultadoNegativo),
        deltaTone: vResultado?.tono ??
            (analisis.resultadoOperativo >= 0 ? RisegStatusTone.success : RisegStatusTone.error),
      ));

      final margen = analisis.margenOperativo;
      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralMargenOperativo,
        // Sin ingresos el margen es indefinido, no cero: se dice, no se
        // pinta un 0 % que afirmaría algo falso.
        value: margen == null ? '—' : '${(margen * 100).toStringAsFixed(1)} %',
        icon: Icons.percent,
        delta: margen == null ? l10n.reportesGeneralMargenIndefinido : null,
        deltaTone: margen == null
            ? RisegStatusTone.neutral
            : (margen >= 0 ? RisegStatusTone.success : RisegStatusTone.error),
      ));

      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralSalidasEfectivo,
        value: formatoCentavosPago(analisis.salidasDeEfectivo),
        icon: Icons.account_balance_wallet_outlined,
        delta: l10n.reportesGeneralSalidasEfectivoNota,
        deltaTone: RisegStatusTone.neutral,
      ));
    }

    if (resumen.personalActivoActual != null) {
      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralPersonalActivo,
        value: '${resumen.personalActivoActual}',
        icon: Icons.people_outline,
        delta: l10n.reportesGeneralIndicadorSnapshot,
        deltaTone: RisegStatusTone.neutral,
      ));
    }
    if (resumen.serviciosActivosActual != null) {
      tarjetas.add(RisegStatCard(
        label: l10n.reportesGeneralServiciosActivos,
        value: '${resumen.serviciosActivosActual}',
        icon: Icons.handshake_outlined,
        delta: l10n.reportesGeneralIndicadorSnapshot,
        deltaTone: RisegStatusTone.neutral,
      ));
    }

    return RisegKpiGrid(children: tarjetas);
  }
}

class _Tendencia extends StatelessWidget {
  const _Tendencia({required this.analisis, required this.altura});

  final AnalisisOperativoPeriodo analisis;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final vacio = analisis.ingresos == 0 && analisis.gastoOperativo == 0;

    return RisegChartCard(
      title: l10n.reportesGeneralTendenciaTitulo,
      subtitle: '${l10n.reportesGeneralTendenciaPregunta} · ${etiquetaGranularidad(l10n, analisis.granularidad)}',
      height: altura,
      vacio: vacio,
      mensajeVacio: l10n.reportesGeneralTendenciaVacia,
      legend: [
        RisegChartLegendItem(label: l10n.reportesLeyendaIngresos, color: colors.info),
        RisegChartLegendItem(label: l10n.reportesLeyendaGastoOperativo, color: colors.error),
      ],
      child: RisegBarChart(
        etiquetas: [for (final p in analisis.puntos) etiquetaCubeta(p.cubeta, analisis.granularidad)],
        formatoValor: formatoCentavosCompacto,
        series: [
          RisegBarSeries(
            label: l10n.reportesLeyendaIngresos,
            color: colors.info,
            valores: [for (final p in analisis.puntos) p.ingresos],
          ),
          RisegBarSeries(
            label: l10n.reportesLeyendaGastoOperativo,
            color: colors.error,
            valores: [for (final p in analisis.puntos) p.gastoOperativo],
          ),
        ],
      ),
    );
  }
}

class _Composicion extends StatelessWidget {
  const _Composicion({required this.analisis, required this.altura});

  final AnalisisOperativoPeriodo analisis;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegChartCard(
      title: l10n.reportesGeneralComposicionTitulo,
      subtitle: l10n.reportesGeneralComposicionPregunta,
      height: altura,
      vacio: analisis.composicion.isEmpty,
      mensajeVacio: l10n.reportesGeneralComposicionVacia,
      trailing: Text(
        formatoCentavosPago(analisis.gastoOperativo),
        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
      ),
      child: RisegCompositionChart(
        total: analisis.gastoOperativo,
        formatoValor: formatoCentavosPago,
        items: [
          for (final componente in analisis.composicion)
            RisegComposicionItem(
              label: etiquetaOrigenEgreso(l10n, componente.origen),
              valor: componente.importe,
              color: colorOrigenEgreso(context, componente.origen),
            ),
        ],
      ),
    );
  }
}

class _Cartera extends StatelessWidget {
  const _Cartera({required this.cartera, required this.altura});

  final AntiguedadCartera? cartera;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final datos = cartera;

    return RisegChartCard(
      title: l10n.reportesGeneralCarteraTitulo,
      subtitle: '${l10n.reportesGeneralCarteraPregunta} · ${l10n.reportesGeneralCarteraNota}',
      height: altura,
      vacio: datos == null || datos.total == 0,
      mensajeVacio: l10n.reportesGeneralCarteraVacia,
      iconoVacio: Icons.receipt_long_outlined,
      trailing: datos == null
          ? null
          : Text(
              formatoCentavosPago(datos.total),
              style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
      child: datos == null
          ? const SizedBox.shrink()
          : RisegAgingBars(
              formatoValor: formatoCentavosPago,
              cubetas: [
                for (final cubeta in RangoAntiguedadCuentaPorCobrar.values)
                  if ((datos.montoPorCubeta[cubeta] ?? 0) != 0)
                    RisegAgingCubeta(
                      label: etiquetaCubetaAntiguedad(l10n, cubeta),
                      valor: datos.montoPorCubeta[cubeta]!,
                      tono: tonoCubetaAntiguedad(cubeta),
                      detalle: l10n.reportesFinanzasAntiguedadConteo(datos.cuentasPorCubeta[cubeta] ?? 0),
                    ),
              ],
            ),
    );
  }
}

class _Focos extends StatelessWidget {
  const _Focos({required this.resumen, required this.altura});

  final ResumenGeneralReportes resumen;
  final double altura;

  /// Cuántos focos aplican, para que la fila reserve el alto correcto
  /// antes de construirlos. Misma aritmética que [build] — si divergiera
  /// el panel quedaría corto o sobrado.
  static int cuantos(ResumenGeneralReportes resumen) {
    final analisis = resumen.analisis;
    final anterior = resumen.analisisAnterior;
    var total = 0;
    if ((resumen.antiguedadCartera?.vencido ?? 0) > 0) total++;
    if (analisis != null && analisis.resultadoOperativo < 0) total++;
    if (analisis != null && anterior != null) {
      final gasto = VariacionPeriodo(
        actual: analisis.gastoOperativo,
        anterior: anterior.gastoOperativo,
        sentido: SentidoFavorable.menosEsMejor,
      );
      if (gasto.tono == TonoVariacion.desfavorable && !gasto.sinBaseComparable) total++;
      final ingresos = VariacionPeriodo(
        actual: analisis.ingresos,
        anterior: anterior.ingresos,
        sentido: SentidoFavorable.masEsMejor,
      );
      if (ingresos.tono == TonoVariacion.desfavorable && !ingresos.sinBaseComparable) total++;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final analisis = resumen.analisis;
    final anterior = resumen.analisisAnterior;

    // Cada foco es aritmética sobre datos que ya se trajeron — nunca una
    // regla de negocio nueva inventada en Reportes.
    final focos = <Widget>[];

    final vencido = resumen.antiguedadCartera?.vencido ?? 0;
    if (vencido > 0) {
      focos.add(RenglonHecho(
        texto: l10n.reportesGeneralFocoCarteraVencida(formatoCentavosPago(vencido)),
        tono: RisegStatusTone.error,
        icono: Icons.schedule,
      ));
    }

    if (analisis != null && analisis.resultadoOperativo < 0) {
      focos.add(RenglonHecho(
        texto: l10n.reportesGeneralFocoResultadoNegativo,
        tono: RisegStatusTone.error,
        icono: Icons.trending_down,
      ));
    }

    if (analisis != null && anterior != null) {
      final gasto = VariacionPeriodo(
        actual: analisis.gastoOperativo,
        anterior: anterior.gastoOperativo,
        sentido: SentidoFavorable.menosEsMejor,
      );
      if (gasto.tono == TonoVariacion.desfavorable && !gasto.sinBaseComparable) {
        focos.add(RenglonHecho(
          texto: l10n.reportesGeneralFocoGastoSubio(textoVariacionCorta(gasto)),
          tono: RisegStatusTone.warning,
          icono: Icons.north_east,
        ));
      }

      final ingresos = VariacionPeriodo(
        actual: analisis.ingresos,
        anterior: anterior.ingresos,
        sentido: SentidoFavorable.masEsMejor,
      );
      if (ingresos.tono == TonoVariacion.desfavorable && !ingresos.sinBaseComparable) {
        focos.add(RenglonHecho(
          texto: l10n.reportesGeneralFocoIngresosBajaron(textoVariacionCorta(ingresos)),
          tono: RisegStatusTone.warning,
          icono: Icons.south_east,
        ));
      }
    }

    return RisegChartCard(
      title: l10n.reportesGeneralFocosTitulo,
      subtitle: l10n.reportesGeneralFocosPregunta,
      height: altura,
      vacio: focos.isEmpty,
      mensajeVacio: l10n.reportesGeneralFocosNinguno,
      iconoVacio: Icons.check_circle_outline,
      child: ListView(padding: EdgeInsets.zero, children: focos),
    );
  }
}

class _PanelInformativo extends StatelessWidget {
  const _PanelInformativo({required this.resumen, required this.titulo});

  final ResumenGeneralReportes resumen;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    // Personal activo y Servicios activos NO se repiten aquí: ya son
    // tarjetas de KPI arriba. Mostrar el mismo número dos veces en una
    // pantalla es exactamente el ruido que este rediseño elimina.
    final datos = <Widget>[
      if (resumen.totalNominaPagadaPeriodo != null)
        DatoCompacto(
          etiqueta: l10n.reportesGeneralNominaPagada,
          nota: l10n.reportesGeneralIndicadorInformativo,
          valor: formatoCentavosPago(resumen.totalNominaPagadaPeriodo!),
        ),
      if (resumen.totalComprasPeriodo != null)
        DatoCompacto(
          etiqueta: l10n.reportesGeneralCompras,
          nota: l10n.reportesGeneralIndicadorInformativo,
          valor: formatoCentavosPago(resumen.totalComprasPeriodo!),
        ),
    ];

    if (datos.isEmpty) return const SizedBox.shrink();

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          // Dos columnas de datos informativos: nunca una tarjeta de
          // ancho completo por número.
          LayoutBuilder(
            builder: (context, constraints) {
              final dosColumnas = constraints.maxWidth >= 560;
              if (!dosColumnas) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: datos);
              }
              final mitad = (datos.length / 2).ceil();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: datos.sublist(0, mitad)),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: datos.sublist(mitad)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
