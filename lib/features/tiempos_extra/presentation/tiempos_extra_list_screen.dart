import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import 'tiempos_extra_controller.dart';
import 'tiempos_extra_state.dart';
import 'widgets/registrar_tiempo_extra_dialog.dart';
import 'widgets/tiempo_extra_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Pantalla global "Tiempos Extra" (cobertura operativa por ausencia,
/// pedido explícito de Marlon) — KPIs + tabla + filtros por rango de
/// fecha, mismo patrón que `DescuentosPersonalListScreen`.
class TiemposExtraListScreen extends ConsumerWidget {
  const TiemposExtraListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(tiemposExtraControllerProvider);
    final notifier = ref.read(tiemposExtraControllerProvider.notifier);
    final colors = context.colors;

    if (state.errorCarga != null && state.registros.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.tiemposExtraCargaErrorTitulo,
        message: l10n.tiemposExtraCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('tiempos_extra_boton_reintentar'),
          label: l10n.tiemposExtraBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final hayFiltrosActivos = state.servicioId != null || state.estatus != null || state.rangoInicio != null || state.rangoFin != null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.tiemposExtraListadoTitulo,
            description: l10n.tiemposExtraListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('tiempos_extra_boton_registrar'),
              label: l10n.tiemposExtraBotonRegistrar,
              icon: Icons.add,
              onPressed: () async {
                final registrado = await mostrarDialogoRegistrarTiempoExtra(context, ref);
                if (registrado) notifier.reintentarCarga();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.tiemposExtraKpiTotalRegistros,
                  value: '${state.resumen.totalRegistros}',
                  icon: Icons.schedule_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.tiemposExtraKpiGastoTotal,
                  value: formatoCentavosPago(state.resumen.gastoTotal),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.tiemposExtraKpiServiciosCubiertos,
                  value: '${state.resumen.porServicio.length}',
                  icon: Icons.shield_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.tiemposExtraFiltroDesde,
                  value: state.rangoInicio,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoInicio: valor),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.tiemposExtraFiltroHasta,
                  value: state.rangoFin,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoFin: valor),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<String?>(
                  label: l10n.tiemposExtraFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.tiemposExtraFiltroEstatusTodos),
                    RisegSelectItem(value: 'registrado', label: l10n.tiemposExtraEstatusRegistrado),
                    RisegSelectItem(value: 'cancelado', label: l10n.tiemposExtraEstatusCancelado),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: hayFiltrosActivos
                    ? () => notifier.aplicarFiltros(limpiarServicioId: true, limpiarEstatus: true, limpiarRango: true)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<TiempoExtraResumen>(
              loading: state.cargando,
              rows: state.registros,
              onRowTap: (r) => context.go('/personal/tiempos-extra/${r.tiempoExtra.id}'),
              emptyState: RisegEmptyState(title: l10n.tiemposExtraVacioTitulo, message: l10n.tiemposExtraVacioMensaje),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaFolio,
                  width: 100,
                  cellBuilder: (r) => Text(r.tiempoExtra.folio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                ),
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaFecha,
                  width: 100,
                  cellBuilder: (r) => Text(_formatoFecha.format(r.tiempoExtra.fecha)),
                ),
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaServicio,
                  cellBuilder: (r) => Text(r.servicioNombre, overflow: TextOverflow.ellipsis),
                ),
                // Una sola columna compacta para el origen (§20): no
                // hacen falta cinco columnas para distinguir por qué
                // hubo que cubrir el turno.
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaOrigen,
                  width: 110,
                  cellBuilder: (r) => Text(
                    origenCoberturaTiempoExtraLabelCorto(l10n, r.tiempoExtra.origenCobertura),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaQuienCubre,
                  cellBuilder: (r) => Text(r.nombreCubre, overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaTurno,
                  width: 110,
                  cellBuilder: (r) => Text(r.turnoNombre),
                ),
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaMonto,
                  width: 120,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(
                    formatoCentavosPago(r.montoTotal),
                    style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegColumn<TiempoExtraResumen>(
                  label: l10n.tiemposExtraColumnaEstatus,
                  width: 120,
                  cellBuilder: (r) => RisegStatusBadge(
                    label: tiempoExtraEstatusLabel(l10n, r.tiempoExtra.estatus),
                    tone: tiempoExtraEstatusTono(r.tiempoExtra.estatus),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
