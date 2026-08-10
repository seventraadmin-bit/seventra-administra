import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
  };
}

RisegStatusTone nominaEstatusTono(String valor) {
  return switch (EstatusNomina.values.byName(valor)) {
    EstatusNomina.borrador => RisegStatusTone.warning,
    EstatusNomina.cerrada => RisegStatusTone.success,
    EstatusNomina.pagada => RisegStatusTone.success,
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

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.nominasListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('nominas_boton_generar'),
              label: l10n.nominasListadoBotonGenerar,
              onPressed: () => _generar(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<NominaResumen>(
              loading: state.cargando,
              rows: state.nominas,
              onRowTap: (r) => context.go('/personal/nomina/${r.nomina.id}'),
              emptyState: RisegEmptyState(
                title: l10n.nominasListadoVacioTitulo,
                message: l10n.nominasListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<NominaResumen>(
                  label: l10n.nominasColumnaFolio,
                  width: 110,
                  cellBuilder: (r) => Text(r.nomina.folio),
                ),
                RisegColumn<NominaResumen>(
                  label: l10n.nominasColumnaPeriodo,
                  cellBuilder: (r) => Text(
                    '${r.nomina.anio}-${r.nomina.mes.toString().padLeft(2, '0')} · '
                    '${nominaTipoPeriodoLabel(l10n, TipoPeriodoNomina.values.byName(r.nomina.tipoPeriodo))}',
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
                  cellBuilder: (r) => Text(formatoCentavosPago(r.totalAPagar)),
                ),
                RisegColumn<NominaResumen>(
                  label: l10n.nominasColumnaEstatus,
                  width: 130,
                  cellBuilder: (r) =>
                      RisegStatusBadge(label: nominaEstatusLabel(l10n, r.nomina.estatus), tone: nominaEstatusTono(r.nomina.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
