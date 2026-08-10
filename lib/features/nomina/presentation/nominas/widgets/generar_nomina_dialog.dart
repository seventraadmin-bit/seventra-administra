import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';

import '../nominas_controller.dart';

String nominaTipoPeriodoLabel(AppLocalizations l10n, TipoPeriodoNomina tipo) {
  return switch (tipo) {
    TipoPeriodoNomina.primera => l10n.nominaTipoPeriodoPrimera,
    TipoPeriodoNomina.segunda => l10n.nominaTipoPeriodoSegunda,
  };
}

/// Diálogo "Generar nómina" (Etapa 6C) — pide año/mes/periodo y dispara
/// `GenerarNominaUseCase`. Nunca automático: siempre una acción
/// explícita del usuario (Resolución explícita de Marlon).
///
/// Devuelve `true` si la generación tuvo éxito.
Future<bool> mostrarDialogoGenerarNomina(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final hoy = DateTime.now();
  int anio = hoy.year;
  int mes = hoy.month;
  TipoPeriodoNomina tipo = TipoPeriodoNomina.primera;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.generarNominaDialogoTitulo,
    confirmLabel: l10n.generarNominaBotonConfirmar,
    cancelLabel: l10n.generarNominaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegSelect<int>(
              label: l10n.generarNominaCampoAnio,
              value: anio,
              items: [
                for (var a = hoy.year - 1; a <= hoy.year + 1; a++) RisegSelectItem(value: a, label: a.toString()),
              ],
              onChanged: (valor) => setState(() => anio = valor ?? anio),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<int>(
              label: l10n.generarNominaCampoMes,
              value: mes,
              items: [for (var m = 1; m <= 12; m++) RisegSelectItem(value: m, label: m.toString().padLeft(2, '0'))],
              onChanged: (valor) => setState(() => mes = valor ?? mes),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<TipoPeriodoNomina>(
              label: l10n.generarNominaCampoTipoPeriodo,
              value: tipo,
              items: [
                for (final t in TipoPeriodoNomina.values) RisegSelectItem(value: t, label: nominaTipoPeriodoLabel(l10n, t)),
              ],
              onChanged: (valor) => setState(() => tipo = valor ?? tipo),
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(nominasControllerProvider.notifier).generar(anio: anio, mes: mes, tipo: tipo);
      if (!context.mounted) return false;

      switch (resultado) {
        case GenerarNominaExitoso(empleadosExcluidos: final excluidos):
          RisegFeedback.showSuccess(context, excluidos.isEmpty ? l10n.generarNominaExito : l10n.generarNominaExitoConExcluidos);
          return true;
        case GenerarNominaYaExiste():
          RisegFeedback.showError(context, l10n.generarNominaYaExiste);
          return false;
        case GenerarNominaSinEmpleados():
          RisegFeedback.showError(context, l10n.generarNominaSinEmpleados);
          return false;
        case GenerarNominaErrorInesperado():
          RisegFeedback.showError(context, l10n.generarNominaErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}
