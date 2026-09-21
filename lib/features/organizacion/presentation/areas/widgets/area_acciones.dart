import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../domain/usecases/desactivar_area_usecase.dart';
import '../../../organizacion_providers.dart';
import '../areas_list_controller.dart';

/// Activar/desactivar un Área (Etapa 16, tercera pasada visual) —
/// reutilizado tanto por el listado como por el expediente de Área.
/// Desactivar primero llama al caso de uso: si bloquea por Puestos
/// activos, muestra el error directo sin ningún diálogo de
/// confirmación; si no bloquea, entonces sí pide confirmación antes de
/// aplicar el cambio.
Future<void> activarArea(BuildContext context, WidgetRef ref, AreaData area) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmado = await RisegDialog.showConfirmation(
    context: context,
    title: l10n.areaConfirmarActivarTitulo,
    message: l10n.areaConfirmarActivarMensaje,
    confirmLabel: l10n.sucursalConfirmarAceptar,
    cancelLabel: l10n.sucursalConfirmarCancelar,
  );
  if (confirmado != true) return;

  final actualizada = await ref.read(activarAreaAutorizadoProvider)(area.id);
  if (!context.mounted) return;
  if (actualizada == null) {
    RisegFeedback.showError(context, l10n.accesoDenegadoAccionMensaje);
    return;
  }
  ref.read(areasListControllerProvider.notifier).recargar();
  RisegFeedback.showSuccess(context, l10n.areaCicloVidaCambiadoExito);
}

Future<void> desactivarArea(BuildContext context, WidgetRef ref, AreaData area) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmado = await RisegDialog.showConfirmation(
    context: context,
    title: l10n.areaConfirmarDesactivarTitulo,
    message: l10n.areaConfirmarDesactivarMensaje,
    confirmLabel: l10n.sucursalConfirmarAceptar,
    cancelLabel: l10n.sucursalConfirmarCancelar,
    destructive: true,
  );
  if (confirmado != true) return;

  final resultado = await ref.read(desactivarAreaAutorizadoProvider)(area.id);

  if (!context.mounted) return;

  if (resultado is DesactivarAreaBloqueadaPorPuestosActivos) {
    RisegFeedback.showError(context, l10n.areaDesactivarBloqueadaError(resultado.cantidad));
    return;
  }
  if (resultado is DesactivarAreaErrorInesperado) {
    RisegFeedback.showError(context, l10n.accesoDenegadoAccionMensaje);
    return;
  }

  ref.read(areasListControllerProvider.notifier).recargar();
  RisegFeedback.showSuccess(context, l10n.areaCicloVidaCambiadoExito);
}
