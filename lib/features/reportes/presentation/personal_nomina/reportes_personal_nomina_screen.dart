import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/personal/presentation/empleados/widgets/motivo_baja_empleado_labels.dart'
    show motivoBajaEmpleadoLabel;
import 'package:riseg_one/features/reportes/domain/export/exportar_reporte_resultado.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_list_screen.dart'
    show nominaEstatusLabel, nominaEstatusTono;
import 'package:riseg_one/features/reportes/reportes_providers.dart';

import '../widgets/analitica_labels.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/paneles_analiticos.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_personal_nomina_controller.dart';
import 'reportes_personal_nomina_state.dart';

/// Pestaña Personal · Nómina de Reportes — dos subsecciones
/// independientes, cada una omitida por completo si falta su permiso.
///
/// La subsección Personal nunca muestra una cifra en pesos (regla de
/// diseño explícita) — los montos viven exclusivamente en la subsección
/// Nómina.
class ReportesPersonalNominaScreen extends ConsumerWidget {
  const ReportesPersonalNominaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesPersonalNominaControllerProvider);
    final controller = ref.read(reportesPersonalNominaControllerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.reportesPersonalNominaTitulo,
            description: l10n.reportesPersonalNominaDescripcion,
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
          else if (!controller.tienePersonal && !controller.tieneNomina)
            RisegEmptyState(
              icon: Icons.lock_outline,
              title: l10n.reportesSinSeccionesTitulo,
              message: l10n.reportesSinSeccionesMensaje,
            )
          else ...[
            if (controller.tienePersonal && state.resumenPersonal != null) ...[
              _SeccionPersonal(
                resumen: state.resumenPersonal!,
                onExportar: () => _exportarPersonal(context, ref, l10n, state, state.resumenPersonal!),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneNomina && state.resumenNomina != null)
              _SeccionNomina(
                resumen: state.resumenNomina!,
                // Solo se pasa si la sesión puede ver Personal: el bloque
                // de contexto compara las dos cifras, y sin ese permiso
                // no debe aparecer ninguna de plantilla.
                resumenPersonal: controller.tienePersonal ? state.resumenPersonal : null,
                onExportar: () => _exportarNomina(context, ref, l10n, state, state.resumenNomina!),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _exportarPersonal(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  ReportesPersonalNominaState state,
  ResumenPersonalReportes resumen,
) async {
  final contexto = construirContextoExportacion(
    ref,
    nombreReporte: l10n.reportesNombrePersonalEventos,
    rangoInicio: state.rangoInicio,
    rangoFin: state.rangoFin,
  );
  final resultado =
      await ref.read(exportarPersonalEventosXlsxUseCaseProvider).ejecutar(contexto: contexto, resumen: resumen);
  if (!context.mounted) return;
  switch (resultado) {
    case ExportarReporteExitoso():
      RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
    case ExportarReporteErrorInesperado():
      RisegFeedback.showError(context, l10n.reportesExportoError);
  }
}

Future<void> _exportarNomina(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  ReportesPersonalNominaState state,
  ResumenNominaReportes resumen,
) async {
  final contexto = construirContextoExportacion(
    ref,
    nombreReporte: l10n.reportesNombreNominaPeriodo,
    rangoInicio: state.rangoInicio,
    rangoFin: state.rangoFin,
  );
  final resultado =
      await ref.read(exportarNominaPeriodoXlsxUseCaseProvider).ejecutar(contexto: contexto, resumen: resumen);
  if (!context.mounted) return;
  switch (resultado) {
    case ExportarReporteExitoso():
      RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
    case ExportarReporteErrorInesperado():
      RisegFeedback.showError(context, l10n.reportesExportoError);
  }
}

class _SeccionPersonal extends StatelessWidget {
  const _SeccionPersonal({required this.resumen, required this.onExportar});

  final ResumenPersonalReportes resumen;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final altas = resumen.altasEnPeriodo.length;
    final reingresos = resumen.reingresosEnPeriodo.length;
    final bajas = resumen.bajasEnPeriodo.length;
    final neto = altas + reingresos - bajas;

    // Tres paneles chicos: el alto sale del que más renglones tiene, no
    // de un número fijo que dejaría a los otros dos medio vacíos.
    final altoFila = alturaDeFila([
      RisegCompositionChart.alturaPara(2), // operativos + administrativos
      alturaBarrasCategoricas,
      RisegCompositionChart.alturaPara(resumen.motivosBajaConteo.length),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.reportesPersonalSeccionTitulo,
          secondaryAction: ReporteExportButton(
            label: l10n.reportesExportarExcel,
            icon: Icons.grid_on_outlined,
            onExportar: onExportar,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegKpiGrid(
          children: [
            RisegStatCard(
              label: l10n.reportesPersonalActivos,
              value: '${resumen.totalActivos}',
              icon: Icons.people_outline,
              delta: l10n.reportesGeneralIndicadorSnapshot,
              deltaTone: RisegStatusTone.neutral,
            ),
            RisegStatCard(label: l10n.reportesPersonalAltas, value: '$altas', icon: Icons.person_add_alt),
            RisegStatCard(label: l10n.reportesPersonalReingresos, value: '$reingresos', icon: Icons.replay),
            RisegStatCard(
              label: l10n.reportesPersonalBajas,
              value: '$bajas',
              icon: Icons.person_remove_alt_1_outlined,
              // Que haya bajas no es "error" por sí mismo; se tiñe solo
              // cuando la plantilla se está encogiendo en el periodo.
              deltaTone: bajas > 0 && neto < 0 ? RisegStatusTone.warning : null,
              delta: bajas > 0 && neto < 0 ? l10n.reportesPersonalMovimientoNeto('$neto') : null,
            ),
            RisegStatCard(
              label: l10n.reportesPersonalAlertasRecontratacion,
              value: '${resumen.alertasRecontratacion.length}',
              icon: Icons.report_gmailerrorred_outlined,
              deltaTone: resumen.alertasRecontratacion.isEmpty ? null : RisegStatusTone.warning,
              delta: resumen.alertasRecontratacion.isEmpty ? null : l10n.reportesPersonalRevisarAntesDeContratar,
            ),
            RisegStatCard(
              label: l10n.reportesPersonalProximosAniversarios,
              value: '${resumen.proximosAniversarios.length}',
              icon: Icons.cake_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              minAncho: 300,
              child: RisegChartCard(
                title: l10n.reportesPersonalDistribucionTitulo,
                subtitle: l10n.reportesPersonalDistribucionPregunta,
                height: altoFila,
                vacio: resumen.totalActivos == 0,
                mensajeVacio: l10n.reportesPersonalDistribucionVacia,
                iconoVacio: Icons.people_outline,
                trailing: Text(
                  '${resumen.totalActivos}',
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
                child: RisegCompositionChart(
                  total: resumen.totalActivos,
                  formatoValor: formatoCantidad,
                  items: [
                    RisegComposicionItem(
                      label: l10n.reportesPersonalOperativos,
                      valor: resumen.totalOperativos,
                      color: colors.accent,
                    ),
                    RisegComposicionItem(
                      label: l10n.reportesPersonalAdministrativos,
                      valor: resumen.totalAdministrativos,
                      color: colors.info,
                    ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              minAncho: 300,
              child: RisegChartCard(
                title: l10n.reportesPersonalMovimientoTitulo,
                subtitle: l10n.reportesPersonalMovimientoPregunta,
                height: altoFila,
                vacio: altas == 0 && reingresos == 0 && bajas == 0,
                mensajeVacio: l10n.reportesPersonalMovimientoVacia,
                iconoVacio: Icons.swap_vert,
                trailing: Text(
                  l10n.reportesPersonalMovimientoNeto(neto > 0 ? '+$neto' : '$neto'),
                  style: AppTypography.bodyStrong.copyWith(
                    color: neto < 0 ? colors.error : (neto > 0 ? colors.success : colors.textPrimary),
                  ),
                ),
                child: RisegBarChart(
                  etiquetas: [
                    l10n.reportesPersonalAltas,
                    l10n.reportesPersonalReingresos,
                    l10n.reportesPersonalBajas,
                  ],
                  formatoValor: formatoCantidad,
                  mostrarEjeY: false,
                  series: [
                    RisegBarSeries(
                      label: l10n.reportesPersonalMovimientoTitulo,
                      color: colors.accent,
                      valores: [altas, reingresos, bajas],
                    ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              minAncho: 300,
              child: RisegChartCard(
                title: l10n.reportesPersonalMotivosBajaTitulo,
                subtitle: l10n.reportesPersonalMotivosBajaPregunta,
                height: altoFila,
                vacio: resumen.motivosBajaConteo.isEmpty,
                mensajeVacio: l10n.reportesPersonalMotivosBajaVacia,
                iconoVacio: Icons.logout,
                child: RisegCompositionChart(
                  total: bajas,
                  formatoValor: formatoCantidad,
                  items: [
                    for (final (indice, entrada) in resumen.motivosBajaConteo.entries.indexed)
                      RisegComposicionItem(
                        label: motivoBajaEmpleadoLabel(l10n, entrada.key.name),
                        valor: entrada.value,
                        color: context.colorCategorico(indice),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeccionNomina extends StatelessWidget {
  const _SeccionNomina({required this.resumen, required this.onExportar, this.resumenPersonal});

  final ResumenNominaReportes resumen;
  final ResumenPersonalReportes? resumenPersonal;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final generado = resumen.totalGeneradoGlobal;
    final pagado = resumen.totalPagadoGlobal;
    // Sin nómina generada el avance es indefinido, no 0 % — mostrar una
    // barra vacía sugeriría que hay algo pendiente de pagar.
    final avance = generado == 0 ? null : (pagado / generado) * 100;

    final personal = resumenPersonal;
    final enNomina = resumen.empleadosDistintosEnPeriodo;
    // El bloque de contexto solo aparece cuando hay algo que explicar:
    // si las dos cifras coinciden, sobra.
    final explicarPlantilla = personal != null && enNomina != personal.totalActivos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.reportesNominaSeccionTitulo,
          secondaryAction: ReporteExportButton(
            label: l10n.reportesExportarExcel,
            icon: Icons.grid_on_outlined,
            onExportar: onExportar,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              flex: 3,
              minAncho: 320,
              child: RisegKpiGrid(
                maxColumnas: 2,
                children: [
                  RisegStatCard(
                    label: l10n.reportesNominaTotalGenerado,
                    value: formatoCentavosPago(generado),
                    icon: Icons.receipt_long_outlined,
                  ),
                  RisegStatCard(
                    label: l10n.reportesNominaTotalPagado,
                    value: formatoCentavosPago(pagado),
                    icon: Icons.payments_outlined,
                  ),
                  RisegStatCard(
                    label: l10n.reportesNominaSaldoPendiente,
                    value: formatoCentavosPago(resumen.totalPendienteGlobal),
                    icon: Icons.pending_actions_outlined,
                    deltaTone: resumen.totalPendienteGlobal > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
                  ),
                  RisegStatCard(
                    label: l10n.reportesNominaEmpleadosPeriodo,
                    value: '$enNomina',
                    icon: Icons.badge_outlined,
                    delta: l10n.reportesNominaEmpleadosPeriodoNota,
                    deltaTone: RisegStatusTone.neutral,
                  ),
                ],
              ),
            ),
            PanelAnalitico(
              flex: 2,
              minAncho: 260,
              child: RisegChartCard(
                title: l10n.reportesNominaAvanceTitulo,
                subtitle: l10n.reportesNominaAvancePregunta,
                height: 96,
                vacio: avance == null,
                mensajeVacio: l10n.reportesNominaAvanceVacia,
                iconoVacio: Icons.savings_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.reportesNominaAvancePorcentaje('${(avance ?? 0).toStringAsFixed(0)} %'),
                      style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    RisegProgressBar(
                      porcentaje: avance ?? 0,
                      tone: (avance ?? 0) >= 100 ? RisegStatusTone.success : RisegStatusTone.warning,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (explicarPlantilla) ...[
          const SizedBox(height: AppSpacing.md),
          _ContextoPlantilla(enNomina: enNomina, personal: personal),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(l10n.reportesNominaListadoTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        RisegTableBase<NominaConTotales>(
          rows: resumen.nominas,
          emptyState: RisegEmptyState(title: l10n.reportesSinDatosTitulo, message: l10n.reportesSinDatosMensaje),
          onRowTap: (n) => context.go('/personal/nomina/${n.nomina.id}'),
          columns: [
            RisegColumn<NominaConTotales>(
              label: l10n.reportesNominaColumnaFolio,
              width: 110,
              cellBuilder: (n) => Text(n.nomina.folio),
            ),
            RisegColumn<NominaConTotales>(
              label: l10n.reportesNominaColumnaEstatus,
              width: 150,
              // Badge con la MISMA etiqueta y el mismo tono que el listado
              // de Nóminas — antes aquí se imprimía el valor crudo del
              // enum ('cerrada', 'pagada'), el único lugar del módulo que
              // mostraba un código en vez de texto de presentación.
              cellBuilder: (n) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: RisegStatusBadge(
                      label: nominaEstatusLabel(l10n, n.nomina.estatus),
                      tone: nominaEstatusTono(n.nomina.estatus),
                    ),
                  ),
                  if (n.esPagoParcial) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        l10n.reportesNominaPagoParcial,
                        style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            RisegColumn<NominaConTotales>(
              label: l10n.reportesNominaColumnaEmpleados,
              width: 100,
              cellBuilder: (n) => Text('${n.empleadosIncluidos}'),
            ),
            RisegColumn<NominaConTotales>(
              label: l10n.reportesNominaColumnaGenerado,
              width: 130,
              alignment: TextAlign.right,
              cellBuilder: (n) => Text(formatoCentavosPago(n.totalGenerado)),
            ),
            RisegColumn<NominaConTotales>(
              label: l10n.reportesNominaColumnaPagado,
              width: 130,
              alignment: TextAlign.right,
              cellBuilder: (n) => Text(formatoCentavosPago(n.totalPagado)),
            ),
            RisegColumn<NominaConTotales>(
              label: l10n.reportesNominaColumnaPendiente,
              width: 130,
              alignment: TextAlign.right,
              cellBuilder: (n) => Text(formatoCentavosPago(n.saldoPendiente)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Explica, con las cifras reales, por qué la nómina del periodo puede
/// incluir más (o menos) gente que la plantilla activa de hoy.
///
/// No se altera ninguna de las dos cifras para hacerlas coincidir, ni se
/// afirma una causa: se ponen los números uno junto a otro —cuántos
/// salieron en las nóminas del periodo, cuántos están activos hoy,
/// cuántas altas/reingresos y cuántas bajas ocurrieron dentro del
/// periodo— y se enuncia la única diferencia estructural que existe
/// entre las dos: una es histórica y congelada, la otra es de hoy.
///
/// El bloque solo se construye cuando la sesión puede ver Personal; sin
/// ese permiso ninguna cifra de plantilla llega hasta aquí.
class _ContextoPlantilla extends StatelessWidget {
  const _ContextoPlantilla({required this.enNomina, required this.personal});

  final int enNomina;
  final ResumenPersonalReportes personal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final movimientosDeEntrada = personal.altasEnPeriodo.length + personal.reingresosEnPeriodo.length;

    return RisegCard(
      variant: RisegCardVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: AppSizes.iconSm, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.reportesNominaContextoPlantillaTitulo,
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.reportesNominaContextoPlantillaExplicacion,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            children: [
              _CifraContexto(texto: l10n.reportesNominaContextoEnNomina(enNomina)),
              _CifraContexto(texto: l10n.reportesNominaContextoActivos(personal.totalActivos)),
              if (movimientosDeEntrada > 0) _CifraContexto(texto: l10n.reportesNominaContextoAltas(movimientosDeEntrada)),
              if (personal.bajasEnPeriodo.isNotEmpty)
                _CifraContexto(texto: l10n.reportesNominaContextoBajas(personal.bajasEnPeriodo.length)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CifraContexto extends StatelessWidget {
  const _CifraContexto({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: colors.textDisabled, borderRadius: AppRadius.fullRadius),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(texto, style: AppTypography.caption.copyWith(color: colors.textPrimary)),
      ],
    );
  }
}
