import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_cuenta_por_cobrar_usecase.dart';

import '../cuentas_por_cobrar_controller.dart';

/// Diálogo para corregir los ÚNICOS dos campos de Categoría C de una
/// Cuenta por cobrar (Etapa 7): `fechaVencimiento` (completa el caso
/// Mirabilia o corrige una fecha ya definida, Resolución E de Marlon)
/// y `observaciones`. Reemplaza a
/// `mostrarDialogoDefinirVencimientoCuentaPorCobrar` — nunca expone
/// `importeEmitido`/`saldoPendiente`/ningún otro campo (Categoría A/B,
/// ver el doc comment de `CorregirCuentaPorCobrarUseCase`). Motivo
/// siempre obligatorio.
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirCuentaPorCobrar(
  BuildContext context,
  WidgetRef ref,
  CuentaPorCobrarData cuenta,
) async {
  final l10n = AppLocalizations.of(context)!;
  DateTime? fechaSeleccionada = cuenta.fechaVencimiento;
  final observacionesController = TextEditingController(text: cuenta.observaciones ?? '');
  final motivoController = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirCuentaPorCobrarDialogoTitulo,
    confirmLabel: l10n.corregirCuentaPorCobrarBotonConfirmar,
    cancelLabel: l10n.corregirCuentaPorCobrarBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.corregirCuentaPorCobrarCampoFecha,
              value: fechaSeleccionada,
              onChanged: (valor) => setState(() => fechaSeleccionada = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.corregirCuentaPorCobrarCampoObservaciones,
              controller: observacionesController,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.corregirCuentaPorCobrarCampoMotivo,
              controller: motivoController,
            ),
            if (errorGeneral != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                errorGeneral!,
                style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
              ),
            ],
          ],
        );
      },
    ),
    onConfirm: () async {
      final motivo = motivoController.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.corregirCuentaPorCobrarErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(cuentasPorCobrarControllerProvider.notifier).corregir(
            cuentaPorCobrarId: cuenta.id,
            fechaVencimiento: fechaSeleccionada,
            limpiarFechaVencimiento: fechaSeleccionada == null,
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
            limpiarObservaciones: observacionesController.text.trim().isEmpty,
            motivo: motivo,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirCuentaPorCobrarExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirCuentaPorCobrarExito);
          return true;
        case CorregirCuentaPorCobrarMotivoRequerido():
          errorGeneral = l10n.corregirCuentaPorCobrarErrorMotivoRequerido;
          return null;
        case CorregirCuentaPorCobrarCancelada():
          RisegFeedback.showError(context, l10n.corregirCuentaPorCobrarErrorCancelada);
          return false;
        case CorregirCuentaPorCobrarNoExiste():
          RisegFeedback.showError(context, l10n.corregirCuentaPorCobrarErrorNoExiste);
          return false;
        case CorregirCuentaPorCobrarErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirCuentaPorCobrarErrorInesperado);
          return false;
      }
    },
  );

  observacionesController.dispose();
  motivoController.dispose();
  return resultado ?? false;
}
