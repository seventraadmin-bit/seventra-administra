import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import '../sesion_controller.dart';

/// "Cambiar mi contraseña" — autoservicio del titular de la sesión
/// (Etapa "Usuarios, permisos y UX de seguridad").
///
/// Distinto del diálogo de Configuración → Usuarios, que resetea la
/// contraseña de OTRA persona y exige `usuarios.resetearPassword`. Este
/// no exige ningún permiso: la autorización es la sesión misma, y solo
/// puede afectar a la cuenta autenticada.
///
/// Toda validación recuperable devuelve `null` para que el diálogo
/// permanezca abierto con el error inline — mismo criterio que el resto
/// de los formularios de la etapa.
Future<bool> mostrarDialogoCambiarMiContrasena(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final passwordCtrl = TextEditingController();
  final confirmarCtrl = TextEditingController();
  String? errorPassword;
  String? errorConfirmar;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.shellCambiarMiContrasena,
    confirmLabel: l10n.usuarioCambiarContrasenaBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => StatefulBuilder(
      builder: (context, setState) => SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              key: const Key('mi_contrasena_nueva'),
              label: l10n.usuarioCampoContrasena,
              controller: passwordCtrl,
              obscureText: true,
              autofocus: true,
              errorText: errorPassword,
              onChanged: (_) => setState(() => errorPassword = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('mi_contrasena_confirmar'),
              label: l10n.usuarioCampoConfirmarContrasena,
              controller: confirmarCtrl,
              obscureText: true,
              errorText: errorConfirmar,
              onChanged: (_) => setState(() => errorConfirmar = null),
            ),
          ],
        ),
      ),
    ),
    onConfirm: () async {
      errorPassword = null;
      errorConfirmar = null;

      if (passwordCtrl.text != confirmarCtrl.text) {
        errorConfirmar = l10n.usuarioErrorContrasenasNoCoinciden;
        return null;
      }

      final r = await ref.read(cambiarMiContrasenaProvider)(passwordCtrl.text);
      if (!context.mounted) return false;

      switch (r) {
        case CambiarContrasenaUsuarioExitoso():
          return true;
        case CambiarContrasenaUsuarioInvalida():
          errorPassword = l10n.usuarioErrorContrasenaInvalida;
          return null;
        case CambiarContrasenaUsuarioNoExiste():
        case CambiarContrasenaUsuarioErrorInesperado():
          RisegFeedback.showError(context, l10n.usuarioErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    passwordCtrl.dispose();
    confirmarCtrl.dispose();
  });

  final exito = resultado ?? false;
  if (exito && context.mounted) {
    RisegFeedback.showSuccess(context, l10n.usuarioCambiarContrasenaExito);
  }
  return exito;
}
