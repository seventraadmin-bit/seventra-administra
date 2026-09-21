import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/compras/domain/usecases/eliminar_cadena_prueba_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../compras_providers.dart';

/// "Eliminar cadena de prueba" (Etapa 15, limpieza segura de datos de
/// prueba) — facultad exclusiva del Usuario Maestro; el botón que
/// invoca esta función solo debe mostrarse cuando la eliminación
/// física normal (`mostrarDialogoEliminarCompraFisicamente`) está
/// bloqueada por historia posterior (ver `_bloqueadaEliminacionNormal`
/// en `CompraExpedienteScreen`). La vista previa se carga ANTES de
/// abrir el diálogo de confirmación — si algo cruzó un punto
/// irreversible, se informa el motivo exacto y no se ofrece ningún
/// formulario (nada que confirmar).
Future<bool> mostrarDialogoEliminarCadenaPruebaCompra(BuildContext context, WidgetRef ref, String compraId) async {
  final l10n = AppLocalizations.of(context)!;

  final resumen = await ref.read(eliminarCadenaPruebaCompraUseCaseProvider).obtenerResumen(compraId);
  if (!context.mounted) return false;

  if (!resumen.existe) {
    RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
    return false;
  }
  if (resumen.bloqueado) {
    RisegFeedback.showError(context, resumen.detalleBloqueo!);
    return false;
  }

  MotivoCadenaPruebaCompra? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.compraCadenaPruebaTitulo,
    confirmLabel: l10n.eliminacionFisicaBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoCadenaPruebaCompra.otro;
        return SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.compraCadenaPruebaAdvertencia, style: AppTypography.body),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.compraCadenaPruebaPreviewTitulo, style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.compraCadenaPruebaPreviewFolioCompra(resumen.folioCompra ?? '—'), style: AppTypography.caption),
                if (resumen.folioEgreso != null)
                  Text(
                    l10n.compraCadenaPruebaPreviewEgreso(resumen.folioEgreso!, formatoCentavosPago(resumen.montoEgreso ?? 0)),
                    style: AppTypography.caption,
                  ),
                if (resumen.entradasInventario > 0)
                  Text(l10n.compraCadenaPruebaPreviewEntradas(resumen.entradasInventario), style: AppTypography.caption),
                if (resumen.asignaciones.isNotEmpty) ...[
                  Text(l10n.compraCadenaPruebaPreviewAsignaciones, style: AppTypography.caption),
                  for (final a in resumen.asignaciones)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Text('• $a', style: AppTypography.caption),
                    ),
                ],
                if (resumen.movimientosDerivados > 0)
                  Text(l10n.compraCadenaPruebaPreviewMovimientos(resumen.movimientosDerivados), style: AppTypography.caption),
                if (resumen.descuentosPendientes > 0)
                  Text(
                    l10n.compraCadenaPruebaPreviewDescuentos(
                      resumen.descuentosPendientes,
                      formatoCentavosPago(resumen.totalDescuentosPendientes),
                    ),
                    style: AppTypography.caption,
                  ),
                if (resumen.totalRegistrosRelacionados == 0)
                  Text(l10n.compraCadenaPruebaPreviewSinRelacionados, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<MotivoCadenaPruebaCompra>(
                  label: l10n.compraCadenaPruebaCampoMotivo,
                  value: motivoSeleccionado,
                  items: [
                    for (final motivo in MotivoCadenaPruebaCompra.values)
                      RisegSelectItem(value: motivo, label: motivo.etiqueta),
                  ],
                  onChanged: (value) => setState(() => motivoSeleccionado = value),
                ),
                if (esOtro) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    label: l10n.compraCadenaPruebaCampoDetalle,
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
          ),
        );
      },
    ),
    onConfirm: () async {
      final motivo = motivoSeleccionado;
      if (motivo == null) {
        errorGeneral = l10n.compraCadenaPruebaErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(eliminarCadenaPruebaCompraAutorizadoProvider)(
        compraId: compraId,
        motivo: motivo,
        detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (resultado) {
        case EliminarCadenaPruebaCompraExitoso():
          RisegFeedback.showSuccess(context, l10n.compraCadenaPruebaExito);
          return true;
        case EliminarCadenaPruebaCompraDetalleRequerido():
          errorGeneral = l10n.compraCadenaPruebaErrorDetalleRequerido;
          return null;
        case EliminarCadenaPruebaCompraNoExiste():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
          return false;
        case EliminarCadenaPruebaCompraTieneDependencias(:final detalle):
          RisegFeedback.showError(context, detalle);
          return false;
        case EliminarCadenaPruebaCompraErrorInesperado():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => detalleCtrl.dispose());
  return resultado ?? false;
}
