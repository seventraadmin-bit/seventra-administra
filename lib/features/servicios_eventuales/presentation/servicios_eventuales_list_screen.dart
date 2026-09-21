import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../data/tables/servicio_eventual_table.dart';
import '../domain/usecases/listar_servicios_eventuales_usecase.dart';
import 'servicios_eventuales_controller.dart';
import 'widgets/servicio_eventual_dialogs.dart';
import 'widgets/servicio_eventual_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Comercial → Eventuales.
///
/// Desde la schemaVersion 88 sí hay cobranza que mostrar: cada
/// eventual tiene su Cuenta por cobrar, así que Cobrado y Pendiente son
/// cifras reales, no un cero de relleno. Se resuelven en lote con el
/// resto del renglón — el listado cuesta lo mismo con 1 que con 100.
class ServiciosEventualesListScreen extends ConsumerWidget {
  const ServiciosEventualesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(serviciosEventualesControllerProvider);
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    final colors = context.colors;

    if (state.errorCarga != null && state.renglones.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.serviciosEventualesCargaErrorTitulo,
        message: l10n.serviciosEventualesCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('servicios_eventuales_boton_reintentar'),
          label: l10n.serviciosEventualesBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.serviciosEventualesListadoTitulo,
            description: l10n.serviciosEventualesListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('servicios_eventuales_boton_registrar'),
              label: l10n.serviciosEventualesBotonRegistrar,
              icon: Icons.add,
              onPressed: () => mostrarDialogoServicioEventual(context, ref),
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
                  label: l10n.serviciosEventualesKpiTotal,
                  value: '${state.renglones.length}',
                  icon: Icons.event_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.serviciosEventualesKpiVenta,
                  value: formatoCentavosPago(state.ventaTotal),
                  icon: Icons.sell_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.serviciosEventualesKpiCosto,
                  value: formatoCentavosPago(state.costoComprometidoTotal),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.serviciosEventualesKpiResultado,
                  value: formatoCentavosPago(state.resultadoTotal),
                  icon: Icons.trending_up,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 200,
            child: RisegSelect<EstatusServicioEventual?>(
              key: const Key('servicios_eventuales_filtro_estatus'),
              label: l10n.serviciosEventualesFiltroEstatus,
              value: state.estatus,
              items: [
                RisegSelectItem(value: null, label: l10n.serviciosEventualesFiltroEstatusTodos),
                for (final estatus in EstatusServicioEventual.values)
                  RisegSelectItem(value: estatus, label: servicioEventualEstatusLabel(l10n, estatus.name)),
              ],
              onChanged: notifier.filtrarPorEstatus,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<RenglonServicioEventual>(
              loading: state.cargando,
              rows: state.renglones,
              onRowTap: (r) => context.go('/comercial/eventuales/${r.servicioEventual.id}'),
              emptyState: RisegEmptyState(
                title: l10n.serviciosEventualesVacioTitulo,
                message: l10n.serviciosEventualesVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaFolio,
                  width: 110,
                  cellBuilder: (r) => Text(
                    r.servicioEventual.folio,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaEvento,
                  cellBuilder: (r) => Text(r.servicioEventual.nombre, overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaSolicitante,
                  cellBuilder: (r) => Text(r.nombreSolicitante, overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaFecha,
                  width: 110,
                  cellBuilder: (r) => Text(_formatoFecha.format(r.servicioEventual.fechaHoraInicio)),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaVenta,
                  width: 120,
                  alignment: TextAlign.right,
                  // El TOTAL derivado, no el importe capturado: con
                  // "Más IVA" son números distintos y el cliente debe el
                  // total. Es el mismo que muestran el expediente y la
                  // Cuenta por cobrar.
                  cellBuilder: (r) => Text(formatoCentavosPago(r.totalVenta)),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaCostos,
                  width: 120,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(formatoCentavosPago(r.totales.costoComprometido)),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaResultado,
                  width: 120,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(
                    formatoCentavosPago(r.resultado),
                    style: AppTypography.bodyStrong.copyWith(
                      // Rojo sólo cuando el evento de verdad pierde
                      // dinero: un resultado en cero no es una alarma.
                      color: r.resultado < 0 ? colors.error : colors.textPrimary,
                    ),
                  ),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.servicioEventualCobroCobrado,
                  width: 120,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(formatoCentavosPago(r.cobrado)),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.servicioEventualCobroPendiente,
                  width: 120,
                  alignment: TextAlign.right,
                  cellBuilder: (r) => Text(formatoCentavosPago(r.pendiente)),
                ),
                RisegColumn<RenglonServicioEventual>(
                  label: l10n.serviciosEventualesColumnaEstatus,
                  width: 120,
                  cellBuilder: (r) => RisegStatusBadge(
                    label: servicioEventualEstatusLabel(l10n, r.servicioEventual.estatus),
                    tone: servicioEventualEstatusTono(r.servicioEventual.estatus),
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
