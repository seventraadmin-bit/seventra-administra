import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/periodo_dashboard.dart';

/// Selector de periodo de la cabecera del Dashboard (Parte B del
/// rediseño gerencial) — Hoy | Semana | Mes | Personalizado, única
/// fuente de verdad del rango vía [PeriodoDashboard]. "Personalizado"
/// abre un diálogo con Fecha inicial → Fecha final (reutiliza
/// `RisegDateField`, mismo componente ya usado en Reportes).
class PeriodoSelector extends StatelessWidget {
  const PeriodoSelector({required this.periodo, required this.onChanged, super.key});

  final PeriodoDashboard periodo;
  final ValueChanged<PeriodoDashboard> onChanged;

  Future<void> _elegirPersonalizado(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    DateTime? inicio = periodo.tipo == TipoPeriodoDashboard.personalizado ? periodo.inicio : null;
    DateTime? fin = periodo.tipo == TipoPeriodoDashboard.personalizado ? periodo.fin : null;
    String? error;

    final resultado = await RisegDialog.showForm<PeriodoDashboard>(
      context: context,
      title: l10n.dashboardPeriodoPersonalizadoTitulo,
      confirmLabel: l10n.dashboardPeriodoPersonalizadoConfirmar,
      cancelLabel: l10n.dashboardPeriodoPersonalizadoCancelar,
      contentBuilder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegDateField(
                  label: l10n.dashboardPeriodoPersonalizadoFechaInicial,
                  value: inicio,
                  onChanged: (v) => setState(() => inicio = v),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegDateField(
                  label: l10n.dashboardPeriodoPersonalizadoFechaFinal,
                  value: fin,
                  onChanged: (v) => setState(() => fin = v),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(error!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          );
        },
      ),
      onConfirm: () async {
        if (inicio == null || fin == null) {
          error = l10n.dashboardPeriodoPersonalizadoErrorFechasRequeridas;
          return null;
        }
        if (fin!.isBefore(inicio!)) {
          error = l10n.dashboardPeriodoPersonalizadoErrorRangoInvalido;
          return null;
        }
        return PeriodoDashboard.personalizado(inicio: inicio!, fin: fin!);
      },
    );

    if (resultado != null) onChanged(resultado);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ahora = DateTime.now();

    Widget opcion(String label, TipoPeriodoDashboard tipo, VoidCallback onTap) {
      final seleccionado = periodo.tipo == tipo;
      return RisegButton(
        label: label,
        variant: seleccionado ? RisegButtonVariant.primary : RisegButtonVariant.secondary,
        size: RisegButtonSize.compact,
        onPressed: onTap,
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        opcion(l10n.dashboardPeriodoHoy, TipoPeriodoDashboard.hoy, () => onChanged(PeriodoDashboard.hoy(ahora))),
        opcion(l10n.dashboardPeriodoSemana, TipoPeriodoDashboard.semana, () => onChanged(PeriodoDashboard.semana(ahora))),
        opcion(l10n.dashboardPeriodoMes, TipoPeriodoDashboard.mes, () => onChanged(PeriodoDashboard.mes(ahora))),
        opcion(l10n.dashboardPeriodoPersonalizado, TipoPeriodoDashboard.personalizado, () => _elegirPersonalizado(context)),
      ],
    );
  }
}
