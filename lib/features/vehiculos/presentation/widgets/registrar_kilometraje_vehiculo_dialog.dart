import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_kilometraje_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../vehiculos_controller.dart';

/// Diálogo "Registrar kilometraje" (Etapa 8B) — el punto de entrada
/// manual del ledger (`lecturaManual`/`correccion`, principalmente).
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRegistrarKilometrajeVehiculo(BuildContext context, WidgetRef ref, String vehiculoId) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(vehiculosControllerProvider.notifier);

  DateTime fecha = DateTime.now();
  final kilometrajeCtrl = TextEditingController();
  String origen = OrigenKilometrajeVehiculo.lecturaManual.name;
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoRegistrarKilometrajeDialogoTitulo,
    confirmLabel: l10n.vehiculoRegistrarKilometrajeBotonConfirmar,
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
                label: l10n.vehiculoRegistrarKilometrajeCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoRegistrarKilometrajeCampoKilometraje,
                controller: kilometrajeCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String>(
                label: l10n.vehiculoRegistrarKilometrajeCampoOrigen,
                value: origen,
                items: [
                  for (final o in OrigenKilometrajeVehiculo.values)
                    RisegSelectItem(value: o.name, label: origenKilometrajeLabel(l10n, o.name)),
                ],
                onChanged: (valor) => setState(() => origen = valor ?? origen),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoRegistrarKilometrajeCampoObservaciones, controller: observacionesCtrl),
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
      final kilometraje = int.tryParse(kilometrajeCtrl.text.trim());
      if (kilometraje == null) {
        errorGeneral = l10n.vehiculoRegistrarKilometrajeErrorInvalido;
        return null;
      }

      final resultado = await notifier.registrarKilometraje(
        vehiculoId: vehiculoId,
        fecha: fecha,
        kilometraje: kilometraje,
        origen: origen,
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarKilometrajeVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoRegistrarKilometrajeExito);
          return true;
        case RegistrarKilometrajeVehiculoInvalido():
          errorGeneral = l10n.vehiculoRegistrarKilometrajeErrorInvalido;
          return null;
        case RegistrarKilometrajeVehiculoMenorAlActual(:final actual):
          errorGeneral = l10n.vehiculoRegistrarKilometrajeErrorMenor(actual);
          return null;
        case RegistrarKilometrajeVehiculoObservacionesRequeridas():
          errorGeneral = l10n.vehiculoRegistrarKilometrajeErrorObservacionesRequeridas;
          return null;
        case RegistrarKilometrajeVehiculoNoExiste():
        case RegistrarKilometrajeVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    kilometrajeCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
