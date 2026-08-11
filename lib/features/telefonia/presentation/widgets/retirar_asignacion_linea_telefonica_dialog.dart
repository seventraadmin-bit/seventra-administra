import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_asignacion_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Retirar asignación" (Etapa 9B) — libera una línea. Si
/// [tieneEquipoAsociado], expone "mover también el equipo asociado"
/// (en este caso, liberar su custodia en Inventario). Devuelve `true`
/// si tuvo éxito.
Future<bool> mostrarDialogoRetirarAsignacionLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  AsignacionLineaTelefonicaData asignacion, {
  required bool tieneEquipoAsociado,
}) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime fechaTermino = DateTime.now();
  final observacionesCtrl = TextEditingController();
  bool moverEquipoAsociado = true;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaRetirarAsignacionDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaRetirarAsignacionBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.lineaTelefonicaRetirarAsignacionCampoFecha,
                value: fechaTermino,
                onChanged: (valor) => setState(() => fechaTermino = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaRetirarAsignacionCampoObservaciones, controller: observacionesCtrl),
              if (tieneEquipoAsociado) ...[
                const SizedBox(height: AppSpacing.xs),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.lineaTelefonicaCampoMoverEquipoAsociado),
                  value: moverEquipoAsociado,
                  onChanged: (valor) => setState(() => moverEquipoAsociado = valor ?? moverEquipoAsociado),
                ),
              ],
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
      final resultado = await ref.read(retirarAsignacionLineaTelefonicaUseCaseProvider).ejecutar(
            asignacionLineaTelefonicaId: asignacion.id,
            fechaTermino: fechaTermino,
            observacionesTermino: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            moverEquipoAsociado: moverEquipoAsociado,
          );
      switch (resultado) {
        case RetirarAsignacionLineaTelefonicaExitoso():
          if (context.mounted) RisegFeedback.showSuccess(context, l10n.lineaTelefonicaRetirarAsignacionExito);
          return true;
        case RetirarAsignacionLineaTelefonicaYaCerrada():
          errorGeneral = l10n.lineaTelefonicaRetirarAsignacionErrorYaCerrada;
          return null;
        case RetirarAsignacionLineaTelefonicaNoExiste():
        case RetirarAsignacionLineaTelefonicaErrorInesperado():
          if (context.mounted) RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  observacionesCtrl.dispose();
  return resultado ?? false;
}
