import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';

import '../planeacion/planeacion_financiera_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
import 'cuentas_financieras_controller.dart';
import 'widgets/registrar_cuenta_financiera_dialog.dart';
import 'widgets/transferir_entre_cuentas_dialog.dart';

final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavosCuentaFinanciera(int centavos) => _formatoMoneda.format(centavos / 100);

String cuentaFinancieraTipoLabel(AppLocalizations l10n, String tipo) {
  return switch (TipoCuentaFinanciera.values.byName(tipo)) {
    TipoCuentaFinanciera.banco => l10n.cuentaFinancieraTipoBanco,
    TipoCuentaFinanciera.efectivo => l10n.cuentaFinancieraTipoEfectivo,
  };
}

/// Listado de Cuentas financieras (Etapa 19C, Parte B) — universo
/// pequeño esperado (unas cuantas cuentas por empresa), así que
/// muestra activas e inactivas juntas con badge de estatus, sin
/// filtros de servidor. El saldo por cuenta se resuelve en lote
/// (`CuentasFinancierasController._cargar`), nunca una consulta por
/// fila.
class CuentasFinancierasListScreen extends ConsumerWidget {
  const CuentasFinancierasListScreen({super.key});

  Future<void> _registrar(BuildContext context, WidgetRef ref) async {
    final registrada = await mostrarDialogoRegistrarCuentaFinanciera(context, ref);
    if (registrada) {
      ref.read(cuentasFinancierasControllerProvider.notifier).reintentarCarga();
      // El saldo inicial de la nueva cuenta cambia la posición de caja
      // — Resumen financiero y Planeación son providers ajenos que
      // nunca se enteraban de esta cuenta nueva.
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final state = ref.watch(cuentasFinancierasControllerProvider);
    final notifier = ref.read(cuentasFinancierasControllerProvider.notifier);

    if (state.errorCarga != null && state.cuentas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.cuentasFinancierasListadoCargaErrorTitulo,
        message: l10n.cuentasFinancierasListadoCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.deudasCreditoListadoBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }

    final cuentas = state.cuentas;
    final activas = cuentas.where((c) => c.cicloVidaRegistro == 'activo').toList();
    final saldoTotal = activas.fold<int>(0, (acc, c) => acc + (state.saldosPorCuenta[c.id] ?? 0));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.cuentasFinancierasListadoTitulo,
            description: l10n.cuentasFinancierasListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('cuentas_financieras_boton_registrar'),
              label: l10n.cuentasFinancierasBotonRegistrar,
              onPressed: () => _registrar(context, ref),
            ),
            // Mover dinero entre cuentas propias vive aquí, junto a las
            // cuentas: no es un módulo nuevo del menú lateral.
            secondaryAction: RisegButton(
              key: const Key('cuentas_financieras_boton_transferir'),
              label: l10n.transferirAccion,
              variant: RisegButtonVariant.secondary,
              onPressed: () => mostrarDialogoTransferir(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnas = constraints.maxWidth < AppBreakpoints.compact ? 1 : 2;
              final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: ancho,
                    child: RisegStatCard(label: l10n.cuentasFinancierasKpiSaldoTotal, value: formatoCentavosCuentaFinanciera(saldoTotal), dense: true),
                  ),
                  SizedBox(
                    width: ancho,
                    child: RisegStatCard(label: l10n.cuentasFinancierasKpiCuentasActivas, value: '${activas.length}', dense: true),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<CuentaFinancieraData>(
              loading: state.cargando,
              rows: cuentas,
              onRowTap: (c) => context.push('/finanzas/cuentas-financieras/${c.id}'),
              emptyState: RisegEmptyState(
                title: l10n.cuentasFinancierasListadoVacioTitulo,
                message: l10n.cuentasFinancierasListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<CuentaFinancieraData>(
                  label: l10n.cuentasFinancierasColumnaCuenta,
                  cellBuilder: (c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        c.ultimosDigitos == null ? c.codigo : '${c.codigo} · ****${c.ultimosDigitos}',
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                RisegColumn<CuentaFinancieraData>(
                  label: l10n.cuentasFinancierasColumnaTipo,
                  width: 130,
                  cellBuilder: (c) => Text(cuentaFinancieraTipoLabel(l10n, c.tipo)),
                ),
                RisegColumn<CuentaFinancieraData>(
                  label: l10n.cuentasFinancierasColumnaSaldo,
                  width: 150,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(
                    formatoCentavosCuentaFinanciera(state.saldosPorCuenta[c.id] ?? 0),
                    style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegColumn<CuentaFinancieraData>(
                  label: l10n.cuentasFinancierasColumnaEstatus,
                  width: 130,
                  cellBuilder: (c) => RisegStatusBadge(
                    label: c.cicloVidaRegistro == 'activo' ? l10n.cuentaFinancieraEstatusActiva : l10n.cuentaFinancieraEstatusInactiva,
                    tone: c.cicloVidaRegistro == 'activo' ? RisegStatusTone.success : RisegStatusTone.neutral,
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
