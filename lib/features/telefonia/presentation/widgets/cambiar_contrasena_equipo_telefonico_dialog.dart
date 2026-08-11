import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_contrasena_equipo_telefonico_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Cambiar contraseña" (Etapa 9D) — sin historial de
/// contraseñas anteriores, sobreescribe la vigente (ver el doc comment
/// de `CambiarContrasenaEquipoTelefonicoUseCase`).
Future<bool> mostrarDialogoCambiarContrasenaEquipoTelefonico(
  BuildContext context,
  WidgetRef ref, {
  required String unidadId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cambiar = ref.read(cambiarContrasenaEquipoTelefonicoAutorizadoProvider);

  final contrasenaCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.equipoTelefonicoContrasenaDialogoTitulo,
    confirmLabel: l10n.equipoTelefonicoContrasenaBotonConfirmar,
    cancelLabel: l10n.equipoTelefonicoConfigurarBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(
                label: l10n.equipoTelefonicoContrasenaCampoNueva,
                controller: contrasenaCtrl,
                obscureText: true,
              ),
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
      if (contrasenaCtrl.text.isEmpty) {
        errorGeneral = l10n.equipoTelefonicoContrasenaErrorRequerida;
        return null;
      }
      final resultado = await cambiar(unidadId: unidadId, contrasena: contrasenaCtrl.text);
      if (!context.mounted) return false;
      switch (resultado) {
        case CambiarContrasenaEquipoTelefonicoExitoso():
          RisegFeedback.showSuccess(context, l10n.equipoTelefonicoContrasenaExito);
          return true;
        case CambiarContrasenaEquipoTelefonicoContrasenaRequerida():
          errorGeneral = l10n.equipoTelefonicoContrasenaErrorRequerida;
          return null;
        case CambiarContrasenaEquipoTelefonicoUnidadNoExiste():
        case CambiarContrasenaEquipoTelefonicoErrorInesperado():
          RisegFeedback.showError(context, l10n.equipoTelefonicoConfigurarErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    contrasenaCtrl.dispose();
  });
  return resultado ?? false;
}
