import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';

import '../../../finanzas_providers.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;

/// Diálogo "Registrar pago" desde el detalle de una Cuenta por cobrar
/// (Etapa 4J.2) — el flujo simplificado que expone la interfaz de esta
/// etapa: crea el Pago y lo aplica por completo a esta Cuenta en un
/// solo paso. La distribución de un mismo Pago entre varias Cuentas
/// queda para una pantalla futura (el modelo N:M ya lo soporta).
///
/// Devuelve `true` si el pago se registró con éxito.
Future<bool> mostrarDialogoRegistrarPagoAplicado(
  BuildContext context,
  WidgetRef ref, {
  required String cuentaPorCobrarId,
  required int saldoPendiente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final montoController = TextEditingController();
  DateTime? fechaSeleccionada;
  FormaPago formaSeleccionada = FormaPago.transferencia;
  final referenciaController = TextEditingController();
  final bancoOrigenController = TextEditingController();
  final cuentaBancariaController = TextEditingController();
  final observacionesController = TextEditingController();
  String? errorMonto;
  String? errorFecha;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.pagoAplicadoDialogoTitulo,
    confirmLabel: l10n.pagoAplicadoBotonConfirmar,
    cancelLabel: l10n.pagoAplicadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CampoConsultaSaldoPendiente(
              label: l10n.pagoAplicadoCampoSaldoPendiente,
              value: formatoCentavosPago(saldoPendiente),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.pagoAplicadoCampoMonto,
              controller: montoController,
              keyboardType: TextInputType.number,
              errorText: errorMonto,
              onChanged: (_) => setState(() => errorMonto = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.pagoAplicadoCampoFecha,
              value: fechaSeleccionada,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fechaSeleccionada = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<FormaPago>(
              label: l10n.pagoAplicadoCampoFormaPago,
              value: formaSeleccionada,
              items: [
                for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name)),
              ],
              onChanged: (valor) => setState(() => formaSeleccionada = valor ?? formaSeleccionada),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.pagoAplicadoCampoReferencia, controller: referenciaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.pagoAplicadoCampoBancoOrigen, controller: bancoOrigenController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.pagoAplicadoCampoCuentaBancariaDestino, controller: cuentaBancariaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.pagoAplicadoCampoObservaciones, controller: observacionesController),
          ],
        );
      },
    ),
    onConfirm: () async {
      final monto = _centavosDesdeTexto(montoController.text);
      if (monto == null || monto <= 0) {
        errorMonto = l10n.pagoAplicadoErrorMontoInvalido;
        return false;
      }
      if (fechaSeleccionada == null) {
        errorFecha = l10n.pagoAplicadoCampoFecha;
        return false;
      }

      final resultado = await ref.read(registrarPagoAplicadoUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            monto: monto,
            fechaPago: fechaSeleccionada!,
            formaPago: formaSeleccionada.name,
            referencia: referenciaController.text.trim().isEmpty ? null : referenciaController.text.trim(),
            bancoOrigen: bancoOrigenController.text.trim().isEmpty ? null : bancoOrigenController.text.trim(),
            cuentaBancariaDestino:
                cuentaBancariaController.text.trim().isEmpty ? null : cuentaBancariaController.text.trim(),
            observaciones: observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarPagoAplicadoExitoso():
          RisegFeedback.showSuccess(context, l10n.pagoAplicadoExito);
          return true;
        case RegistrarPagoAplicadoCuentaNoExiste():
          RisegFeedback.showError(context, l10n.pagoAplicadoErrorCuentaNoExiste);
          return false;
        case RegistrarPagoAplicadoCuentaYaPagada():
          RisegFeedback.showError(context, l10n.pagoAplicadoErrorCuentaYaPagada);
          return false;
        case RegistrarPagoAplicadoMontoInvalido():
          RisegFeedback.showError(context, l10n.pagoAplicadoErrorMontoInvalido);
          return false;
        case RegistrarPagoAplicadoSobrepago():
          RisegFeedback.showError(
            context,
            l10n.pagoAplicadoErrorSobrepago(formatoCentavosPago(resultado.saldoDisponible)),
          );
          return false;
        case RegistrarPagoAplicadoErrorInesperado():
          RisegFeedback.showError(context, l10n.pagoAplicadoErrorInesperado);
          return false;
      }
    },
  );

  montoController.dispose();
  referenciaController.dispose();
  bancoOrigenController.dispose();
  cuentaBancariaController.dispose();
  observacionesController.dispose();
  return resultado ?? false;
}

/// Convierte texto capturado en pesos (ej. "1500.50") a centavos —
/// misma unidad que el resto del proyecto. `null` si el texto no es
/// un número válido.
int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Par etiqueta/valor de solo lectura simple, usado aquí para mostrar
/// el saldo pendiente de referencia dentro del formulario — no
/// reutiliza `CampoConsulta` (que asume "Pendiente de captura" para
/// valores vacíos, una semántica que no aplica a un saldo siempre
/// presente).
class CampoConsultaSaldoPendiente extends StatelessWidget {
  const CampoConsultaSaldoPendiente({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
      ],
    );
  }
}
