import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/cancelar_tiempo_extra_usecase.dart';
import '../tiempos_extra_controller.dart';

/// "Cancelar tiempo extra" — cancela también el Egreso vinculado (ver
/// `TiempoExtraRepositoryImpl.cancelar`). `motivo` obligatorio, mismo
/// patrón que `mostrarDialogoCancelarSaldoDescuentoProgramado`.
Future<bool> mostrarDialogoCancelarTiempoExtra(BuildContext context, WidgetRef ref, String tiempoExtraId) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cancelarTiempoExtraDialogoTitulo,
    confirmLabel: l10n.cancelarTiempoExtraBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.cancelarTiempoExtraAdvertencia, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.cancelarTiempoExtraCampoMotivo, controller: motivoCtrl, autofocus: true),
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
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.cancelarTiempoExtraErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(tiemposExtraControllerProvider.notifier).cancelar(tiempoExtraId: tiempoExtraId, motivo: motivo);
      if (!context.mounted) return false;

      switch (resultado) {
        case CancelarTiempoExtraExitoso():
          RisegFeedback.showSuccess(context, l10n.cancelarTiempoExtraExito);
          return true;
        case CancelarTiempoExtraYaCancelado():
        case CancelarTiempoExtraNoExiste():
          RisegFeedback.showError(context, l10n.cancelarTiempoExtraErrorNoActivo);
          return false;
        case CancelarTiempoExtraErrorInesperado():
          RisegFeedback.showError(context, l10n.cancelarTiempoExtraErrorInesperado);
          return false;
      }
    },
  );

  motivoCtrl.dispose();
  return resultado ?? false;
}
