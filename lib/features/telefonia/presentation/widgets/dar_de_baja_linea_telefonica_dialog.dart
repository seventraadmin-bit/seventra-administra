import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';

import '../linea_telefonica_labels.dart';
import '../telefonia_controller.dart';

/// Baja terminal de una línea telefónica (Etapa 9A) — devuelve `true`
/// si tuvo éxito, mismo patrón que `mostrarDialogoDarDeBajaVehiculo`.
Future<bool> mostrarDialogoDarDeBajaLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  LineaTelefonicaData linea,
) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(telefoniaControllerProvider.notifier);

  MotivoBajaLineaTelefonica motivo = MotivoBajaLineaTelefonica.cancelacion;
  DateTime fecha = DateTime.now();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaDarDeBajaDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaDarDeBajaBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<MotivoBajaLineaTelefonica>(
                label: l10n.lineaTelefonicaDarDeBajaCampoMotivo,
                value: motivo,
                items: [
                  for (final m in MotivoBajaLineaTelefonica.values)
                    RisegSelectItem(value: m, label: motivoBajaLineaTelefonicaLabel(l10n, m)),
                ],
                onChanged: (valor) => setState(() => motivo = valor ?? motivo),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaDarDeBajaCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaDarDeBajaCampoObservaciones, controller: observacionesCtrl),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final resultado = await notifier.darDeBaja(
        lineaTelefonicaId: linea.id,
        fechaBaja: fecha,
        motivoBaja: motivo,
        observacionesBaja: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      switch (resultado) {
        case DarDeBajaLineaTelefonicaExitoso():
          if (context.mounted) RisegFeedback.showSuccess(context, l10n.lineaTelefonicaDarDeBajaExito);
          return true;
        case DarDeBajaLineaTelefonicaObservacionesRequeridas():
          errorGeneral = l10n.lineaTelefonicaDarDeBajaErrorObservacionesRequeridas;
          return null;
        case DarDeBajaLineaTelefonicaNoExiste():
        case DarDeBajaLineaTelefonicaYaDeBaja():
        case DarDeBajaLineaTelefonicaErrorInesperado():
          if (context.mounted) RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  observacionesCtrl.dispose();
  return resultado ?? false;
}
