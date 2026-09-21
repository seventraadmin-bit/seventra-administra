import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../domain/analitica/comparacion_periodo.dart';
import '../../domain/export/exportar_reporte_resultado.dart';
import '../../domain/export/reporte_export_context.dart';
import '../../reportes_providers.dart';
import '../widgets/analitica_labels.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/paneles_analiticos.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_finanzas_controller.dart';
import 'widgets/seccion_cuentas_por_cobrar.dart';
import 'widgets/seccion_deudas.dart';
import 'widgets/seccion_pagos.dart';
import 'widgets/selector_seccion_finanzas.dart';
import 'reportes_finanzas_state.dart';

/// Pestaña Finanzas de Reportes — reutiliza exclusivamente
/// consultas/casos de uso ya existentes de Finanzas (nunca reconstruye
/// el dominio dentro de Reportes).
class ReportesFinanzasScreen extends ConsumerWidget {
  const ReportesFinanzasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesFinanzasControllerProvider);
    final controller = ref.read(reportesFinanzasControllerProvider.notifier);

    Future<void> exportarPdf() async {
      final contexto = construirContextoExportacion(
        ref,
        nombreReporte: l10n.reportesNombreReporteFinanzas,
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
      );
      final resultado =
          await ref.read(exportarReporteFinanzasPdfUseCaseProvider).ejecutar(contexto: contexto, state: state);
      if (!context.mounted) return;
      switch (resultado) {
        case ExportarReporteExitoso():
          RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
        case ExportarReporteErrorInesperado():
          RisegFeedback.showError(context, l10n.reportesExportoError);
      }
    }

    Future<void> exportarEgresosXlsx() async {
      final origen = state.egresosPorOrigen;
      if (origen == null) return;
      final contexto = construirContextoExportacion(
        ref,
        nombreReporte: l10n.reportesNombreFinanzasEgresos,
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
      );
      final resultado = await ref
          .read(exportarFinanzasEgresosXlsxUseCaseProvider)
          .ejecutar(contexto: contexto, detalle: origen.detalle);
      if (!context.mounted) return;
      switch (resultado) {
        case ExportarReporteExitoso():
          RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
        case ExportarReporteErrorInesperado():
          RisegFeedback.showError(context, l10n.reportesExportoError);
      }
    }

    /// Muestra el resultado de cualquier exportación con el mismo
    /// mensaje — la diferencia entre ellas es qué se exporta, no cómo
    /// se avisa.
    void avisar(ExportarReporteResultado resultado) {
      if (!context.mounted) return;
      switch (resultado) {
        case ExportarReporteExitoso():
          RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
        case ExportarReporteErrorInesperado():
          RisegFeedback.showError(context, l10n.reportesExportoError);
      }
    }

    ReporteExportContext contextoDe(String nombre) => construirContextoExportacion(
          ref,
          nombreReporte: nombre,
          rangoInicio: state.rangoInicio,
          rangoFin: state.rangoFin,
        );

    Future<void> exportarCxcXlsx() async {
      final cobranza = state.cobranza;
      if (cobranza == null) return;
      // `cobranza.cuentas` ya viene filtrada por la pantalla: el
      // archivo trae exactamente el mismo universo que se está viendo.
      avisar(await ref.read(exportarCuentasPorCobrarXlsxUseCaseProvider).ejecutar(
            contexto: contextoDe(l10n.reportesNombreCxc),
            cuentas: cobranza.cuentas,
          ));
    }

    Future<void> exportarPagosXlsx() async {
      final pagos = state.pagos;
      if (pagos == null) return;
      avisar(await ref.read(exportarPagosXlsxUseCaseProvider).ejecutar(
            contexto: contextoDe(l10n.reportesNombrePagos),
            pagos: pagos.pagos,
          ));
    }

    Future<void> exportarDeudasXlsx() async {
      final deuda = state.deuda;
      if (deuda == null) return;
      avisar(await ref.read(exportarDeudasXlsxUseCaseProvider).ejecutar(
            contexto: contextoDe(l10n.reportesNombreDeudas),
            analisis: deuda,
          ));
    }

    /// El Excel que se ofrece depende de la sección: exportar la
    /// cartera desde la vista de Pagos no tendría sentido.
    ({String label, Future<void> Function() accion})? excelDeLaSeccion() => switch (state.seccion) {
          SeccionFinanzas.resumen => state.egresosPorOrigen == null
              ? null
              : (label: l10n.reportesExportarExcel, accion: exportarEgresosXlsx),
          SeccionFinanzas.cuentasPorCobrar =>
            state.cobranza == null ? null : (label: l10n.reportesExportarCxc, accion: exportarCxcXlsx),
          SeccionFinanzas.pagos =>
            state.pagos == null ? null : (label: l10n.reportesExportarPagos, accion: exportarPagosXlsx),
          SeccionFinanzas.deudas =>
            state.deuda == null ? null : (label: l10n.reportesExportarDeudas, accion: exportarDeudasXlsx),
        };

    final excel = excelDeLaSeccion();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.reportesFinanzasTitulo,
            description: l10n.reportesFinanzasDescripcion,
            primaryAction: controller.sinAutorizacion || state.cargando
                ? null
                : Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ReporteExportButton(
                        label: l10n.reportesExportarPdf,
                        icon: Icons.picture_as_pdf_outlined,
                        onExportar: exportarPdf,
                      ),
                      if (excel != null)
                        ReporteExportButton(
                          label: excel.label,
                          icon: Icons.grid_on_outlined,
                          onExportar: excel.accion,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          const ReportesFiltroBar(),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorCarga != null)
            RisegEmptyState(icon: Icons.error_outline, title: l10n.reportesErrorCargaTitulo, message: state.errorCarga!)
          else if (controller.sinAutorizacion)
            RisegEmptyState(
              icon: Icons.lock_outline,
              title: l10n.reportesSinSeccionesTitulo,
              message: l10n.reportesSinSeccionesMensaje,
            )
          else ...[
            SelectorSeccionFinanzas(
              seleccionada: state.seccion,
              onCambiar: controller.cambiarSeccion,
            ),
            const SizedBox(height: AppSpacing.lg),
            switch (state.seccion) {
              SeccionFinanzas.resumen => _Contenido(state: state),
              SeccionFinanzas.cuentasPorCobrar => state.cobranza == null
                  ? const SizedBox.shrink()
                  : SeccionCuentasPorCobrar(cobranza: state.cobranza!),
              SeccionFinanzas.pagos =>
                state.pagos == null ? const SizedBox.shrink() : SeccionPagos(pagos: state.pagos!),
              SeccionFinanzas.deudas =>
                state.deuda == null ? const SizedBox.shrink() : SeccionDeudas(deuda: state.deuda!),
            },
          ],
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.state});

  final ReportesFinanzasState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final analisis = state.analisis;
    final anterior = state.analisisAnterior;

    ({String texto, RisegStatusTone tono})? comparar(num actual, num? base, SentidoFavorable sentido) {
      if (base == null) return null;
      return deltaDeVariacion(l10n, VariacionPeriodo(actual: actual, anterior: base, sentido: sentido));
    }

    final cubetasConSaldo = state.montoPorCobrarPorRango.values.where((monto) => monto != 0).length;
    // Cada fila toma el alto del panel que más necesita (ver
    // `alturaDeFila`), nunca un valor fijo.
    final altoFilaGrafica = alturaDeFila([
      alturaSerieTemporal,
      RisegCompositionChart.alturaPara(analisis?.composicion.length ?? 0),
    ]);
    final altoFilaExposicion = alturaDeFila([
      RisegAgingBars.alturaPara(cubetasConSaldo),
      alturaDatosCompactos(3),
    ]);

    final margen = analisis?.margenOperativo;
    final vIngresos = comparar(state.totalIngresos, anterior?.ingresos, SentidoFavorable.masEsMejor);
    final vGasto = comparar(state.gastoOperativo, anterior?.gastoOperativo, SentidoFavorable.menosEsMejor);
    final vResultado = comparar(state.resultadoOperativo, anterior?.resultadoOperativo, SentidoFavorable.masEsMejor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegKpiGrid(
          children: [
            RisegStatCard(
              label: l10n.reportesGeneralIngresos,
              value: formatoCentavosPago(state.totalIngresos),
              icon: Icons.trending_up,
              delta: vIngresos?.texto,
              deltaTone: vIngresos?.tono,
            ),
            RisegStatCard(
              label: l10n.reportesGeneralGastoOperativo,
              value: formatoCentavosPago(state.gastoOperativo),
              icon: Icons.trending_down,
              delta: vGasto?.texto,
              deltaTone: vGasto?.tono,
            ),
            RisegStatCard(
              label: l10n.reportesGeneralResultadoOperativo,
              value: formatoCentavosPago(state.resultadoOperativo),
              icon: Icons.balance,
              delta: vResultado?.texto,
              deltaTone: vResultado?.tono,
            ),
            RisegStatCard(
              label: l10n.reportesGeneralMargenOperativo,
              value: margen == null ? '—' : '${(margen * 100).toStringAsFixed(1)} %',
              icon: Icons.percent,
              delta: margen == null ? l10n.reportesGeneralMargenIndefinido : null,
              deltaTone: margen == null
                  ? RisegStatusTone.neutral
                  : (margen >= 0 ? RisegStatusTone.success : RisegStatusTone.error),
            ),
            RisegStatCard(
              label: l10n.reportesFinanzasPagosRecibidos,
              value: formatoCentavosPago(state.totalPagosRecibidos),
              icon: Icons.payments_outlined,
            ),
          ],
        ),
        if (analisis != null) ...[
          const SizedBox(height: AppSpacing.md),
          FilaPaneles(
            paneles: [
              PanelAnalitico(
                flex: 3,
                minAncho: 380,
                child: RisegChartCard(
                  height: altoFilaGrafica,
                  title: l10n.reportesGeneralTendenciaTitulo,
                  subtitle:
                      '${l10n.reportesFinanzasTendenciaPregunta} · ${etiquetaGranularidad(l10n, analisis.granularidad)}',

                  vacio: analisis.ingresos == 0 && analisis.gastoOperativo == 0,
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
                ),
              ),
              PanelAnalitico(
                flex: 2,
                minAncho: 300,
                child: RisegChartCard(
                  height: altoFilaGrafica,
                  title: l10n.reportesFinanzasComposicionTitulo,
                  subtitle: l10n.reportesFinanzasComposicionPregunta,

                  vacio: analisis.composicion.isEmpty,
                  mensajeVacio: l10n.reportesFinanzasComposicionVacia,
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
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilaPaneles(
            paneles: [
              PanelAnalitico(flex: 3, minAncho: 340, child: _Cartera(state: state, altura: altoFilaExposicion)),
              PanelAnalitico(flex: 2, minAncho: 280, child: _Financiamiento(state: state, altura: altoFilaExposicion)),
              PanelAnalitico(flex: 2, minAncho: 260, child: _Exposicion(state: state, altura: altoFilaExposicion)),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              minAncho: 340,
              child: _TablaCategorias(
                titulo: l10n.reportesFinanzasIngresosPorCategoria,
                filas: state.ingresosPorCategoria,
              ),
            ),
            PanelAnalitico(
              minAncho: 340,
              child: _TablaCategorias(
                titulo: l10n.reportesFinanzasEgresosPorCategoria,
                nota: l10n.reportesFinanzasCategoriaNota,
                filas: state.egresosPorCategoria,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Cartera extends StatelessWidget {
  const _Cartera({required this.state, required this.altura});

  final ReportesFinanzasState state;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final total = state.montoPorCobrarPorRango.values.fold<int>(0, (a, b) => a + b);

    return RisegChartCard(
      title: l10n.reportesFinanzasAntiguedadTitulo,
      subtitle: '${l10n.reportesFinanzasAntiguedadPregunta} · ${l10n.reportesGeneralCarteraNota}',
      height: altura,
      vacio: total == 0,
      mensajeVacio: l10n.reportesGeneralCarteraVacia,
      iconoVacio: Icons.receipt_long_outlined,
      trailing: Text(
        formatoCentavosPago(total),
        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
      ),
      child: RisegAgingBars(
        formatoValor: formatoCentavosPago,
        cubetas: [
          for (final cubeta in RangoAntiguedadCuentaPorCobrar.values)
            if ((state.montoPorCobrarPorRango[cubeta] ?? 0) != 0)
              RisegAgingCubeta(
                label: etiquetaCubetaAntiguedad(l10n, cubeta),
                valor: state.montoPorCobrarPorRango[cubeta]!,
                tono: tonoCubetaAntiguedad(cubeta),
                detalle: l10n.reportesFinanzasAntiguedadConteo(state.cuentasPorCobrarPorRango[cubeta] ?? 0),
              ),
        ],
      ),
    );
  }
}

/// Descompone el gasto por **cómo se pagó**, no por a qué se destinó.
///
/// Responde la pregunta que el KPI de gasto operativo deja abierta:
/// cuánto de ese gasto ya salió de caja y cuánto quedó difiriéndose en
/// una tarjeta. Los pagos de deuda aparecen aquí, marcados como lo que
/// son — salida de caja que no es gasto del periodo.
class _Financiamiento extends StatelessWidget {
  const _Financiamiento({required this.state, required this.altura});

  final ReportesFinanzasState state;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegChartCard(
      title: l10n.reportesFinanzasFinanciamientoTitulo,
      subtitle: l10n.reportesFinanzasFinanciamientoPregunta,
      height: altura,
      iconoVacio: Icons.credit_card_outlined,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DatoCompacto(
            etiqueta: l10n.reportesFinanzasFinanciamientoEfectivo,
            nota: l10n.reportesFinanzasFinanciamientoEfectivoNota,
            valor: formatoCentavosPago(state.salidasDeEfectivo - state.pagosDeDeuda),
          ),
          DatoCompacto(
            etiqueta: l10n.reportesFinanzasFinanciamientoTarjeta,
            nota: l10n.reportesFinanzasFinanciamientoTarjetaNota,
            valor: formatoCentavosPago(state.cargosDeTarjeta),
          ),
          DatoCompacto(
            etiqueta: l10n.reportesFinanzasFinanciamientoPagoDeuda,
            nota: l10n.reportesFinanzasFinanciamientoPagoDeudaNota,
            valor: formatoCentavosPago(state.pagosDeDeuda),
          ),
        ],
      ),
    );
  }
}

class _TablaCategorias extends StatelessWidget {
  const _TablaCategorias({required this.titulo, required this.filas, this.nota});

  final String titulo;
  final String? nota;
  final List<TotalPorCategoria> filas;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          if (nota != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(nota!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          ],
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<TotalPorCategoria>(
            rows: filas,
            emptyState: RisegEmptyState(title: l10n.reportesSinDatosTitulo, message: l10n.reportesSinDatosMensaje),
            columns: [
              RisegColumn<TotalPorCategoria>(
                label: l10n.reportesFinanzasColumnaCategoria,
                cellBuilder: (c) => Text(c.nombreCategoria),
              ),
              RisegColumn<TotalPorCategoria>(
                label: l10n.reportesFinanzasColumnaTotal,
                width: 130,
                alignment: TextAlign.right,
                cellBuilder: (c) => Text(formatoCentavosPago(c.total)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cartera pendiente frente a deuda pendiente, ambas **a la fecha**.
///
/// Es informativo y así se etiqueta: NO es liquidez ni capital de
/// trabajo. Son dos magnitudes útiles de ver juntas, pero no se restan
/// entre sí ni equivalen a efectivo disponible — cobrar una factura
/// toma tiempo y pagar una deuda tiene fecha propia.
class _Exposicion extends StatelessWidget {
  const _Exposicion({required this.state, required this.altura});

  final ReportesFinanzasState state;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final porCobrar = state.cobranza?.saldoPendiente ?? 0;
    final porPagar = state.deuda?.saldoTotal ?? 0;

    return RisegChartCard(
      title: l10n.reportesExposicionTitulo,
      subtitle: l10n.reportesExposicionPregunta,
      height: altura,
      vacio: porCobrar == 0 && porPagar == 0,
      mensajeVacio: l10n.reportesCxcAgingVacia,
      iconoVacio: Icons.balance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RisegAgingBars(
              formatoValor: formatoCentavosPago,
              cubetas: [
                RisegAgingCubeta(
                  label: l10n.reportesExposicionCxc,
                  valor: porCobrar,
                  tono: RisegStatusTone.info,
                ),
                RisegAgingCubeta(
                  label: l10n.reportesExposicionDeuda,
                  valor: porPagar,
                  tono: RisegStatusTone.warning,
                ),
              ],
            ),
          ),
          Text(
            l10n.reportesExposicionNota,
            style: AppTypography.caption.copyWith(color: colors.textDisabled),
          ),
        ],
      ),
    );
  }
}
