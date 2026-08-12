import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Advertencia previa a restaurar (Etapa 14C) — acción destructiva: se
/// reemplazan todos los datos actuales. [onConfirm] es la propia
/// restauración (`RespaldoController.restaurar`); mientras esté
/// pendiente, `RisegDialog` mantiene el diálogo abierto con el botón
/// primario en `loading` (mismo comportamiento que cualquier otra
/// confirmación con `onConfirm` en el proyecto).
Future<bool?> mostrarConfirmacionRestauracion({
  required BuildContext context,
  required AppLocalizations l10n,
  required Future<void> Function() onConfirm,
}) {
  return RisegDialog.showConfirmation(
    context: context,
    title: l10n.respaldoRestaurarConfirmarTitulo,
    message: l10n.respaldoRestaurarConfirmarMensaje,
    confirmLabel: l10n.respaldoRestaurarConfirmarBoton,
    cancelLabel: l10n.respaldoRestaurarCancelarBoton,
    destructive: true,
    onConfirm: onConfirm,
  );
}
