import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../vehiculos_controller.dart';

/// Baja terminal de un Vehículo (Etapa 8A) — devuelve `true` si tuvo
/// éxito, mismo patrón que cualquier otro diálogo de acción del
/// proyecto.
Future<bool> mostrarDialogoDarDeBajaVehiculo(BuildContext context, WidgetRef ref, VehiculoData vehiculo) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(vehiculosControllerProvider.notifier);

  MotivoBajaVehiculo motivo = MotivoBajaVehiculo.venta;
  DateTime fecha = DateTime.now();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoBajaDialogoTitulo,
    confirmLabel: l10n.vehiculoBajaBotonConfirmar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<MotivoBajaVehiculo>(
                label: l10n.vehiculoBajaCampoMotivo,
                value: motivo,
                items: [
                  for (final m in MotivoBajaVehiculo.values)
                    RisegSelectItem(value: m, label: motivoBajaVehiculoLabel(l10n, m)),
                ],
                onChanged: (valor) => setState(() => motivo = valor ?? motivo),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoBajaCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoBajaCampoObservaciones, controller: observacionesCtrl),
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
      final resultado = await notifier.darDeBaja(
        vehiculoId: vehiculo.id,
        fechaBaja: fecha,
        motivoBaja: motivo,
        observacionesBaja: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      switch (resultado) {
        case DarDeBajaVehiculoExitoso():
          if (context.mounted) RisegFeedback.showSuccess(context, l10n.vehiculoBajaExito);
          return true;
        case DarDeBajaVehiculoObservacionesRequeridas():
          errorGeneral = l10n.vehiculoBajaErrorObservacionesRequeridas;
          return null;
        case DarDeBajaVehiculoNoExiste():
        case DarDeBajaVehiculoYaDeBaja():
        case DarDeBajaVehiculoErrorInesperado():
          if (context.mounted) RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
          return false;
      }
    },
  );

  observacionesCtrl.dispose();
  return resultado ?? false;
}
