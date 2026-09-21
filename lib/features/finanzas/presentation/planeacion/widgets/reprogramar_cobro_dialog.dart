import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';

import '../planeacion_financiera_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Diálogo "Reprogramar fecha esperada" (Etapa 19D, pedido §9) — sobre
/// un cobro vencido. Nunca sobrescribe la fecha contractual original
/// (`fechaVencimiento`): captura `fechaCobroReprogramada` por separado,
/// ver el doc comment de `ReprogramarCobroCuentaPorCobrarUseCase`.
///
/// Devuelve `true` si la operación tuvo éxito.
Future<bool> mostrarDialogoReprogramarCobro(
  BuildContext context,
  WidgetRef ref, {
  required PendienteVencido pendiente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  DateTime? nuevaFecha;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.reprogramarCobroDialogoTitulo,
    confirmLabel: l10n.reprogramarCobroBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.reprogramarCobroFechaOriginal(pendiente.concepto, _formatoFecha.format(pendiente.fechaVencimiento)),
                style: AppTypography.body,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.reprogramarCobroCampoNuevaFecha,
                value: nuevaFecha,
                onChanged: (valor) => setState(() => nuevaFecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.reprogramarCobroCampoMotivo, controller: motivoCtrl),
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
      if (nuevaFecha == null) {
        errorGeneral = l10n.reprogramarCobroErrorFechaRequerida;
        return null;
      }
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.cuentaPorCobrarReprogramarErrorMotivoRequerido;
        return null;
      }
      final resultado = await ref.read(planeacionFinancieraControllerProvider.notifier).reprogramarCobro(
            cuentaPorCobrarId: pendiente.origenId,
            fechaCobroReprogramada: nuevaFecha,
            motivo: motivo,
          );
      if (!context.mounted) return false;
      switch (resultado) {
        case ReprogramarCobroCuentaPorCobrarExitoso():
          RisegFeedback.showSuccess(context, l10n.reprogramarCobroExito);
          return true;
        case ReprogramarCobroCuentaPorCobrarMotivoRequerido():
          errorGeneral = l10n.cuentaPorCobrarReprogramarErrorMotivoRequerido;
          return null;
        case ReprogramarCobroCuentaPorCobrarNoExiste():
        case ReprogramarCobroCuentaPorCobrarCancelada():
          RisegFeedback.showError(context, l10n.reprogramarCobroErrorInesperado);
          return false;
        case ReprogramarCobroCuentaPorCobrarErrorInesperado():
          RisegFeedback.showError(context, l10n.reprogramarCobroErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  return resultado ?? false;
}
