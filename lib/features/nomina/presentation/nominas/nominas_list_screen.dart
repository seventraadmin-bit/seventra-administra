import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';

import 'nominas_controller.dart';
import 'nominas_state.dart';
import 'widgets/generar_nomina_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String nominaEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusNomina.values.byName(valor)) {
    EstatusNomina.borrador => l10n.nominaEstatusBorrador,
    EstatusNomina.cerrada => l10n.nominaEstatusCerrada,
    EstatusNomina.pagada => l10n.nominaEstatusPagada,
    EstatusNomina.cancelada => l10n.nominaEstatusCancelada,
  };
}

RisegStatusTone nominaEstatusTono(String valor) {
  return switch (EstatusNomina.values.byName(valor)) {
    EstatusNomina.borrador => RisegStatusTone.warning,
    EstatusNomina.cerrada => RisegStatusTone.success,
    EstatusNomina.pagada => RisegStatusTone.success,
    EstatusNomina.cancelada => RisegStatusTone.neutral,
  };
}

/// Listado de Nóminas (Etapa 6C) — un renglón por periodo generado.
/// El detalle por Empleado (columnas exactas pedidas por Marlon) vive en
/// `NominaDetalleScreen`, una ruta aparte (`/personal/nomina/:id`).
class NominasListScreen extends ConsumerWidget {
  const NominasListScreen({super.key});

  Future<void> _generar(BuildContext context, WidgetRef ref) async {
    await mostrarDialogoGenerarNomina(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(nominasControllerProvider);
    final notifier = ref.read(nominasControllerProvider.notifier);

    if (state.errorCarga != null && state.nominas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.nominasListadoCargaErrorTitulo,
        message: l10n.nominasListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('nominas_boton_reintentar'),
          label: l10n.nominasListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final colors = context.colors;
    final proxima = state.proximaNomina;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.nominasListadoTitulo,
            description: l10n.nominasListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('nominas_boton_generar'),
              label: l10n.nominasListadoBotonGenerar,
              onPressed: () => _generar(context, ref),
            ),
          ),
          // Etapa 17: resumen agregado del conjunto YA FILTRADO
          // (`state.visibles`) — siempre visible, distinto del bloque
          // "Próxima nómina" de abajo (ese es un llamado a la acción
          // sobre la Nómina cerrada más próxima a pagar; este es el
          // total agregado del periodo/estatus seleccionado, incluidas
          // Nóminas en Borrador). Ambos son reales, ninguno inventado.
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 190,
                child: RisegStatCard(dense: true, label: l10n.nominasResumenNominasDelPeriodo, value: '${state.resumenNominasDelPeriodo}'),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(dense: true, label: l10n.nominasResumenTotalNomina, value: formatoCentavosPago(state.resumenTotalNomina)),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.nominasResumenEmpleadosPagadosConsiderados,
                  value: l10n.nominasResumenEmpleadosPagadosConsideradosValor(
                    state.resumenEmpleadosPagados,
                    state.resumenEmpleadosConsiderados,
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.nominasResumenPendiente,
                  value: '${state.resumenNominasPendientes}',
                  deltaTone: state.resumenNominasPendientes > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: RisegSelect<int?>(
                  label: l10n.nominasFiltroAnio,
                  value: state.anioFiltro,
                  items: [
                    RisegSelectItem(value: null, label: l10n.nominasFiltroAnioTodos),
                    for (final anio in state.aniosDisponibles) RisegSelectItem(value: anio, label: '$anio'),
                  ],
                  onChanged: (v) => notifier.aplicarFiltros(anio: v, limpiarAnio: v == null),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<String?>(
                  label: l10n.nominasFiltroEstatus,
                  value: state.estatusFiltro,
                  items: [
                    RisegSelectItem(value: null, label: l10n.nominasFiltroEstatusTodos),
                    for (final e in EstatusNomina.values) RisegSelectItem(value: e.name, label: nominaEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (v) => notifier.aplicarFiltros(estatus: v, limpiarEstatus: v == null),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos ? notifier.limpiarTodosLosFiltros : null,
              ),
            ],
          ),
          // Etapa 16, evolución visual — resumen superior SOLO cuando
          // existe una Nómina `cerrada` real pendiente de pago: nunca un
          // "total estimado" para un periodo que aún no se ha generado
          // (esa cifra no existe hasta entonces).
          if (proxima != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(
                  width: 210,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.nominasKpiProximaNomina,
                    value: _formatoFecha.format(proxima.nomina.fechaPagoOrdinaria),
                    delta: periodoNominaTexto(l10n, proxima.nomina),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.nominasKpiPersonalIncluido,
                    value: l10n.nominasKpiPersonalIncluidoValor(proxima.totalEmpleados),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.nominasKpiTotalAPagar,
                    value: formatoCentavosPago(proxima.totalAPagar),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          RisegTableBase<NominaResumen>(
            loading: state.cargando,
            rows: state.visibles,
            onRowTap: (r) => context.go('/personal/nomina/${r.nomina.id}'),
            emptyState: RisegEmptyState(
              title: l10n.nominasListadoVacioTitulo,
              message: l10n.nominasListadoVacioMensaje,
            ),
            hoverColor: colors.accentSoftBg,
            rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
            rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
            actionsWidth: 40,
            columns: [
              // Etapa 16, evolución visual: el PERIODO es la información
              // principal (antes era el folio) — el folio pasa a
              // secundario, mismo criterio de jerarquía que
              // "Plantilla activa" (aunque una Nómina no tiene
              // avatar/identidad de persona, así que no se fuerza
              // `RisegEntityIdentity` aquí — solo se replica el patrón
              // "primario en negrita + secundario muted, apilados").
              RisegColumn<NominaResumen>(
                label: l10n.nominasColumnaPeriodo,
                cellBuilder: (r) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(periodoNominaTexto(l10n, r.nomina), style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(r.nomina.folio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
              RisegColumn<NominaResumen>(
                label: l10n.nominasColumnaFechaPago,
                width: 120,
                cellBuilder: (r) => Text(_formatoFecha.format(r.nomina.fechaPagoOrdinaria)),
              ),
              RisegColumn<NominaResumen>(
                label: l10n.nominasColumnaEmpleados,
                width: 100,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(r.totalEmpleados.toString()),
              ),
              RisegColumn<NominaResumen>(
                label: l10n.nominasColumnaTotal,
                width: 130,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(formatoCentavosPago(r.totalAPagar), style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
              ),
              RisegColumn<NominaResumen>(
                label: l10n.nominasColumnaEstatus,
                width: 130,
                cellBuilder: (r) =>
                    RisegStatusBadge(label: nominaEstatusLabel(l10n, r.nomina.estatus), tone: nominaEstatusTono(r.nomina.estatus)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Texto "{tipo de periodo} · {año}-{mes}" — reutilizado tal cual por
/// `NominaDetalleScreen` (Etapa 16, evolución visual) para que el
/// listado y el detalle nunca muestren el periodo con un formato
/// distinto.
String periodoNominaTexto(AppLocalizations l10n, NominaData nomina) {
  return '${nominaTipoPeriodoLabel(l10n, TipoPeriodoNomina.values.byName(nomina.tipoPeriodo))} · '
      '${nomina.anio}-${nomina.mes.toString().padLeft(2, '0')}';
}
