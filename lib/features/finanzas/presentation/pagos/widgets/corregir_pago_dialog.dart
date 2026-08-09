import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';

import '../pagos_controller.dart';
import '../pagos_list_screen.dart' show formaPagoLabel;

/// Diálogo para corregir metadatos administrativos de un Pago (Etapa
/// 4J.2) — nunca `montoTotal` (un monto incorrecto se cancela y se
/// vuelve a capturar, mismo criterio que el resto del proyecto).
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirPago(BuildContext context, WidgetRef ref, PagoData pago) async {
  final l10n = AppLocalizations.of(context)!;
  DateTime fechaSeleccionada = pago.fechaPago;
  FormaPago formaSeleccionada = FormaPago.values.byName(pago.formaPago);
  final referenciaController = TextEditingController(text: pago.referencia ?? '');
  final bancoOrigenController = TextEditingController(text: pago.bancoOrigen ?? '');
  final cuentaBancariaController = TextEditingController(text: pago.cuentaBancariaDestino ?? '');
  final observacionesController = TextEditingController(text: pago.observaciones ?? '');
  final motivoController = TextEditingController();

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirPagoDialogoTitulo,
    confirmLabel: l10n.corregirPagoBotonConfirmar,
    cancelLabel: l10n.corregirPagoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.corregirPagoCampoFecha,
              value: fechaSeleccionada,
              onChanged: (valor) => setState(() => fechaSeleccionada = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<FormaPago>(
              label: l10n.corregirPagoCampoFormaPago,
              value: formaSeleccionada,
              items: [
                for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name)),
              ],
              onChanged: (valor) => setState(() => formaSeleccionada = valor ?? formaSeleccionada),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirPagoCampoReferencia, controller: referenciaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirPagoCampoBancoOrigen, controller: bancoOrigenController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirPagoCampoCuentaBancariaDestino, controller: cuentaBancariaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirPagoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.corregirPagoCampoMotivo, controller: motivoController),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(pagosControllerProvider.notifier).corregir(
            pagoId: pago.id,
            fechaPago: fechaSeleccionada,
            formaPago: formaSeleccionada.name,
            referencia: referenciaController.text.trim().isEmpty ? null : referenciaController.text.trim(),
            bancoOrigen: bancoOrigenController.text.trim().isEmpty ? null : bancoOrigenController.text.trim(),
            cuentaBancariaDestino:
                cuentaBancariaController.text.trim().isEmpty ? null : cuentaBancariaController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            motivo: motivoController.text.trim(),
          );

      if (!context.mounted) return false;

      if (resultado is CorregirPagoExitoso) {
        RisegFeedback.showSuccess(context, l10n.corregirPagoExito);
        return true;
      }
      if (resultado is CorregirPagoCancelado) {
        RisegFeedback.showError(context, l10n.corregirPagoErrorCancelado);
        return false;
      }
      RisegFeedback.showError(context, l10n.corregirPagoErrorInesperado);
      return false;
    },
  );

  referenciaController.dispose();
  bancoOrigenController.dispose();
  cuentaBancariaController.dispose();
  observacionesController.dispose();
  motivoController.dispose();
  return resultado ?? false;
}
