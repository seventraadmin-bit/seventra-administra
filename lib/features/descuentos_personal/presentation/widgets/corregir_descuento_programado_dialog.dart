import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formatoCentavosPago;

import '../../domain/usecases/corregir_descuento_programado_usecase.dart';
import '../../domain/usecases/generar_plan_cuotas.dart';
import '../../domain/usecases/sugerir_primera_fecha_descuento.dart';
import '../descuentos_personal_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// "Corregir" (Etapa 5) — a diferencia de "Reprogramar" (que solo mueve
/// el plan futuro sobre el `saldoPendiente` actual), esta corrección
/// puede tocar el monto total de la obligación y campos administrativos
/// (tipo/fecha de registro/observaciones). Cuando el monto total
/// cambia, exige un plan de cuotas futuro nuevo (mismo requisito que
/// "Reprogramar") — el saldo a redistribuir es el NUEVO saldo pendiente
/// (`nuevoTotal − totalAplicadoHistorico`), nunca el importe libre.
/// `motivo` siempre obligatorio.
Future<bool> mostrarDialogoCorregirDescuentoProgramado(
  BuildContext context,
  WidgetRef ref,
  DescuentoProgramadoEmpleadoData descuento,
) async {
  final l10n = AppLocalizations.of(context)!;
  final totalAplicadoHistorico =
      descuento.importeOriginal - descuento.saldoPendiente;

  String tipo = descuento.tipo;
  DateTime fechaRegistro = descuento.fechaRegistro;
  final importeCtrl = TextEditingController(
    text: (descuento.importeOriginal / 100).toStringAsFixed(2),
  );
  final observacionesCtrl = TextEditingController(
    text: descuento.observaciones ?? '',
  );
  final numeroCuotasCtrl = TextEditingController(text: '1');
  DateTime? fechaPrimeraCuota = sugerirPrimeraFechaDescuento(DateTime.now());
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirDescuentoDialogoTitulo,
    confirmLabel: l10n.corregirDescuentoBotonConfirmar,
    cancelLabel: l10n.registrarDescuentoProgramadoBotonCancelar,
    contentBuilder:
        (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) {
            final importe = _centavosDesdeTexto(importeCtrl.text);
            final importeCambia =
                importe != null && importe != descuento.importeOriginal;
            final nuevoSaldoPendiente =
                importeCambia ? importe - totalAplicadoHistorico : null;
            final numeroCuotas = int.tryParse(numeroCuotasCtrl.text.trim());
            final plan =
                (importeCambia &&
                        nuevoSaldoPendiente != null &&
                        nuevoSaldoPendiente > 0 &&
                        numeroCuotas != null &&
                        numeroCuotas > 0 &&
                        fechaPrimeraCuota != null)
                    ? generarPlanCuotas(
                      importeOriginal: nuevoSaldoPendiente,
                      numeroCuotas: numeroCuotas,
                      fechaPrimera: fechaPrimeraCuota!,
                    )
                    : const <CuotaPlan>[];

            return SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.corregirDescuentoAvisoAplicado(
                        formatoCentavosPago(totalAplicadoHistorico),
                      ),
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegSelect<String>(
                      label: l10n.corregirDescuentoCampoTipo,
                      value: tipo,
                      items: [
                        RisegSelectItem(
                          value: 'prestamo',
                          label: l10n.descuentosPersonalTipoPrestamo,
                        ),
                        RisegSelectItem(
                          value: 'botas',
                          label: l10n.descuentosPersonalTipoBotas,
                        ),
                      ],
                      onChanged: (valor) => setState(() => tipo = valor ?? tipo),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegDateField(
                      label: l10n.corregirDescuentoCampoFecha,
                      value: fechaRegistro,
                      onChanged:
                          (valor) => setState(() => fechaRegistro = valor),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.corregirDescuentoCampoImporte,
                      controller: importeCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.corregirDescuentoCampoObservaciones,
                      controller: observacionesCtrl,
                    ),
                    if (importeCambia) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.corregirDescuentoSeccionNuevoPlan,
                        style: AppTypography.label,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (nuevoSaldoPendiente != null && nuevoSaldoPendiente > 0) ...[
                        Text(
                          l10n.corregirDescuentoNuevoSaldoPendiente(
                            formatoCentavosPago(nuevoSaldoPendiente),
                          ),
                          style: AppTypography.body,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        RisegTextField(
                          label: l10n.corregirDescuentoCampoNumeroCuotas,
                          controller: numeroCuotasCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        RisegDateField(
                          label: l10n.corregirDescuentoCampoPrimeraFecha,
                          value: fechaPrimeraCuota,
                          onChanged:
                              (valor) =>
                                  setState(() => fechaPrimeraCuota = valor),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        for (final cuota in plan)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.registrarDescuentoProgramadoPrevisualizacionCuota(
                                      cuota.numeroCuota,
                                      plan.length,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatoFecha.format(cuota.fechaProgramada),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Text(formatoCentavosPago(cuota.importe)),
                              ],
                            ),
                          ),
                      ] else
                        Text(
                          l10n.corregirDescuentoNuevoSaldoPendiente(
                            formatoCentavosPago(0),
                          ),
                          style: AppTypography.body,
                        ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.corregirDescuentoCampoMotivo,
                      controller: motivoCtrl,
                    ),
                    if (errorGeneral != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        errorGeneral!,
                        style: AppTypography.caption.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
    onConfirm: () async {
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.corregirDescuentoErrorMotivoRequerido;
        return null;
      }
      final importe = _centavosDesdeTexto(importeCtrl.text);
      if (importe == null || importe <= 0) {
        errorGeneral = l10n.corregirDescuentoErrorValorInvalido;
        return null;
      }
      final importeCambia = importe != descuento.importeOriginal;
      final numeroCuotas =
          importeCambia ? int.tryParse(numeroCuotasCtrl.text.trim()) : null;
      final nuevoSaldoPendiente =
          importeCambia ? importe - totalAplicadoHistorico : null;
      if (importeCambia &&
          nuevoSaldoPendiente != null &&
          nuevoSaldoPendiente > 0 &&
          (numeroCuotas == null ||
              numeroCuotas <= 0 ||
              fechaPrimeraCuota == null)) {
        errorGeneral = l10n.corregirDescuentoErrorRequiereNuevoPlan;
        return null;
      }

      final resultado = await ref
          .read(descuentosPersonalControllerProvider.notifier)
          .corregir(
            descuentoProgramadoId: descuento.id,
            tipo: tipo,
            fechaRegistro: fechaRegistro,
            importeOriginal: importe,
            numeroCuotas: numeroCuotas,
            fechaPrimeraCuota: fechaPrimeraCuota,
            observaciones:
                observacionesCtrl.text.trim().isEmpty
                    ? null
                    : observacionesCtrl.text.trim(),
            limpiarObservaciones: observacionesCtrl.text.trim().isEmpty,
            motivo: motivo,
          );
      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirDescuentoProgramadoExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirDescuentoExito);
          return true;
        case CorregirDescuentoProgramadoMotivoRequerido():
          errorGeneral = l10n.corregirDescuentoErrorMotivoRequerido;
          return null;
        case CorregirDescuentoProgramadoValorInvalido():
          errorGeneral = l10n.corregirDescuentoErrorValorInvalido;
          return null;
        case CorregirDescuentoProgramadoRequiereNuevoPlan():
          errorGeneral = l10n.corregirDescuentoErrorRequiereNuevoPlan;
          return null;
        case CorregirDescuentoProgramadoExcedeLoAplicado(:final totalAplicado):
          errorGeneral = l10n.corregirDescuentoErrorExcedeLoAplicado(
            formatoCentavosPago(totalAplicado),
          );
          return null;
        case CorregirDescuentoProgramadoNoActivo():
        case CorregirDescuentoProgramadoNoExiste():
          RisegFeedback.showError(context, l10n.corregirDescuentoErrorNoActivo);
          return false;
        case CorregirDescuentoProgramadoErrorInesperado():
          RisegFeedback.showError(
            context,
            l10n.corregirDescuentoErrorInesperado,
          );
          return false;
      }
    },
  );

  importeCtrl.dispose();
  observacionesCtrl.dispose();
  numeroCuotasCtrl.dispose();
  motivoCtrl.dispose();
  return resultado ?? false;
}
