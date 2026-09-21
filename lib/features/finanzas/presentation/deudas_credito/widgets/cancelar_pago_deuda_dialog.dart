import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_deuda_usecase.dart';

import '../../../finanzas_providers.dart';
import '../deudas_credito_list_screen.dart' show formatoCentavosDeuda;

/// Diálogo "Cancelar pago" de una Deuda/TDC (Etapa 9) — revierte por
/// completo un pago individual: la Deuda recupera el saldo, el `Egreso`
/// se cancela (y con él Caja y bancos recupera el dinero) y, en una
/// tarjeta, se libera el crédito disponible.
///
/// El movimiento original nunca se borra: la reversión es una línea
/// nueva del historial. Motivo obligatorio.
///
/// Devuelve `true` si la cancelación tuvo éxito.
Future<bool> mostrarDialogoCancelarPagoDeuda(
  BuildContext context,
  WidgetRef ref, {
  required MovimientoDeudaData pago,
  required int importeNeto,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorMotivo;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cancelarPagoDeudaDialogoTitulo,
    confirmLabel: l10n.cancelarPagoDeudaBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final colors = context.colors;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cancelarPagoDeudaAdvertencia(formatoCentavosDeuda(importeNeto)),
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.cancelarPagoDeudaCampoMotivo,
                controller: motivoCtrl,
                errorText: errorMotivo,
                autofocus: true,
                onChanged: (_) => setState(() => errorMotivo = null),
              ),
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      if (motivoCtrl.text.trim().isEmpty) {
        errorMotivo = l10n.cancelarPagoDeudaErrorMotivoRequerido;
        return null;
      }

      final r = await ref.read(cancelarPagoDeudaAutorizadoProvider)(
        pagoId: pago.id,
        motivo: motivoCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (r) {
        case CancelarPagoDeudaExitoso(:final cicloTarjetaRequiereConciliacion):
          // El ciclo de la tarjeta solo retrocede cuando deshacerlo es
          // inequívoco. Cuando no lo es, se dice en voz alta en vez de
          // dejar el dato desactualizado en silencio.
          if (cicloTarjetaRequiereConciliacion) {
            // Sin variante "warning" en RisegFeedback: se muestra como
            // error para que el aviso no pase desapercibido — lo que
            // importa es que el operador VEA que debe conciliar.
            RisegFeedback.showError(context, l10n.cancelarPagoDeudaExitoConciliarCiclo);
          } else {
            RisegFeedback.showSuccess(context, l10n.cancelarPagoDeudaExito);
          }
          return true;
        case CancelarPagoDeudaMotivoRequerido():
          errorMotivo = l10n.cancelarPagoDeudaErrorMotivoRequerido;
          return null;
        case CancelarPagoDeudaYaCancelado():
          RisegFeedback.showError(context, l10n.cancelarPagoDeudaErrorYaCancelado);
          return false;
        case CancelarPagoDeudaDeudaCancelada():
          RisegFeedback.showError(context, l10n.cancelarPagoDeudaErrorDeudaCancelada);
          return false;
        case CancelarPagoDeudaNoExiste():
        case CancelarPagoDeudaErrorInesperado():
          RisegFeedback.showError(context, l10n.cancelarPagoDeudaErrorInesperado);
          return false;
      }
    },
  );

  motivoCtrl.dispose();
  return resultado ?? false;
}
