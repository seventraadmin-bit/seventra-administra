import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_plan_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo "Registrar plan / costo" (Etapa 9A) — sirve tanto para el
/// primer plan de una línea como para "cambiar plan" (ver el doc
/// comment de `RegistrarPlanLineaTelefonicaUseCase`). Devuelve `true`
/// si tuvo éxito.
Future<bool> mostrarDialogoRegistrarPlanLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;

  final nombreCtrl = TextEditingController();
  final costoCtrl = TextEditingController();
  DateTime fechaInicioVigencia = DateTime.now();
  DateTime? fechaFinPermanencia;
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaPlanDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaPlanBotonGuardar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.lineaTelefonicaPlanCampoNombre, controller: nombreCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.lineaTelefonicaPlanCampoCostoMensual,
                controller: costoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaPlanCampoFechaInicioVigencia,
                value: fechaInicioVigencia,
                onChanged: (valor) => setState(() => fechaInicioVigencia = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaPlanCampoFechaFinPermanencia,
                value: fechaFinPermanencia,
                onChanged: (valor) => setState(() => fechaFinPermanencia = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaPlanCampoObservaciones, controller: observacionesCtrl),
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
      final costo = _centavosDesdeTexto(costoCtrl.text);
      if (costo == null) {
        errorGeneral = l10n.lineaTelefonicaPlanErrorCostoInvalido;
        return null;
      }

      final registrado = await ref.read(registrarPlanLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            nombre: nombreCtrl.text,
            costoMensual: costo,
            fechaInicioVigencia: fechaInicioVigencia,
            fechaFinPermanencia: fechaFinPermanencia,
            observaciones: observacionesCtrl.text,
          );
      if (!context.mounted) return false;

      switch (registrado) {
        case RegistrarPlanLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaPlanGuardadoExito);
          return true;
        case RegistrarPlanLineaTelefonicaNombreRequerido():
          errorGeneral = l10n.lineaTelefonicaPlanErrorNombreRequerido;
          return null;
        case RegistrarPlanLineaTelefonicaCostoInvalido():
          errorGeneral = l10n.lineaTelefonicaPlanErrorCostoInvalido;
          return null;
        case RegistrarPlanLineaTelefonicaPermanenciaInvalida():
          errorGeneral = l10n.lineaTelefonicaPlanErrorPermanenciaInvalida;
          return null;
        case RegistrarPlanLineaTelefonicaLineaDeBaja():
          RisegFeedback.showError(context, l10n.lineaTelefonicaPlanErrorLineaDeBaja);
          return false;
        case RegistrarPlanLineaTelefonicaLineaNoExiste():
        case RegistrarPlanLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    nombreCtrl.dispose();
    costoCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
