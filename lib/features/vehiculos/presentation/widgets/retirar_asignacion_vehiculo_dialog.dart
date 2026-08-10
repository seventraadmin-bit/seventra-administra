import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/retirar_asignacion_vehiculo_usecase.dart';

import '../vehiculos_controller.dart';

/// Diálogo "Retirar asignación" (Etapa 8B) — libera el Vehículo.
/// Kilometraje de devolución opcional. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRetirarAsignacionVehiculo(
  BuildContext context,
  WidgetRef ref,
  AsignacionVehiculoData asignacion,
) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(vehiculosControllerProvider.notifier);

  DateTime fechaTermino = DateTime.now();
  final observacionesCtrl = TextEditingController();
  final kilometrajeCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoRetirarAsignacionDialogoTitulo,
    confirmLabel: l10n.vehiculoRetirarAsignacionBotonConfirmar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.vehiculoRetirarAsignacionCampoFecha,
                value: fechaTermino,
                onChanged: (valor) => setState(() => fechaTermino = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoRetirarAsignacionCampoKilometrajeDevolucion,
                controller: kilometrajeCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoRetirarAsignacionCampoObservaciones, controller: observacionesCtrl),
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
      final kilometrajeTexto = kilometrajeCtrl.text.trim();
      final kilometraje = kilometrajeTexto.isEmpty ? null : int.tryParse(kilometrajeTexto);
      if (kilometrajeTexto.isNotEmpty && kilometraje == null) {
        errorGeneral = l10n.vehiculoRegistrarKilometrajeErrorInvalido;
        return null;
      }

      final resultado = await notifier.retirarAsignacion(
        asignacionVehiculoId: asignacion.id,
        fechaTermino: fechaTermino,
        observacionesTermino: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
        kilometrajeDevolucion: kilometraje,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RetirarAsignacionVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoRetirarAsignacionExito);
          return true;
        case RetirarAsignacionVehiculoKilometrajeMenorAlActual(:final actual):
          errorGeneral = l10n.vehiculoAsignarErrorKilometrajeMenor(actual);
          return null;
        case RetirarAsignacionVehiculoNoExiste():
        case RetirarAsignacionVehiculoYaCerrada():
        case RetirarAsignacionVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesCtrl.dispose();
    kilometrajeCtrl.dispose();
  });
  return resultado ?? false;
}
