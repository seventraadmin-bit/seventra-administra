import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;

import '../../domain/usecases/cancelar_compra_usecase.dart';
import '../compras_controller.dart';

String _estatusUnidadLabel(EstatusArticuloUnidad estatus) {
  return switch (estatus) {
    EstatusArticuloUnidad.disponible => 'disponible',
    EstatusArticuloUnidad.asignado => 'asignada',
    EstatusArticuloUnidad.danado => 'dañada',
    EstatusArticuloUnidad.perdido => 'perdida',
    EstatusArticuloUnidad.enLavanderia => 'en lavandería',
    EstatusArticuloUnidad.enReparacion => 'en reparación',
    EstatusArticuloUnidad.pendienteDesecho => 'pendiente de desecho',
    EstatusArticuloUnidad.baja => 'dada de baja',
  };
}

/// Diálogo "Cancelar compra" (Etapa 10) — reversión estructurada
/// (revierte Inventario, cancela el Egreso), nunca borrado. Motivo
/// estructurado (Etapa 15, bug real COM-000021): un `RisegSelect` con
/// los valores fijos de `MotivoCancelacionCompra`, `Otro` exige
/// detalle, y unas Observaciones siempre opcionales. Si el caso de uso
/// bloquea la cancelación (unidades ya no disponibles, o partidas por
/// cantidad ya consumidas/asignadas), se lista el detalle real — nunca
/// un mensaje genérico. Ver el doc comment de `CancelarCompraUseCase`.
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCancelarCompra(BuildContext context, WidgetRef ref, String compraId) async {
  final l10n = AppLocalizations.of(context)!;

  MotivoCancelacionCompra? motivoSeleccionado;
  final detalleCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.compraCancelarDialogoTitulo,
    confirmLabel: l10n.compraCancelarBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final esOtro = motivoSeleccionado == MotivoCancelacionCompra.otro;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.compraCancelarMensaje, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<MotivoCancelacionCompra>(
                label: l10n.compraCancelarCampoMotivo,
                value: motivoSeleccionado,
                items: [
                  for (final motivo in MotivoCancelacionCompra.values)
                    RisegSelectItem(value: motivo, label: motivo.etiqueta),
                ],
                onChanged: (value) => setState(() => motivoSeleccionado = value),
              ),
              if (esOtro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.compraCancelarCampoDetalle, controller: detalleCtrl, autofocus: true),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.compraCancelarCampoObservaciones, controller: observacionesCtrl),
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
        errorGeneral = l10n.compraCancelarErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref.read(comprasControllerProvider.notifier).cancelarCompra(
            compraId: compraId,
            motivo: motivo,
            detalle: detalleCtrl.text.trim().isEmpty ? null : detalleCtrl.text.trim(),
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
          );
      if (!context.mounted) return false;

      switch (resultado) {
        case CancelarCompraExitosa():
          RisegFeedback.showSuccess(context, l10n.compraCancelarExito);
          return true;
        case CancelarCompraDetalleRequerido():
          errorGeneral = l10n.compraCancelarErrorDetalleRequerido;
          return null;
        case CancelarCompraYaCancelada():
          errorGeneral = l10n.compraCancelarYaCancelada;
          return null;
        case CancelarCompraBloqueadaPorUnidadesNoDisponibles(:final unidades):
          final detalle = unidades
              .map((u) => '${u.codigo} (${_estatusUnidadLabel(EstatusArticuloUnidad.values.byName(u.estatus))})')
              .join(', ');
          errorGeneral = '${l10n.compraCancelarBloqueadaMensaje} $detalle';
          return null;
        case CancelarCompraBloqueadaPorArticulosConsumidos(:final detalles):
          errorGeneral = '${l10n.compraCancelarBloqueadaArticulosMensaje} ${detalles.join(' ')}';
          return null;
        case CancelarCompraNoExiste():
        case CancelarCompraErrorInesperado():
          RisegFeedback.showError(context, l10n.compraErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    detalleCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
