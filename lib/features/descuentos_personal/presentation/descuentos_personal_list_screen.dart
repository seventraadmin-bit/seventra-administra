import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formatoCentavosPago;

import 'descuentos_personal_controller.dart';
import 'descuentos_personal_state.dart';
import 'widgets/registrar_descuento_programado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String descuentoProgramadoTipoLabel(AppLocalizations l10n, String tipo) {
  return tipo == 'botas'
      ? l10n.descuentosPersonalTipoBotas
      : l10n.descuentosPersonalTipoPrestamo;
}

String descuentoProgramadoEstatusLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'liquidado' => l10n.descuentosPersonalEstatusLiquidado,
    'cancelado' => l10n.descuentosPersonalEstatusCancelado,
    _ => l10n.descuentosPersonalEstatusActivo,
  };
}

RisegStatusTone descuentoProgramadoEstatusTono(String estatus) {
  return switch (estatus) {
    'liquidado' => RisegStatusTone.success,
    'cancelado' => RisegStatusTone.neutral,
    _ => RisegStatusTone.info,
  };
}

String _filtroLabel(AppLocalizations l10n, DescuentosPersonalFiltro filtro) {
  return switch (filtro) {
    DescuentosPersonalFiltro.todos => l10n.descuentosPersonalFiltroTodos,
    DescuentosPersonalFiltro.prestamos =>
      l10n.descuentosPersonalFiltroPrestamos,
    DescuentosPersonalFiltro.botas => l10n.descuentosPersonalFiltroBotas,
    DescuentosPersonalFiltro.liquidados =>
      l10n.descuentosPersonalFiltroLiquidados,
  };
}

/// Pantalla global "Descuentos al Personal" (Etapa 15) — préstamos,
/// costo de botas y futuros tipos, con su plan de recuperación
/// automático vía Nómina. KPIs + tabla + filtros, mismo patrón que
/// `NominasListScreen`.
class DescuentosPersonalListScreen extends ConsumerWidget {
  const DescuentosPersonalListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(descuentosPersonalControllerProvider);
    final notifier = ref.read(descuentosPersonalControllerProvider.notifier);
    final colors = context.colors;

    if (state.errorCarga != null && state.descuentos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.descuentosPersonalCargaErrorTitulo,
        message: l10n.descuentosPersonalCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('descuentos_personal_boton_reintentar'),
          label: l10n.descuentosPersonalBotonReintentar,
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
            title: l10n.descuentosPersonalListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('descuentos_personal_boton_registrar'),
              label: l10n.descuentosPersonalBotonRegistrar,
              onPressed:
                  () =>
                      mostrarDialogoRegistrarDescuentoProgramado(context, ref),
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
                  label: l10n.descuentosPersonalKpiSaldoPendiente,
                  value: formatoCentavosPago(state.kpis.saldoPendienteTotal),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.descuentosPersonalKpiPrestamosActivos,
                  value: '${state.kpis.prestamosActivos}',
                  icon: Icons.request_quote_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.descuentosPersonalKpiCobrosProximos,
                  value: '${state.kpis.cobrosProximos}',
                  icon: Icons.event_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.descuentosPersonalKpiEmpleadosConSaldo,
                  value: '${state.kpis.empleadosConSaldo}',
                  icon: Icons.groups_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // División primaria (pedido explícito) — separa descuentos
          // activos (incluye liquidados) de los ya cancelados, antes de
          // cualquier otro filtro más granular.
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                key: const Key('descuentos_personal_grupo_activos'),
                label: Text(l10n.descuentosPersonalFiltroActivos),
                selected: state.grupo == GrupoEstadoDescuento.activos,
                onSelected: (_) => notifier.cambiarGrupo(GrupoEstadoDescuento.activos),
              ),
              ChoiceChip(
                key: const Key('descuentos_personal_grupo_cancelados'),
                label: Text(l10n.descuentosPersonalFiltroCancelados),
                selected: state.grupo == GrupoEstadoDescuento.cancelados,
                onSelected: (_) => notifier.cambiarGrupo(GrupoEstadoDescuento.cancelados),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final filtro in DescuentosPersonalFiltro.values)
                ChoiceChip(
                  label: Text(_filtroLabel(l10n, filtro)),
                  selected: state.filtro == filtro,
                  onSelected: (_) => notifier.cambiarFiltro(filtro),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<DescuentoProgramadoResumen>(
              loading: state.cargando,
              rows: state.visibles,
              onRowTap:
                  (r) => context.go('/personal/descuentos/${r.descuento.id}'),
              emptyState: RisegEmptyState(
                title: l10n.descuentosPersonalVacioTitulo,
                message: l10n.descuentosPersonalVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder:
                  (_) => Icon(
                    Icons.chevron_right,
                    size: AppSizes.iconMd,
                    color: colors.textMuted,
                  ),
              actionsWidth: 40,
              columns: [
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaFolio,
                  width: 100,
                  cellBuilder:
                      (r) => Text(
                        r.descuento.folio,
                        style: AppTypography.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                ),
                // Etapa 16, evolución visual: identidad del Empleado igual
                // que "Plantilla activa" — foto/iniciales + nombre +
                // No. de empleado, nunca solo el nombre suelto.
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaEmpleado,
                  cellBuilder:
                      (r) => RisegEntityIdentity(
                        primario: r.empleadoNombre,
                        secundario:
                            r.numeroEmpleado == null
                                ? null
                                : l10n.personalActivoNumeroEmpleado(
                                  r.numeroEmpleado!,
                                ),
                        imagenPath:
                            state.fotografiaPathPorEmpleadoId[r
                                .descuento
                                .empleadoId],
                      ),
                ),
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaTipo,
                  width: 100,
                  cellBuilder:
                      (r) => Text(
                        descuentoProgramadoTipoLabel(l10n, r.descuento.tipo),
                      ),
                ),
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaFecha,
                  width: 100,
                  cellBuilder:
                      (r) =>
                          Text(_formatoFecha.format(r.descuento.fechaRegistro)),
                ),
                // Etapa 16: "Importe original"/"Pagado" se fusionan en una
                // representación compacta de progreso (pedido explícito:
                // nunca una columna gigante, solo texto secundario + barra
                // delgada); `cancelado` nunca muestra la barra como si
                // siguiera cobrándose (ver `progresoPorcentaje`).
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaProgreso,
                  width: 150,
                  cellBuilder: (r) {
                    // `cancelarSaldo` deja `saldoPendiente = 0` (condonado,
                    // nunca pagado) — para un `cancelado`, `recuperado`
                    // (importeOriginal - saldoPendiente) queda igual al
                    // importe original y NO representa lo realmente
                    // cobrado; mostrar "$X de $X pagados" ahí sería
                    // engañoso (pedido explícito: nunca como si siguiera
                    // cobrándose). Se muestra un texto distinto, sin barra.
                    if (r.descuento.estatus == 'cancelado') {
                      return Text(
                        l10n.descuentosPersonalProgresoCancelado,
                        style: AppTypography.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      );
                    }
                    final progreso = r.progresoPorcentaje!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.descuentosPersonalProgresoTexto(
                            formatoCentavosPago(r.recuperado),
                            formatoCentavosPago(r.descuento.importeOriginal),
                          ),
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RisegProgressBar(
                          porcentaje: progreso,
                          tone:
                              progreso >= 100
                                  ? RisegStatusTone.success
                                  : RisegStatusTone.info,
                        ),
                      ],
                    );
                  },
                ),
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaSaldo,
                  width: 110,
                  alignment: TextAlign.right,
                  cellBuilder:
                      (r) => Text(
                        formatoCentavosPago(r.descuento.saldoPendiente),
                        style: AppTypography.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                ),
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaProximaCuota,
                  width: 110,
                  cellBuilder:
                      (r) => Text(
                        r.proximaCuota == null
                            ? '—'
                            : _formatoFecha.format(
                              r.proximaCuota!.fechaProgramada,
                            ),
                      ),
                ),
                RisegColumn<DescuentoProgramadoResumen>(
                  label: l10n.descuentosPersonalColumnaEstatus,
                  width: 120,
                  cellBuilder:
                      (r) => RisegStatusBadge(
                        label: descuentoProgramadoEstatusLabel(
                          l10n,
                          r.descuento.estatus,
                        ),
                        tone: descuentoProgramadoEstatusTono(
                          r.descuento.estatus,
                        ),
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
