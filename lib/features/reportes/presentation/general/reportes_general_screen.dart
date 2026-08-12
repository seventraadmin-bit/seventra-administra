import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../domain/export/exportar_reporte_resultado.dart';
import '../../reportes_providers.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_general_controller.dart';

/// Reporte General (Etapa 12A) — vista consolidada por periodo. Cada
/// tarjeta se omite por completo cuando su campo llega en `null` (sin
/// autorización para esa sección) — nunca se muestra "$0" en su lugar,
/// eso sería indistinguible de un cero real y autorizado.
class ReportesGeneralScreen extends ConsumerWidget {
  const ReportesGeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesGeneralControllerProvider);
    final controller = ref.read(reportesGeneralControllerProvider.notifier);
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
                : ReporteExportButton(label: l10n.reportesExportarPdf, icon: Icons.picture_as_pdf_outlined, onExportar: exportarPdf),
          ),
          const SizedBox(height: AppSpacing.md),
          ReportesFiltroBar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
            onRangoInicioChanged: (fecha) => controller.cambiarRango(rangoInicio: fecha, rangoFin: state.rangoFin),
            onRangoFinChanged: (fecha) => controller.cambiarRango(rangoInicio: state.rangoInicio, rangoFin: fecha),
          ),
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
          else ...[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                if (resumen.totalIngresos != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralIngresos,
                    value: formatoCentavosPago(resumen.totalIngresos!),
                    icon: Icons.trending_up,
                  ),
                if (resumen.totalEgresos != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralEgresos,
                    value: formatoCentavosPago(resumen.totalEgresos!),
                    icon: Icons.trending_down,
                  ),
                if (resumen.resultadoOperativo != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralResultadoOperativo,
                    value: formatoCentavosPago(resumen.resultadoOperativo!),
                    icon: Icons.balance,
                    delta: resumen.resultadoOperativo! >= 0
                        ? l10n.reportesGeneralResultadoPositivo
                        : l10n.reportesGeneralResultadoNegativo,
                    deltaTone: resumen.resultadoOperativo! >= 0 ? RisegStatusTone.success : RisegStatusTone.error,
                  ),
                if (resumen.totalNominaPagadaPeriodo != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralNominaPagada,
                    value: formatoCentavosPago(resumen.totalNominaPagadaPeriodo!),
                    delta: l10n.reportesGeneralIndicadorInformativo,
                    deltaTone: RisegStatusTone.neutral,
                  ),
                if (resumen.totalComprasPeriodo != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralCompras,
                    value: formatoCentavosPago(resumen.totalComprasPeriodo!),
                    delta: l10n.reportesGeneralIndicadorInformativo,
                    deltaTone: RisegStatusTone.neutral,
                  ),
                if (resumen.personalActivoActual != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralPersonalActivo,
                    value: '${resumen.personalActivoActual}',
                    delta: l10n.reportesGeneralIndicadorSnapshot,
                    deltaTone: RisegStatusTone.neutral,
                    icon: Icons.people_outline,
                  ),
                if (resumen.serviciosActivosActual != null)
                  RisegStatCard(
                    label: l10n.reportesGeneralServiciosActivos,
                    value: '${resumen.serviciosActivosActual}',
                    delta: l10n.reportesGeneralIndicadorSnapshot,
                    deltaTone: RisegStatusTone.neutral,
                    icon: Icons.handshake_outlined,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
