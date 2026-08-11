import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel;


import '../../domain/usecases/corregir_compra_usecase.dart';
import '../compras_controller.dart';

/// Diálogo "Corregir datos de la compra" (Etapa 10) — solo campos
/// administrativos (proveedor, forma de pago, observaciones); nunca
/// partidas, cantidades ni costos (ver el doc comment de
/// `CompraPartida`). Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCorregirCompra(BuildContext context, WidgetRef ref, String compraId) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(comprasControllerProvider.notifier);
  final compra = await notifier.obtenerCompra(compraId);
  if (!context.mounted || compra == null) return false;

  final proveedorCtrl = TextEditingController(text: compra.proveedor ?? '');
  String formaPago = compra.formaPago;
  final formaPagoOtroCtrl = TextEditingController(text: compra.formaPagoOtroDescripcion ?? '');
  final observacionesCtrl = TextEditingController(text: compra.observaciones ?? '');
  final motivoCtrl = TextEditingController();

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.compraCorregirDialogoTitulo,
    confirmLabel: l10n.compraCorregirBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.compraCampoProveedor, controller: proveedorCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String>(
                label: l10n.compraCampoFormaPago,
                value: formaPago,
                items: [for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name))],
                onChanged: (valor) => setState(() => formaPago = valor ?? formaPago),
              ),
              if (formaPago == FormaPago.otro.name) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.compraCampoFormaPagoOtroDescripcion, controller: formaPagoOtroCtrl),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.compraCampoObservaciones, controller: observacionesCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.compraCorregirCampoMotivo, controller: motivoCtrl),
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final resultado = await notifier.corregirCompra(
        compraId: compraId,
        proveedor: proveedorCtrl.text,
        formaPago: formaPago,
        formaPagoOtroDescripcion: formaPagoOtroCtrl.text,
        observaciones: observacionesCtrl.text,
        motivo: motivoCtrl.text,
      );
      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirCompraExitosa():
          RisegFeedback.showSuccess(context, l10n.compraCorregirExito);
          return true;
        case CorregirCompraNoExiste():
        case CorregirCompraCancelada():
        case CorregirCompraErrorInesperado():
          RisegFeedback.showError(context, l10n.compraErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    proveedorCtrl.dispose();
    formaPagoOtroCtrl.dispose();
    observacionesCtrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
