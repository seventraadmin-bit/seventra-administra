import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_deuda_usecase.dart';

import '../../../finanzas_providers.dart';

/// Diálogo "Cancelar deuda" (Etapa 19) — condona el saldo restante; el
/// historial (`MovimientoDeuda`) nunca se borra. Sin `Egreso`.
///
/// Devuelve `true` si la cancelación tuvo éxito.
Future<bool> mostrarDialogoCancelarDeuda(BuildContext context, WidgetRef ref, {required String deudaId}) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cancelarDeudaDialogoTitulo,
    confirmLabel: l10n.cancelarDeudaBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.cancelarDeudaAdvertencia, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.cancelarDeudaCampoMotivo, controller: motivoCtrl, autofocus: true),
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
        errorGeneral = l10n.cancelarDeudaErrorMotivoRequerido;
        return null;
      }
      final resultado = await ref.read(cancelarDeudaAutorizadoProvider)(deudaId: deudaId, motivo: motivo);
      if (!context.mounted) return false;
      switch (resultado) {
        case CancelarDeudaExitoso():
          RisegFeedback.showSuccess(context, l10n.cancelarDeudaExito);
          return true;
        case CancelarDeudaMotivoRequerido():
          errorGeneral = l10n.cancelarDeudaErrorMotivoRequerido;
          return null;
        case CancelarDeudaNoExiste():
        case CancelarDeudaNoActiva():
          RisegFeedback.showError(context, l10n.cancelarDeudaErrorNoActiva);
          return false;
        case CancelarDeudaErrorInesperado():
          RisegFeedback.showError(context, l10n.cancelarDeudaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  return resultado ?? false;
}
