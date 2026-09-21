import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_asignacion_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'coherencia_linea_equipo_mensajes.dart';

/// Diálogo "Retirar asignación" (Etapa 9B) — libera una línea.
///
/// §12: si el teléfono asociado sigue en manos de alguien, dejar la
/// línea sin asignación se rechaza — es exactamente el caso real que
/// originó la Rebanada 2. Hay que retirar antes el equipo de la línea,
/// o devolver el aparato en Inventario. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRetirarAsignacionLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  AsignacionLineaTelefonicaData asignacion,
) async {
  final l10n = AppLocalizations.of(context)!;
  final nombres = await NombresDestinoTelefonia.cargar(ref);
  if (!context.mounted) return false;

  DateTime fechaTermino = DateTime.now();
  final observacionesCtrl = TextEditingController();
  final motivoCtrl = TextEditingController();
  bool pideMotivo = false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaRetirarAsignacionDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaRetirarAsignacionBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.lineaTelefonicaRetirarAsignacionCampoFecha,
                value: fechaTermino,
                onChanged: (valor) => setState(() => fechaTermino = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaRetirarAsignacionCampoObservaciones, controller: observacionesCtrl),
              if (pideMotivo) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('linea_retirar_asignacion_campo_motivo'),
                  label: l10n.lineaTelefonicaResolverInconsistenciaCampoMotivo,
                  controller: motivoCtrl,
                ),
              ],
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
      final resultado = await ref.read(retirarAsignacionLineaTelefonicaAutorizadoProvider)(
            asignacionLineaTelefonicaId: asignacion.id,
            fechaTermino: fechaTermino,
            observacionesTermino: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            motivo: motivoCtrl.text,
          );
      switch (resultado) {
        case RetirarAsignacionLineaTelefonicaExitoso():
          if (context.mounted) RisegFeedback.showSuccess(context, l10n.lineaTelefonicaRetirarAsignacionExito);
          return true;
        case RetirarAsignacionLineaTelefonicaYaCerrada():
          errorGeneral = l10n.lineaTelefonicaRetirarAsignacionErrorYaCerrada;
          return null;
        case RetirarAsignacionLineaTelefonicaEquipoCustodiado(:final coherencia):
          errorGeneral = mensajeIncoherenciaLineaEquipo(l10n, coherencia, nombres);
          return null;
        case RetirarAsignacionLineaTelefonicaMotivoRequerido():
          pideMotivo = true;
          errorGeneral = l10n.lineaTelefonicaCoherenciaMotivoRequerido;
          return null;
        case RetirarAsignacionLineaTelefonicaNoExiste():
        case RetirarAsignacionLineaTelefonicaErrorInesperado():
          if (context.mounted) RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesCtrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
