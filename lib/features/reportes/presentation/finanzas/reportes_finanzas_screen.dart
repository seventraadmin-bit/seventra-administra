import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';

import '../../domain/export/exportar_reporte_resultado.dart';
import '../../reportes_providers.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_finanzas_controller.dart';
import 'reportes_finanzas_state.dart';

/// Pestaña Finanzas de Reportes (Etapa 12A) — reutiliza exclusivamente
/// consultas/casos de uso ya existentes de Finanzas (nunca reconstruye
/// el dominio dentro de Reportes).
class ReportesFinanzasScreen extends ConsumerWidget {
  const ReportesFinanzasScreen({super.key});

  String _etiquetaRango(AppLocalizations l10n, RangoAntiguedadCuentaPorCobrar rango) => switch (rango) {
        RangoAntiguedadCuentaPorCobrar.alCorriente => l10n.reportesFinanzasAntiguedadAlCorriente,
        RangoAntiguedadCuentaPorCobrar.dias0a30 => l10n.reportesFinanzasAntiguedad0a30,
        RangoAntiguedadCuentaPorCobrar.dias31a60 => l10n.reportesFinanzasAntiguedad31a60,
        RangoAntiguedadCuentaPorCobrar.dias61a90 => l10n.reportesFinanzasAntiguedad61a90,
        RangoAntiguedadCuentaPorCobrar.dias90Mas => l10n.reportesFinanzasAntiguedad90Mas,
      };

  String _etiquetaOrigen(AppLocalizations l10n, OrigenEgreso origen) => switch (origen) {
        OrigenEgreso.compra => l10n.reportesFinanzasOrigenCompra,
        OrigenEgreso.nomina => l10n.reportesFinanzasOrigenNomina,
        OrigenEgreso.manual => l10n.reportesFinanzasOrigenManual,
      };

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
      final resultado =
          await ref.read(exportarFinanzasEgresosXlsxUseCaseProvider).ejecutar(contexto: contexto, detalle: origen.detalle);
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
            title: l10n.reportesFinanzasTitulo,
            description: l10n.reportesFinanzasDescripcion,
            primaryAction: controller.sinAutorizacion || state.cargando
                ? null
                : Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ReporteExportButton(label: l10n.reportesExportarPdf, icon: Icons.picture_as_pdf_outlined, onExportar: exportarPdf),
                      if (state.egresosPorOrigen != null)
                        ReporteExportButton(
                          label: l10n.reportesExportarExcel,
                          icon: Icons.grid_on_outlined,
                          onExportar: exportarEgresosXlsx,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          ReportesFiltroBar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
            onRangoInicioChanged: (fecha) => controller.cambiarRango(rangoInicio: fecha, rangoFin: state.rangoFin),
            onRangoFinChanged: (fecha) => controller.cambiarRango(rangoInicio: state.rangoInicio, rangoFin: fecha),
          ),
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
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                RisegStatCard(
                  label: l10n.reportesGeneralIngresos,
                  value: formatoCentavosPago(state.totalIngresos),
                  icon: Icons.trending_up,
                ),
                RisegStatCard(
                  label: l10n.reportesGeneralEgresos,
                  value: formatoCentavosPago(state.totalEgresos),
                  icon: Icons.trending_down,
                ),
                RisegStatCard(
                  label: l10n.reportesGeneralResultadoOperativo,
                  value: formatoCentavosPago(state.resultadoOperativo),
                  icon: Icons.balance,
                ),
                RisegStatCard(
                  label: l10n.reportesFinanzasPagosRecibidos,
                  value: formatoCentavosPago(state.totalPagosRecibidos),
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            RisegCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.reportesFinanzasAntiguedadTitulo, style: AppTypography.heading3),
                  const SizedBox(height: AppSpacing.sm),
                  for (final rango in RangoAntiguedadCuentaPorCobrar.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      child: Row(
                        children: [
                          Expanded(child: Text(_etiquetaRango(l10n, rango))),
                          Text(
                            l10n.reportesFinanzasAntiguedadConteo(state.cuentasPorCobrarPorRango[rango] ?? 0),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(
                            width: 110,
                            child: Text(
                              formatoCentavosPago(state.montoPorCobrarPorRango[rango] ?? 0),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.egresosPorOrigen case final origen?)
              RisegCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.reportesFinanzasOrigenTitulo, style: AppTypography.heading3),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.sm,
                      children: [
                        Text('${_etiquetaOrigen(l10n, OrigenEgreso.compra)}: ${formatoCentavosPago(origen.totalCompra)}'),
                        Text('${_etiquetaOrigen(l10n, OrigenEgreso.nomina)}: ${formatoCentavosPago(origen.totalNomina)}'),
                        Text('${_etiquetaOrigen(l10n, OrigenEgreso.manual)}: ${formatoCentavosPago(origen.totalManual)}'),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.reportesFinanzasIngresosPorCategoria, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegTableBase<TotalPorCategoria>(
              rows: state.ingresosPorCategoria,
              emptyState: RisegEmptyState(title: l10n.reportesSinDatosTitulo, message: l10n.reportesSinDatosMensaje),
              columns: [
                RisegColumn<TotalPorCategoria>(label: l10n.reportesFinanzasColumnaCategoria, cellBuilder: (c) => Text(c.nombreCategoria)),
                RisegColumn<TotalPorCategoria>(
                  label: l10n.reportesFinanzasColumnaTotal,
                  width: 140,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(formatoCentavosPago(c.total)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.reportesFinanzasEgresosPorCategoria, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegTableBase<TotalPorCategoria>(
              rows: state.egresosPorCategoria,
              emptyState: RisegEmptyState(title: l10n.reportesSinDatosTitulo, message: l10n.reportesSinDatosMensaje),
              columns: [
                RisegColumn<TotalPorCategoria>(label: l10n.reportesFinanzasColumnaCategoria, cellBuilder: (c) => Text(c.nombreCategoria)),
                RisegColumn<TotalPorCategoria>(
                  label: l10n.reportesFinanzasColumnaTotal,
                  width: 140,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(formatoCentavosPago(c.total)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
