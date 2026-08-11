import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import '../usuarios_controller.dart';

/// Cambio de contraseña (Etapa 11A) — acción administrativa propia,
/// separada del alta/edición de datos (mismo criterio que en cada
/// dominio del proyecto). Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCambiarContrasenaUsuario(BuildContext context, WidgetRef ref, UsuarioData usuario) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(usuariosControllerProvider.notifier);
  final passwordCtrl = TextEditingController();
  final confirmarCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.usuarioCambiarContrasenaTitulo(usuario.nombre),
    confirmLabel: l10n.usuarioCambiarContrasenaBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(
                label: l10n.usuarioCampoContrasena,
                controller: passwordCtrl,
                obscureText: true,
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.usuarioCampoConfirmarContrasena,
                controller: confirmarCtrl,
                obscureText: true,
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: context.colors.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      if (passwordCtrl.text != confirmarCtrl.text) {
        errorGeneral = l10n.usuarioErrorContrasenasNoCoinciden;
        return false;
      }
      final resultado = await notifier.cambiarContrasena(usuarioId: usuario.id, password: passwordCtrl.text);
      switch (resultado) {
        case CambiarContrasenaUsuarioExitoso():
          return true;
        case CambiarContrasenaUsuarioNoExiste():
          errorGeneral = l10n.usuarioErrorInesperado;
        case CambiarContrasenaUsuarioInvalida():
          errorGeneral = l10n.usuarioErrorContrasenaInvalida;
        case CambiarContrasenaUsuarioErrorInesperado():
          errorGeneral = l10n.usuarioErrorInesperado;
      }
      return false;
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    passwordCtrl.dispose();
    confirmarCtrl.dispose();
  });

  final exito = resultado ?? false;
  if (exito && context.mounted) {
    RisegFeedback.showSuccess(context, l10n.usuarioCambiarContrasenaExito);
  } else if (!exito && errorGeneral != null && context.mounted) {
    RisegFeedback.showError(context, errorGeneral!);
  }
  return exito;
}
