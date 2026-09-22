import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';

import '../tiempos_extra_controller.dart';

/// Eliminación física extraordinaria de un TiempoExtra (Etapa
/// "corrección real de Tiempo Extra") — facultad exclusiva del Usuario
/// Maestro; el botón que invoca esta función solo debe mostrarse
/// cuando `sesion.esMaestro == true` Y `estatus == cancelado`, pero la
/// protección real vive en `eliminarTiempoExtraFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. Mismo estilo de diálogo con
/// motivo estructurado que `mostrarDialogoEliminarCompraFisicamente`.
Future<bool> mostrarDialogoEliminarTiempoExtraFisicamente(BuildContext context, WidgetRef ref, String tiempoExtraId) async {
  final l10n = AppLocalizations.of(context)!;

  MotivoEliminacionFisicaTiempoExtra? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.tiempoExtraDetalleSeccionCostosAdicionales}',
    confirmLabel: l10n.eliminacionFisicaBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoEliminacionFisicaTiempoExtra.otro;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.eliminacionFisicaAdvertenciaGenerica, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<MotivoEliminacionFisicaTiempoExtra>(
                label: l10n.eliminacionFisicaCampoMotivo,
                value: motivoSeleccionado,
                items: [
                  for (final motivo in MotivoEliminacionFisicaTiempoExtra.values)
                    RisegSelectItem(value: motivo, label: motivo.etiqueta),
                ],
                onChanged: (value) => setState(() => motivoSeleccionado = value),
              ),
              if (esOtro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  label: l10n.tiempoExtraEliminarFisicamenteCampoDetalle,
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
        errorGeneral = l10n.tiempoExtraEliminarFisicamenteErrorMotivoRequerido;
        return null;
      }

      // Por el controlador, nunca por el provider autorizado directo:
      // `TiemposExtraController.eliminarFisicamente` es quien recarga el
      // listado (renglones, filtros y KPIs) e invalida a Finanzas, que
      // ve desaparecer el Egreso de la cobertura. Llamar al provider
      // autorizado aqui persistia el borrado y no refrescaba nada.
      final resultado = await ref.read(tiemposExtraControllerProvider.notifier).eliminarFisicamente(
        tiempoExtraId: tiempoExtraId,
        motivo: motivo,
        detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (resultado) {
        case EliminarTiempoExtraFisicamenteExitoso():
          RisegFeedback.showSuccess(context, l10n.eliminacionFisicaExito);
          return true;
        case EliminarTiempoExtraFisicamenteDetalleRequerido():
          errorGeneral = l10n.tiempoExtraEliminarFisicamenteErrorDetalleRequerido;
          return null;
        case EliminarTiempoExtraFisicamenteNoExiste():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
          return false;
        case EliminarTiempoExtraFisicamenteTieneDependencias(:final detalle):
          RisegFeedback.showError(context, detalle);
          return false;
        case EliminarTiempoExtraFisicamenteErrorInesperado():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => detalleCtrl.dispose());
  return resultado ?? false;
}
