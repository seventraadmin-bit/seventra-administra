import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_complemento_pago_usecase.dart';

import '../complementos_controller.dart';

/// Diálogo para corregir metadatos administrativos de un Complemento
/// de pago (Etapa 4J.3) — nunca `uuid` ni `montoTotal` (Resolución de
/// Marlon: cancelar y registrar uno nuevo).
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirComplemento(
  BuildContext context,
  WidgetRef ref,
  ComplementoPagoData complemento,
) async {
  final l10n = AppLocalizations.of(context)!;
  DateTime fechaSeleccionada = complemento.fechaTimbrado;
  final serieFiscalController = TextEditingController(text: complemento.serieFiscal ?? '');
  final folioFiscalController = TextEditingController(text: complemento.folioFiscal ?? '');
  final observacionesController = TextEditingController(text: complemento.observaciones ?? '');
  final motivoController = TextEditingController();

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirComplementoDialogoTitulo,
    confirmLabel: l10n.corregirComplementoBotonConfirmar,
    cancelLabel: l10n.corregirComplementoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.corregirComplementoCampoFechaTimbrado,
              value: fechaSeleccionada,
              onChanged: (valor) => setState(() => fechaSeleccionada = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirComplementoCampoSerieFiscal, controller: serieFiscalController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirComplementoCampoFolioFiscal, controller: folioFiscalController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirComplementoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirComplementoCampoMotivo, controller: motivoController),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(complementosControllerProvider.notifier).corregir(
            complementoPagoId: complemento.id,
            serieFiscal: serieFiscalController.text.trim().isEmpty ? null : serieFiscalController.text.trim(),
            folioFiscal: folioFiscalController.text.trim().isEmpty ? null : folioFiscalController.text.trim(),
            fechaTimbrado: fechaSeleccionada,
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            motivo: motivoController.text.trim(),
          );

      if (!context.mounted) return false;

      if (resultado is CorregirComplementoPagoExitoso) {
        RisegFeedback.showSuccess(context, l10n.corregirComplementoExito);
        return true;
      }
      if (resultado is CorregirComplementoPagoCancelado) {
        RisegFeedback.showError(context, l10n.corregirComplementoErrorCancelado);
        return false;
      }
      RisegFeedback.showError(context, l10n.corregirComplementoErrorInesperado);
      return false;
    },
  );

  serieFiscalController.dispose();
  folioFiscalController.dispose();
  observacionesController.dispose();
  motivoController.dispose();
  return resultado ?? false;
}
