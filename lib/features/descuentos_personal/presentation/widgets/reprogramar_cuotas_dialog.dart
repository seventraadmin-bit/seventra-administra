import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formatoCentavosPago;

import '../../domain/usecases/generar_plan_cuotas.dart';
import '../../domain/usecases/reprogramar_cuotas_pendientes_usecase.dart';
import '../../domain/usecases/sugerir_primera_fecha_descuento.dart';
import '../descuentos_personal_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// "Reprogramar" (Etapa 15) — reemplaza el plan FUTURO completo
/// (`pendiente`/`reservada`) por uno nuevo sobre el `saldoPendiente`
/// real, nunca toca una cuota ya `aplicada`. `motivo` obligatorio.
Future<bool> mostrarDialogoReprogramarCuotas(
  BuildContext context,
  WidgetRef ref,
  DescuentoProgramadoEmpleadoData descuento,
) async {
  final l10n = AppLocalizations.of(context)!;
  final numeroCuotasCtrl = TextEditingController(text: '1');
  DateTime? fechaPrimeraCuota = sugerirPrimeraFechaDescuento(DateTime.now());
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.reprogramarCuotasDialogoTitulo,
    confirmLabel: l10n.reprogramarCuotasBotonConfirmar,
    cancelLabel: l10n.registrarDescuentoProgramadoBotonCancelar,
    contentBuilder:
        (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) {
            final numeroCuotas = int.tryParse(numeroCuotasCtrl.text.trim());
            final plan =
                (numeroCuotas != null &&
                        numeroCuotas > 0 &&
                        fechaPrimeraCuota != null)
                    ? generarPlanCuotas(
                      importeOriginal: descuento.saldoPendiente,
                      numeroCuotas: numeroCuotas,
                      fechaPrimera: fechaPrimeraCuota!,
                    )
                    : const <CuotaPlan>[];

            return SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reprogramarCuotasSaldoARedistribuir(
                        formatoCentavosPago(descuento.saldoPendiente),
                      ),
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.reprogramarCuotasCampoNumeroCuotas,
                      controller: numeroCuotasCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegDateField(
                      label: l10n.reprogramarCuotasCampoPrimeraFecha,
                      value: fechaPrimeraCuota,
                      onChanged:
                          (valor) => setState(() => fechaPrimeraCuota = valor),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.reprogramarCuotasCampoMotivo,
                      controller: motivoCtrl,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.registrarDescuentoProgramadoSeccionPrevisualizacion,
                      style: AppTypography.label,
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
                            Text(_formatoFecha.format(cuota.fechaProgramada)),
                            const SizedBox(width: AppSpacing.md),
                            Text(formatoCentavosPago(cuota.importe)),
                          ],
                        ),
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
      final numeroCuotas = int.tryParse(numeroCuotasCtrl.text.trim());
      if (numeroCuotas == null || numeroCuotas <= 0) {
        errorGeneral =
            l10n.registrarDescuentoProgramadoErrorNumeroCuotasInvalido;
        return null;
      }
      if (fechaPrimeraCuota == null) {
        errorGeneral = l10n.reprogramarCuotasCampoPrimeraFecha;
        return null;
      }
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.reprogramarCuotasErrorMotivoRequerido;
        return null;
      }

      final resultado = await ref
          .read(descuentosPersonalControllerProvider.notifier)
          .reprogramar(
            descuentoProgramadoId: descuento.id,
            numeroCuotas: numeroCuotas,
            fechaPrimeraCuota: fechaPrimeraCuota!,
            motivo: motivo,
          );
      if (!context.mounted) return false;

      switch (resultado) {
        case ReprogramarCuotasPendientesExitoso():
          RisegFeedback.showSuccess(context, l10n.reprogramarCuotasExito);
          return true;
        case ReprogramarCuotasPendientesMotivoRequerido():
          errorGeneral = l10n.reprogramarCuotasErrorMotivoRequerido;
          return null;
        case ReprogramarCuotasPendientesNumeroCuotasInvalido():
          errorGeneral =
              l10n.registrarDescuentoProgramadoErrorNumeroCuotasInvalido;
          return null;
        case ReprogramarCuotasPendientesSinSaldoPendiente():
          errorGeneral = l10n.reprogramarCuotasErrorSinSaldoPendiente;
          return null;
        case ReprogramarCuotasPendientesNoActivo():
        case ReprogramarCuotasPendientesNoExiste():
          RisegFeedback.showError(
            context,
            l10n.reprogramarCuotasErrorSinSaldoPendiente,
          );
          return false;
        case ReprogramarCuotasPendientesErrorInesperado():
          RisegFeedback.showError(
            context,
            l10n.reprogramarCuotasErrorInesperado,
          );
          return false;
      }
    },
  );

  numeroCuotasCtrl.dispose();
  motivoCtrl.dispose();
  return resultado ?? false;
}
