import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';

import '../../../../notificaciones/presentation/notificaciones_controller.dart';
import '../../../finanzas_providers.dart';
import '../../complementos/complementos_controller.dart';

/// Diálogo "Registrar complemento" desde el detalle de un Pago (Etapa
/// 4J.3) — el Complemento ya se generó y timbró externamente, aquí
/// solo se deja constancia administrativa. Relación 1:1 con el Pago
/// (Resolución definitiva de Marlon).
///
/// Devuelve `true` si el registro tuvo éxito.
Future<bool> mostrarDialogoRegistrarComplemento(BuildContext context, WidgetRef ref, String pagoId) async {
  final l10n = AppLocalizations.of(context)!;
  final uuidController = TextEditingController();
  final serieFiscalController = TextEditingController();
  final folioFiscalController = TextEditingController();
  final montoController = TextEditingController();
  final observacionesController = TextEditingController();
  DateTime? fechaSeleccionada;
  String? errorUuid;
  String? errorMonto;
  String? errorFecha;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarComplementoDialogoTitulo,
    confirmLabel: l10n.registrarComplementoBotonConfirmar,
    cancelLabel: l10n.registrarComplementoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              label: l10n.registrarComplementoCampoUuid,
              controller: uuidController,
              errorText: errorUuid,
              onChanged: (_) => setState(() => errorUuid = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarComplementoCampoSerieFiscal, controller: serieFiscalController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarComplementoCampoFolioFiscal, controller: folioFiscalController),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.registrarComplementoCampoFechaTimbrado,
              value: fechaSeleccionada,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fechaSeleccionada = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.registrarComplementoCampoMontoTotal,
              controller: montoController,
              keyboardType: TextInputType.number,
              errorText: errorMonto,
              onChanged: (_) => setState(() => errorMonto = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.registrarComplementoCampoObservaciones, controller: observacionesController),
          ],
        );
      },
    ),
    onConfirm: () async {
      // `null`, no `false`: `RisegDialog.showForm` cierra con cualquier
      // resultado no nulo, así que devolver `false` aquí cerraba el
      // diálogo y el usuario nunca llegaba a ver el error que se acaba
      // de escribir en `errorUuid`/`errorMonto`/`errorFecha`.
      final uuid = uuidController.text.trim();
      if (uuid.isEmpty) {
        errorUuid = l10n.registrarComplementoErrorUuidFormatoInvalido;
        return null;
      }
      final monto = _centavosDesdeTexto(montoController.text);
      if (monto == null || monto <= 0) {
        errorMonto = l10n.registrarComplementoErrorMontoInvalido;
        return null;
      }
      if (fechaSeleccionada == null) {
        errorFecha = l10n.registrarComplementoCampoFechaTimbrado;
        return null;
      }
      final resultado = await ref.read(registrarComplementoPagoAutorizadoProvider)(
            pagoId: pagoId,
            uuid: uuid,
            serieFiscal: serieFiscalController.text.trim().isEmpty ? null : serieFiscalController.text.trim(),
            folioFiscal: folioFiscalController.text.trim().isEmpty ? null : folioFiscalController.text.trim(),
            fechaTimbrado: fechaSeleccionada!,
            montoTotal: monto,
            observaciones:
                observacionesController.text.trim().isEmpty ? null : observacionesController.text.trim(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarComplementoPagoExitoso():
          // La obligación quedó cumplida: debe desaparecer del contador
          // de la campana y de la vista Pendientes SIN reiniciar la app.
          ref.invalidate(notificacionesControllerProvider);
          ref.invalidate(complementosControllerProvider);
          RisegFeedback.showSuccess(context, l10n.registrarComplementoExito);
          return true;
        case RegistrarComplementoPagoPagoNoExiste():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorPagoNoExiste);
          return false;
        case RegistrarComplementoPagoPagoCancelado():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorPagoCancelado);
          return false;
        case RegistrarComplementoPagoYaExiste():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorYaExiste);
          return false;
        case RegistrarComplementoPagoUuidFormatoInvalido():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorUuidFormatoInvalido);
          return false;
        case RegistrarComplementoPagoUuidYaRegistrado():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorUuidYaRegistrado);
          return false;
        case RegistrarComplementoPagoMontoInvalido():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorMontoInvalido);
          return false;
        case RegistrarComplementoPagoFechaTimbradoAnteriorAlPago():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorFechaTimbradoAnteriorAlPago);
          return false;
        case RegistrarComplementoPagoErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarComplementoErrorInesperado);
          return false;
      }
    },
  );

  uuidController.dispose();
  serieFiscalController.dispose();
  folioFiscalController.dispose();
  montoController.dispose();
  observacionesController.dispose();
  return resultado ?? false;
}

/// Convierte texto capturado en pesos a centavos — mismo criterio que
/// el resto del proyecto.
int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}
