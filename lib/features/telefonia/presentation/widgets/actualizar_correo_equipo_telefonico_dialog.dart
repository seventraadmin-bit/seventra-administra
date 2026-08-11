import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/actualizar_correo_equipo_telefonico_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Editar correo" (Etapa 9D) — correo/observaciones de
/// configuración de un equipo. Nunca toca la contraseña, ver
/// `mostrarDialogoCambiarContrasenaEquipoTelefonico`.
Future<bool> mostrarDialogoActualizarCorreoEquipoTelefonico(
  BuildContext context,
  WidgetRef ref, {
  required String unidadId,
  String? correoActual,
  String? observacionesActuales,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final actualizar = ref.read(actualizarCorreoEquipoTelefonicoAutorizadoProvider);

  final correoCtrl = TextEditingController(text: correoActual ?? '');
  final observacionesCtrl = TextEditingController(text: observacionesActuales ?? '');

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.equipoTelefonicoCorreoDialogoTitulo,
    confirmLabel: l10n.equipoTelefonicoCorreoBotonConfirmar,
    cancelLabel: l10n.equipoTelefonicoConfigurarBotonCancelar,
    // Sin validación local: correo/observaciones son ambos opcionales
    // (mismo criterio que `ActualizarCorreoEquipoTelefonicoUseCase`,
    // que solo puede fallar por "la unidad no existe"/error inesperado
    // — ninguno de los dos es un error de captura corregible en el
    // formulario).
    contentBuilder: (dialogContext) => SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegTextField(label: l10n.equipoTelefonicoCorreoCampoCorreo, controller: correoCtrl),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.equipoTelefonicoCorreoCampoObservaciones, controller: observacionesCtrl),
        ],
      ),
    ),
    onConfirm: () async {
      final resultado = await actualizar(
        unidadId: unidadId,
        correo: correoCtrl.text.trim().isEmpty ? null : correoCtrl.text.trim(),
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case ActualizarCorreoEquipoTelefonicoExitoso():
          RisegFeedback.showSuccess(context, l10n.equipoTelefonicoCorreoExito);
          return true;
        case ActualizarCorreoEquipoTelefonicoUnidadNoExiste():
        case ActualizarCorreoEquipoTelefonicoErrorInesperado():
          RisegFeedback.showError(context, l10n.equipoTelefonicoConfigurarErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    correoCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
