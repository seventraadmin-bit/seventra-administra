import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_cadena_prueba_nomina_usecase.dart';

import '../../../nomina_providers.dart';

/// "Eliminar cadena de prueba" (Etapa 15, ampliación de la limpieza
/// segura de datos de prueba) — facultad exclusiva del Usuario Maestro;
/// a diferencia de `mostrarDialogoEliminarNominaFisicamente` (solo
/// Borrador sin `PagoNomina`), esta acción SÍ alcanza una Nómina
/// Cerrada/Pagada junto con TODOS sus `PagoNomina`/Egresos — el botón
/// que la invoca solo debe mostrarse cuando la eliminación física
/// normal ya está bloqueada. La vista previa se carga ANTES de abrir el
/// diálogo de confirmación — si algo cruzó un punto irreversible, se
/// informa el motivo exacto y no se ofrece ningún formulario.
Future<bool> mostrarDialogoEliminarCadenaPruebaNomina(BuildContext context, WidgetRef ref, String nominaId) async {
  final l10n = AppLocalizations.of(context)!;

  final resumen = await ref.read(eliminarCadenaPruebaNominaUseCaseProvider).obtenerResumen(nominaId);
  if (!context.mounted) return false;

  if (!resumen.existe) {
    RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
    return false;
  }
  if (resumen.bloqueado) {
    RisegFeedback.showError(context, resumen.detalleBloqueo!);
    return false;
  }

  MotivoCadenaPruebaNomina? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.nominaCadenaPruebaTitulo,
    confirmLabel: l10n.eliminacionFisicaBotonConfirmar,
    cancelLabel: l10n.generarNominaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoCadenaPruebaNomina.otro;
        return SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.nominaCadenaPruebaAdvertencia, style: AppTypography.body),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.compraCadenaPruebaPreviewTitulo, style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.nominaCadenaPruebaPreviewFolio(resumen.folioNomina ?? '—', resumen.estatus ?? '—'), style: AppTypography.caption),
                Text(l10n.nominaCadenaPruebaPreviewRenglones(resumen.totalEmpleados, formatoCentavosPago(resumen.totalAPagar)), style: AppTypography.caption),
                if (resumen.pagos.isNotEmpty) ...[
                  Text(l10n.nominaCadenaPruebaPreviewPagos, style: AppTypography.caption),
                  for (final p in resumen.pagos)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Text(
                        '• ${p.folioPagoNomina} — ${formatoCentavosPago(p.montoTotal)}'
                        '${p.folioEgreso != null ? ' (${p.folioEgreso})' : ''}',
                        style: AppTypography.caption,
                      ),
                    ),
                ],
                if (resumen.descuentosInventarioAplicados > 0)
                  Text(
                    l10n.nominaCadenaPruebaPreviewDescuentos(
                      resumen.descuentosInventarioAplicados,
                      formatoCentavosPago(resumen.totalDescuentosInventarioAplicados),
                    ),
                    style: AppTypography.caption,
                  ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<MotivoCadenaPruebaNomina>(
                  label: l10n.compraCadenaPruebaCampoMotivo,
                  value: motivoSeleccionado,
                  items: [
                    for (final motivo in MotivoCadenaPruebaNomina.values)
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

      final resultado = await ref.read(eliminarCadenaPruebaNominaAutorizadoProvider)(
        nominaId: nominaId,
        motivo: motivo,
        detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (resultado) {
        case EliminarCadenaPruebaNominaExitoso():
          RisegFeedback.showSuccess(context, l10n.nominaCadenaPruebaExito);
          return true;
        case EliminarCadenaPruebaNominaDetalleRequerido():
          errorGeneral = l10n.compraCadenaPruebaErrorDetalleRequerido;
          return null;
        case EliminarCadenaPruebaNominaNoExiste():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
          return false;
        case EliminarCadenaPruebaNominaTieneDependencias(:final detalle):
          RisegFeedback.showError(context, detalle);
          return false;
        case EliminarCadenaPruebaNominaErrorInesperado():
          RisegFeedback.showError(context, l10n.eliminacionFisicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => detalleCtrl.dispose());
  return resultado ?? false;
}
