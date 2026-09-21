import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_deuda_usecase.dart';

import '../../../finanzas_providers.dart';
import '../../ingresos/widgets/ingreso_monto_utils.dart';
import '../deudas_credito_list_screen.dart' show formatoCentavosDeuda;

/// Diálogo "Corregir pago" de una Deuda/TDC (Etapa 9) — corrige el
/// importe, la `CuentaFinanciera` de la que salió, o ambos, en una sola
/// transacción que mantiene sincronizados el `MovimientoDeuda` y su
/// `Egreso`.
///
/// El pago original nunca se reescribe: la diferencia se asienta como
/// un ajuste vinculado, así que el historial conserva lo que se capturó
/// por error. Motivo obligatorio.
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirPagoDeuda(
  BuildContext context,
  WidgetRef ref, {
  required DeudaData deuda,
  required MovimientoDeudaData pago,
  required int importeNeto,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  final egreso = pago.egresoId == null ? null : await ref.read(egresoRepositoryProvider).obtenerPorId(pago.egresoId!);
  if (!context.mounted) return false;

  final importeCtrl = TextEditingController(text: (importeNeto / 100).toStringAsFixed(2));
  final motivoCtrl = TextEditingController();
  String? cuentaFinancieraId = egreso?.cuentaFinancieraId;
  String? errorImporte;
  String? errorMotivo;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirPagoDeudaDialogoTitulo,
    confirmLabel: l10n.corregirPagoDeudaBotonConfirmar,
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
                l10n.corregirPagoDeudaImporteActual(formatoCentavosDeuda(importeNeto)),
                style: AppTypography.label,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.corregirPagoDeudaSaldoActual(formatoCentavosDeuda(deuda.saldoActual)),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.corregirPagoDeudaCampoImporte,
                controller: importeCtrl,
                keyboardType: TextInputType.number,
                errorText: errorImporte,
                autofocus: true,
                onChanged: (_) => setState(() => errorImporte = null),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.movimientoCampoCuentaFinanciera,
                value: cuentaFinancieraId,
                helperText: l10n.corregirPagoDeudaCuentaAyuda,
                items: [
                  RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                  for (final c in cuentas) RisegSelectItem(value: c.id, label: c.nombre),
                ],
                onChanged: (valor) => setState(() => cuentaFinancieraId = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.corregirPagoDeudaCampoMotivo,
                controller: motivoCtrl,
                errorText: errorMotivo,
                onChanged: (_) => setState(() => errorMotivo = null),
              ),
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final importe = centavosDesdeTexto(importeCtrl.text);
      if (importe == null || importe <= 0) {
        errorImporte = l10n.registrarPagoDeudaErrorImporteInvalido;
        return null;
      }
      if (motivoCtrl.text.trim().isEmpty) {
        errorMotivo = l10n.corregirPagoDeudaErrorMotivoRequerido;
        return null;
      }

      final r = await ref.read(corregirPagoDeudaAutorizadoProvider)(
        pagoId: pago.id,
        nuevoImporte: importe,
        nuevaCuentaFinancieraId: cuentaFinancieraId,
        limpiarCuentaFinanciera: cuentaFinancieraId == null,
        motivo: motivoCtrl.text.trim(),
      );
      if (!context.mounted) return false;

      switch (r) {
        case CorregirPagoDeudaExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirPagoDeudaExito);
          return true;
        case CorregirPagoDeudaSobrepasaSaldo(:final importeMaximo):
          errorImporte = l10n.corregirPagoDeudaErrorSobrepasaSaldo(formatoCentavosDeuda(importeMaximo));
          return null;
        case CorregirPagoDeudaImporteInvalido():
          errorImporte = l10n.registrarPagoDeudaErrorImporteInvalido;
          return null;
        case CorregirPagoDeudaMotivoRequerido():
          errorMotivo = l10n.corregirPagoDeudaErrorMotivoRequerido;
          return null;
        case CorregirPagoDeudaCancelado():
          RisegFeedback.showError(context, l10n.corregirPagoDeudaErrorCancelado);
          return false;
        case CorregirPagoDeudaDeudaCancelada():
          RisegFeedback.showError(context, l10n.corregirPagoDeudaErrorDeudaCancelada);
          return false;
        case CorregirPagoDeudaNoExiste():
        case CorregirPagoDeudaErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirPagoDeudaErrorInesperado);
          return false;
      }
    },
  );

  importeCtrl.dispose();
  motivoCtrl.dispose();
  return resultado ?? false;
}
