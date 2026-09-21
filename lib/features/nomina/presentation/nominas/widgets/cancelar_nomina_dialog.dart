import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_nomina_usecase.dart';

import '../nominas_controller.dart';

/// Diálogo "Cancelar Nómina" (Etapa 4) — salida controlada y auditada,
/// nunca destructiva: solo Borrador o Cerrada-sin-ningún-`PagoNomina`
/// real (`CancelarNominaUseCase` ya lo valida; el botón que abre este
/// diálogo también debe ocultarse fuera de esos dos casos, ver
/// `nomina_detalle_screen.dart`). Mismo criterio de motivo estructurado
/// que `mostrarDialogoCancelarCompra`. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCancelarNomina(BuildContext context, WidgetRef ref, String nominaId) async {
  final l10n = AppLocalizations.of(context)!;

  MotivoCancelacionNomina? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.nominaCancelarDialogoTitulo,
    confirmLabel: l10n.nominaCancelarBotonConfirmar,
    cancelLabel: l10n.generarNominaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoCancelacionNomina.otro;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.nominaCancelarMensaje, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<MotivoCancelacionNomina>(
                label: l10n.nominaCancelarCampoMotivo,
                value: motivoSeleccionado,
                items: [
                  for (final motivo in MotivoCancelacionNomina.values)
                    RisegSelectItem(value: motivo, label: motivo.etiqueta),
                ],
                onChanged: (value) => setState(() => motivoSeleccionado = value),
              ),
              if (esOtro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.nominaCancelarCampoDetalle, controller: detalleCtrl, autofocus: true),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.nominaCancelarCampoObservaciones, controller: observacionesCtrl),
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
      final motivo = motivoSeleccionado;
      if (motivo == null) {
        errorGeneral = l10n.nominaCancelarErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(nominasControllerProvider.notifier).cancelarNomina(
            nominaId: nominaId,
            motivo: motivo,
            detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
          );
      if (!context.mounted) return false;

      switch (resultado) {
        case CancelarNominaExitoso():
          RisegFeedback.showSuccess(context, l10n.nominaCancelarExito);
          return true;
        case CancelarNominaDetalleRequerido():
          errorGeneral = l10n.nominaCancelarErrorDetalleRequerido;
          return null;
        case CancelarNominaYaCancelada():
          errorGeneral = l10n.nominaCancelarYaCancelada;
          return null;
        case CancelarNominaTienePagos():
          errorGeneral = l10n.nominaCancelarTienePagos;
          return null;
        case CancelarNominaNoExiste():
          RisegFeedback.showError(context, l10n.nominaCancelarNoExiste);
          return false;
        case CancelarNominaErrorInesperado():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    detalleCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
