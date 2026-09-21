import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/compras/domain/usecases/eliminar_compra_fisicamente_usecase.dart';

import '../../compras_providers.dart';

/// Eliminación física extraordinaria de una Compra (Etapa 15) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en `eliminarCompraFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. Elimina, en la misma
/// transacción, la Compra, sus renglones, las integraciones de
/// Inventario que generó y su propio Egreso — el único rechazo real es
/// historia posterior verificada (unidad asignada/vinculada, o
/// movimientos adicionales).
///
/// Motivo estructurado (Etapa 15, mismo criterio que
/// `mostrarDialogoCancelarCompra`): esta pantalla implementa su propio
/// diálogo — con un `RisegSelect` fijo + detalle condicional — en vez
/// de reusar el caparazón genérico `mostrarDialogoEliminarFisicamente`
/// (`riseg_eliminar_fisicamente_dialog.dart`), que solo captura texto
/// libre y es compartido por 10+ dominios que no deben verse afectados
/// por este cambio.
Future<bool> mostrarDialogoEliminarCompraFisicamente(BuildContext context, WidgetRef ref, String compraId) async {
  final l10n = AppLocalizations.of(context)!;

  MotivoEliminacionFisicaCompra? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.compraExpedienteSeccionDatos}',
    confirmLabel: l10n.eliminacionFisicaBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoEliminacionFisicaCompra.otro;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.eliminacionFisicaAdvertenciaGenerica, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<MotivoEliminacionFisicaCompra>(
                label: l10n.eliminacionFisicaCampoMotivo,
                value: motivoSeleccionado,
                items: [
                  for (final motivo in MotivoEliminacionFisicaCompra.values)
                    RisegSelectItem(value: motivo, label: motivo.etiqueta),
                ],
                onChanged: (value) => setState(() => motivoSeleccionado = value),
              ),
              if (esOtro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  label: l10n.compraEliminarFisicamenteCampoDetalle,
                  controller: detalleCtrl,
                  autofocus: true,
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
      final motivo = motivoSeleccionado;
      if (motivo == null) {
        errorGeneral = l10n.compraEliminarFisicamenteErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(eliminarCompraFisicamenteAutorizadoProvider)(
        compraId: compraId,
        motivo: motivo,
        detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (resultado) {
        case EliminarCompraFisicamenteExitoso():
          RisegFeedback.showSuccess(context, l10n.eliminacionFisicaExito);
          return true;
        case EliminarCompraFisicamenteDetalleRequerido():
          errorGeneral = l10n.compraEliminarFisicamenteErrorDetalleRequerido;
          return null;
        case EliminarCompraFisicamenteNoExiste():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
          return false;
        case EliminarCompraFisicamenteTieneDependencias(:final detalle):
          RisegFeedback.showError(context, detalle);
          return false;
        case EliminarCompraFisicamenteErrorInesperado():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => detalleCtrl.dispose());
  return resultado ?? false;
}
