import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formatoCentavosPago;

import '../../domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import '../descuentos_personal_controller.dart';

/// "Cancelar saldo" (Etapa 15) — condona el saldo pendiente
/// (`pendiente`/`reservada`), conserva íntegro lo ya recuperado
/// (cuotas `aplicada`). `motivo` obligatorio, mismo patrón que
/// `mostrarDialogoEliminarCadenaPruebaNomina`.
Future<bool> mostrarDialogoCancelarSaldoDescuentoProgramado(
  BuildContext context,
  WidgetRef ref,
  DescuentoProgramadoEmpleadoData descuento,
) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cancelarSaldoDialogoTitulo,
    confirmLabel: l10n.cancelarSaldoBotonConfirmar,
    cancelLabel: l10n.registrarDescuentoProgramadoBotonCancelar,
    contentBuilder:
        (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) {
            return SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.cancelarSaldoAdvertencia(
                      formatoCentavosPago(descuento.saldoPendiente),
                    ),
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    label: l10n.cancelarSaldoCampoMotivo,
                    controller: motivoCtrl,
                    autofocus: true,
                  ),
                  if (errorGeneral != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      errorGeneral!,
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
    onConfirm: () async {
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.cancelarSaldoErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref
          .read(descuentosPersonalControllerProvider.notifier)
          .cancelarSaldo(descuentoProgramadoId: descuento.id, motivo: motivo);
      if (!context.mounted) return false;

      switch (resultado) {
        case CancelarSaldoDescuentoProgramadoExitoso():
          RisegFeedback.showSuccess(context, l10n.cancelarSaldoExito);
          return true;
        case CancelarSaldoDescuentoProgramadoMotivoRequerido():
          errorGeneral = l10n.cancelarSaldoErrorMotivoRequerido;
          return null;
        case CancelarSaldoDescuentoProgramadoNoActivo():
        case CancelarSaldoDescuentoProgramadoNoExiste():
          RisegFeedback.showError(context, l10n.cancelarSaldoErrorNoActivo);
          return false;
        case CancelarSaldoDescuentoProgramadoErrorInesperado():
          RisegFeedback.showError(context, l10n.cancelarSaldoErrorInesperado);
          return false;
      }
    },
  );

  motivoCtrl.dispose();
  return resultado ?? false;
}
