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
    EstatusArticuloUnidad.baja => 'dada de baja',
  };
}

/// Diálogo "Cancelar compra" (Etapa 10) — reversión estructurada
/// (revierte Inventario, cancela el Egreso), nunca borrado. Si el
/// caso de uso bloquea la cancelación por unidades ya no disponibles,
/// se lista cada una con su estatus — nunca un mensaje genérico. Ver
/// el doc comment de `CancelarCompraUseCase`. Devuelve `true` si tuvo
/// éxito.
Future<bool> mostrarDialogoCancelarCompra(BuildContext context, WidgetRef ref, String compraId) async {
  final l10n = AppLocalizations.of(context)!;

  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.compraCancelarDialogoTitulo,
    confirmLabel: l10n.compraCancelarBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.compraCancelarMensaje, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.compraCancelarCampoMotivo, controller: motivoCtrl, autofocus: true),
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
      final resultado = await ref
          .read(comprasControllerProvider.notifier)
          .cancelarCompra(compraId: compraId, motivo: motivoCtrl.text.trim());
      if (!context.mounted) return false;

      switch (resultado) {
        case CancelarCompraExitosa():
          RisegFeedback.showSuccess(context, l10n.compraCancelarExito);
          return true;
        case CancelarCompraYaCancelada():
          errorGeneral = l10n.compraCancelarYaCancelada;
          return null;
        case CancelarCompraBloqueadaPorUnidadesNoDisponibles(:final unidades):
          final detalle = unidades
              .map((u) => '${u.codigo} (${_estatusUnidadLabel(EstatusArticuloUnidad.values.byName(u.estatus))})')
              .join(', ');
          errorGeneral = '${l10n.compraCancelarBloqueadaMensaje} $detalle';
          return null;
        case CancelarCompraNoExiste():
        case CancelarCompraErrorInesperado():
          RisegFeedback.showError(context, l10n.compraErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
