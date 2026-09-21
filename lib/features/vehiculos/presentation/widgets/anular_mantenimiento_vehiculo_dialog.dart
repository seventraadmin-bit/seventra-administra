import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cancelar_mantenimiento_vehiculo_usecase.dart';

import '../../vehiculos_providers.dart';

/// Diálogo "Anular mantenimiento" (schemaVersion 80).
///
/// Anular **no borra**: la fila se conserva con su `egresoId`/`deudaId`
/// como evidencia de qué se revirtió, y el historial del vehículo recibe
/// un evento `mantenimientoCancelado`. Lo que se revierte es el efecto
/// financiero, exactamente una vez — el Egreso pasa a cancelado, o el
/// cargo a la tarjeta se libera con un ajuste negativo.
///
/// Por eso la advertencia se muestra siempre: quien anula debe saber que
/// el dinero regresa a su origen, no que el registro desaparece.
///
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoAnularMantenimientoVehiculo(
  BuildContext context,
  WidgetRef ref,
  VehiculoMantenimientoData registro,
) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoMantenimientoDialogoAnularTitulo,
    confirmLabel: l10n.vehiculoMantenimientoBotonAnular,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final colors = dialogContext.colors;
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(registro.descripcion, style: AppTypography.body),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.vehiculoMantenimientoAnularAdvertencia,
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('vehiculo_mantenimiento_anular_motivo'),
                label: l10n.vehiculoMantenimientoCampoMotivoAnulacion,
                controller: motivoCtrl,
                autofocus: true,
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errorGeneral!,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final anulado = await ref.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
            vehiculoMantenimientoId: registro.id,
            motivo: motivoCtrl.text,
          );
      if (!context.mounted) return false;

      switch (anulado) {
        case CancelarMantenimientoVehiculoMotivoRequerido():
          errorGeneral = l10n.vehiculoMantenimientoErrorMotivoRequerido;
          return null;
        case CancelarMantenimientoVehiculoYaCancelado():
          errorGeneral = l10n.vehiculoMantenimientoErrorYaCancelado;
          return null;
        case CancelarMantenimientoVehiculoNoExiste():
        case CancelarMantenimientoVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoMantenimientoErrorInesperado);
          return false;
        case CancelarMantenimientoVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoMantenimientoAnuladoExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  return resultado ?? false;
}
