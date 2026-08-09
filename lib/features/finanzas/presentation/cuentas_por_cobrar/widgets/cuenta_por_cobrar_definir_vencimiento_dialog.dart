import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/actualizar_fecha_vencimiento_cuenta_por_cobrar_usecase.dart';

import '../cuentas_por_cobrar_controller.dart';

/// Diálogo para definir o corregir la fecha de vencimiento de una
/// Cuenta por cobrar (Etapa 4J.1, Resolución E de Marlon) — la única
/// vía administrativa para completar el caso Mirabilia (documento sin
/// regla de Pago calculable) o corregir una fecha ya definida.
///
/// Devuelve `true` si la actualización tuvo éxito.
Future<bool> mostrarDialogoDefinirVencimientoCuentaPorCobrar(
  BuildContext context,
  WidgetRef ref,
  String cuentaPorCobrarId, {
  DateTime? fechaActual,
}) async {
  final l10n = AppLocalizations.of(context)!;
  DateTime? fechaSeleccionada = fechaActual;
  final motivoController = TextEditingController();
  String? errorFecha;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cuentaPorCobrarDefinirVencimientoDialogoTitulo,
    confirmLabel: l10n.cuentaPorCobrarDefinirVencimientoBotonConfirmar,
    cancelLabel: l10n.cuentaPorCobrarDefinirVencimientoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.cuentaPorCobrarDefinirVencimientoCampoFecha,
              value: fechaSeleccionada,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fechaSeleccionada = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.cuentaPorCobrarDefinirVencimientoCampoMotivo,
              controller: motivoController,
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      if (fechaSeleccionada == null) return false;

      final resultado = await ref.read(cuentasPorCobrarControllerProvider.notifier).actualizarFechaVencimiento(
            cuentaPorCobrarId: cuentaPorCobrarId,
            fechaVencimiento: fechaSeleccionada!,
            motivo: motivoController.text.trim().isEmpty ? null : motivoController.text.trim(),
          );

      if (!context.mounted) return false;

      if (resultado is ActualizarFechaVencimientoCuentaPorCobrarExitoso) {
        RisegFeedback.showSuccess(context, l10n.cuentaPorCobrarDefinirVencimientoExito);
        return true;
      }
      if (resultado is ActualizarFechaVencimientoCuentaPorCobrarNoExiste) {
        RisegFeedback.showError(context, l10n.cuentaPorCobrarDefinirVencimientoErrorNoExiste);
        return false;
      }
      RisegFeedback.showError(context, l10n.cuentaPorCobrarDefinirVencimientoErrorInesperado);
      return false;
    },
  );

  motivoController.dispose();
  return resultado ?? false;
}
