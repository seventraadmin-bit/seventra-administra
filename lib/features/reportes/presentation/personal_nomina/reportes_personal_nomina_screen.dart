import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/personal/presentation/empleados/widgets/baja_laboral_empleado_dialog.dart' show motivoBajaEmpleadoLabel;
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';

import '../widgets/reportes_filtro_bar.dart';
import 'reportes_personal_nomina_controller.dart';

/// Pestaña Personal · Nómina de Reportes (Etapa 12B) — dos subsecciones
/// independientes, cada una omitida por completo si falta su permiso.
/// La subsección Personal nunca muestra una cifra en pesos (regla de
/// diseño explícita, ver el plan técnico) — los montos viven
/// exclusivamente en la subsección Nómina.
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
          RisegSectionHeader(title: l10n.reportesPersonalNominaTitulo, description: l10n.reportesPersonalNominaDescripcion),
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
          else ...[
            if (!controller.tienePersonal && !controller.tieneNomina)
              RisegEmptyState(
                icon: Icons.lock_outline,
                title: l10n.reportesSinSeccionesTitulo,
                message: l10n.reportesSinSeccionesMensaje,
              )
            else ...[
              if (controller.tienePersonal && state.resumenPersonal != null) ...[
                _SeccionPersonal(l10n: l10n, resumen: state.resumenPersonal!),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (controller.tieneNomina && state.resumenNomina != null) _SeccionNomina(l10n: l10n, resumen: state.resumenNomina!),
            ],
          ],
        ],
      ),
    );
  }
}

class _SeccionPersonal extends StatelessWidget {
  const _SeccionPersonal({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenPersonalReportes resumen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.reportesPersonalSeccionTitulo, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            RisegStatCard(label: l10n.reportesPersonalActivos, value: '${resumen.totalActivos}', icon: Icons.people_outline),
            RisegStatCard(label: l10n.reportesPersonalAdministrativos, value: '${resumen.totalAdministrativos}'),
            RisegStatCard(label: l10n.reportesPersonalOperativos, value: '${resumen.totalOperativos}'),
            RisegStatCard(label: l10n.reportesPersonalAltas, value: '${resumen.altasEnPeriodo.length}'),
            RisegStatCard(label: l10n.reportesPersonalReingresos, value: '${resumen.reingresosEnPeriodo.length}'),
            RisegStatCard(label: l10n.reportesPersonalBajas, value: '${resumen.bajasEnPeriodo.length}'),
            RisegStatCard(
              label: l10n.reportesPersonalProximosAniversarios,
              value: '${resumen.proximosAniversarios.length}',
            ),
            RisegStatCard(
              label: l10n.reportesPersonalAlertasRecontratacion,
              value: '${resumen.alertasRecontratacion.length}',
              deltaTone: resumen.alertasRecontratacion.isEmpty ? null : RisegStatusTone.warning,
              delta: resumen.alertasRecontratacion.isEmpty ? null : l10n.reportesPersonalRevisarAntesDeContratar,
            ),
          ],
        ),
        if (resumen.motivosBajaConteo.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          RisegCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportesPersonalMotivosBajaTitulo, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final entrada in resumen.motivosBajaConteo.entries)
                      Text('${motivoBajaEmpleadoLabel(l10n, entrada.key.name)}: ${entrada.value}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SeccionNomina extends StatelessWidget {
  const _SeccionNomina({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenNominaReportes resumen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.reportesNominaSeccionTitulo, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            RisegStatCard(label: l10n.reportesNominaTotalGenerado, value: formatoCentavosPago(resumen.totalGeneradoGlobal)),
            RisegStatCard(label: l10n.reportesNominaTotalPagado, value: formatoCentavosPago(resumen.totalPagadoGlobal)),
            RisegStatCard(
              label: l10n.reportesNominaSaldoPendiente,
              value: formatoCentavosPago(resumen.totalPendienteGlobal),
              deltaTone: resumen.totalPendienteGlobal > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
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
              width: 140,
              cellBuilder: (n) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(n.nomina.estatus),
                  if (n.esPagoParcial) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Text('· ${l10n.reportesNominaPagoParcial}'),
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
