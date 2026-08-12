import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../design_system.dart';

/// Traduce cualquier tipo sellado `EliminarXxxFisicamenteResultado` a
/// esta forma común. `tieneDependencias` existe para que el caparazón
/// **no** muestre un segundo aviso genérico encima del `detalle`
/// específico que cada `mostrarDialogoEliminarXxxFisicamente` ya
/// mostró antes de mapear el resultado (bug real, Etapa 15: antes se
/// mapeaba a `errorInesperado` y el usuario veía dos avisos, uno
/// específico y otro genérico, encimados).
enum ResultadoEliminacionFisica { exitoso, motivoRequerido, noExiste, tieneDependencias, errorInesperado }

/// Caparazón visual compartido de "Eliminar físicamente" (Etapa 11D) —
/// **puramente presentacional**: solo captura el motivo obligatorio y
/// llama a [eliminar]; cada dominio conserva su propio UseCase,
/// Resultado sellado y fachada dedicada (`exigirMaestro`) — este
/// widget no decide nada de negocio, así que compartirlo no viola el
/// principio de "sin infraestructura genérica de eliminación" (esa
/// prohibición es sobre el dominio, no sobre el formulario en sí).
Future<bool> mostrarDialogoEliminarFisicamente(
  BuildContext context, {
  required String titulo,
  required String advertencia,
  required Future<ResultadoEliminacionFisica> Function(String motivo) eliminar,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final confirmado = await RisegDialog.showForm<bool>(
    context: context,
    title: titulo,
    confirmLabel: l10n.eliminacionFisicaBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(advertencia, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.eliminacionFisicaCampoMotivo, controller: motivoCtrl, autofocus: true),
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
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.eliminacionFisicaErrorMotivoRequerido;
        return null;
      }
      final resultado = await eliminar(motivo);
      if (!context.mounted) return false;
      switch (resultado) {
        case ResultadoEliminacionFisica.exitoso:
          RisegFeedback.showSuccess(context, l10n.eliminacionFisicaExito);
          return true;
        case ResultadoEliminacionFisica.motivoRequerido:
          errorGeneral = l10n.eliminacionFisicaErrorMotivoRequerido;
          return null;
        case ResultadoEliminacionFisica.noExiste:
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
          return false;
        case ResultadoEliminacionFisica.tieneDependencias:
          // El `detalle` específico ya se mostró en el llamador, antes
          // de mapear a este caso — no se muestra nada más aquí.
          return false;
        case ResultadoEliminacionFisica.errorInesperado:
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  return confirmado ?? false;
}
