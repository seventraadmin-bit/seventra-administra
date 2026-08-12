import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/boveda/domain/usecases/cambiar_secreto_credencial_boveda_usecase.dart';

import '../../boveda_providers.dart';

/// Diálogo "Cambiar secreto" (Etapa 14D) — flujo dedicado y separado
/// de la edición del resto de los campos, mismo criterio que
/// `mostrarDialogoCambiarContrasenaEquipoTelefonico` (Etapa 9D). Sin
/// historial de secretos anteriores: sobreescribe el vigente (o lo
/// limpia si el campo queda vacío — a diferencia de Telefonía, aquí el
/// secreto es opcional en toda la credencial).
Future<bool> mostrarDialogoCambiarSecretoCredencialBoveda(BuildContext context, WidgetRef ref, {required String credencialId}) async {
  final l10n = AppLocalizations.of(context)!;
  final cambiar = ref.read(cambiarSecretoCredencialBovedaAutorizadoProvider);

  final secretoCtrl = TextEditingController();

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.bovedaCambiarSecretoDialogoTitulo,
    confirmLabel: l10n.bovedaCambiarSecretoBotonConfirmar,
    cancelLabel: l10n.bovedaGestionarBotonCancelar,
    contentBuilder: (dialogContext) => SizedBox(
      width: 380,
      child: RisegTextField(label: l10n.bovedaCambiarSecretoCampoNuevo, controller: secretoCtrl, obscureText: true),
    ),
    onConfirm: () async {
      final resultado = await cambiar(id: credencialId, secreto: secretoCtrl.text.isEmpty ? null : secretoCtrl.text);
      if (!context.mounted) return false;
      switch (resultado) {
        case CambiarSecretoCredencialBovedaExitoso():
          RisegFeedback.showSuccess(context, l10n.bovedaCambiarSecretoExito);
          return true;
        case CambiarSecretoCredencialBovedaNoExiste():
        case CambiarSecretoCredencialBovedaErrorInesperado():
          RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    secretoCtrl.dispose();
  });
  return resultado ?? false;
}
