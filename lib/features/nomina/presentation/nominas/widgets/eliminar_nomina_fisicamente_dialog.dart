import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_nomina_fisicamente_usecase.dart';

import '../../../nomina_providers.dart';

/// Eliminación física extraordinaria de una Nómina (Etapa 15) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en
/// `eliminarNominaFisicamenteAutorizadoProvider` (`exigirMaestro`) —
/// nunca en la UI. Solo elimina un Borrador sin `PagoNomina` — una
/// Nómina Cerrada/Pagada, o con cualquier pago real, se bloquea
/// siempre. Al eliminar, cualquier `DescuentoInventario` que esta
/// Nómina haya aplicado vuelve a `pendiente` (nunca desaparece).
///
/// Motivo estructurado — mismo criterio exacto que
/// `mostrarDialogoEliminarCompraFisicamente`: diálogo propio con un
/// `RisegSelect` fijo + detalle condicional, en vez del caparazón
/// genérico compartido por 10+ dominios.
Future<bool> mostrarDialogoEliminarNominaFisicamente(BuildContext context, WidgetRef ref, String nominaId) async {
  final l10n = AppLocalizations.of(context)!;

  MotivoEliminacionFisicaNomina? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.eliminacionFisicaAccionMenu,
    confirmLabel: l10n.eliminacionFisicaBotonConfirmar,
    cancelLabel: l10n.generarNominaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoEliminacionFisicaNomina.otro;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.eliminacionFisicaAdvertenciaGenerica, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<MotivoEliminacionFisicaNomina>(
                label: l10n.eliminacionFisicaCampoMotivo,
                value: motivoSeleccionado,
                items: [
                  for (final motivo in MotivoEliminacionFisicaNomina.values)
                    RisegSelectItem(value: motivo, label: motivo.etiqueta),
                ],
                onChanged: (value) => setState(() => motivoSeleccionado = value),
              ),
              if (esOtro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  label: l10n.eliminarNominaFisicamenteCampoDetalle,
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
        errorGeneral = l10n.eliminarNominaFisicamenteErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(eliminarNominaFisicamenteAutorizadoProvider)(
        nominaId: nominaId,
        motivo: motivo,
        detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (resultado) {
        case EliminarNominaFisicamenteExitoso():
          RisegFeedback.showSuccess(context, l10n.eliminacionFisicaExito);
          return true;
        case EliminarNominaFisicamenteDetalleRequerido():
          errorGeneral = l10n.eliminarNominaFisicamenteErrorDetalleRequerido;
          return null;
        case EliminarNominaFisicamenteNoExiste():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
          return false;
        case EliminarNominaFisicamenteTieneDependencias(:final detalle):
          RisegFeedback.showError(context, detalle);
          return false;
        case EliminarNominaFisicamenteErrorInesperado():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => detalleCtrl.dispose());
  return resultado ?? false;
}
