import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_antidoping_usecase.dart';

import '../../../personal_providers.dart';

String resultadoSustanciaAntidopingLabel(AppLocalizations l10n, String valor) {
  return switch (ResultadoSustanciaAntidoping.values.byName(valor)) {
    ResultadoSustanciaAntidoping.negativo => l10n.resultadoSustanciaAntidopingNegativo,
    ResultadoSustanciaAntidoping.positivo => l10n.resultadoSustanciaAntidopingPositivo,
    ResultadoSustanciaAntidoping.noAplica => l10n.resultadoSustanciaAntidopingNoAplica,
  };
}

RisegStatusTone resultadoSustanciaAntidopingTono(String valor) {
  return switch (ResultadoSustanciaAntidoping.values.byName(valor)) {
    ResultadoSustanciaAntidoping.negativo => RisegStatusTone.success,
    ResultadoSustanciaAntidoping.positivo => RisegStatusTone.error,
    ResultadoSustanciaAntidoping.noAplica => RisegStatusTone.neutral,
  };
}

/// Diálogo combinado "Antidoping" (Etapa 5B) — un resultado por
/// sustancia (AMP/BZD/COC/MET/OPI), nunca un resultado único general
/// (Resolución explícita de Marlon). Mismo diseño de PDF opcional en
/// el mismo paso que Perfil psicológico/Estudio socioeconómico.
///
/// Devuelve `true` si se guardó correctamente.
Future<bool> mostrarDialogoAntidopingEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime? fecha = empleado.fechaAntidoping;
  ResultadoSustanciaAntidoping amp =
      empleado.resultadoAmp == null ? ResultadoSustanciaAntidoping.noAplica : ResultadoSustanciaAntidoping.values.byName(empleado.resultadoAmp!);
  ResultadoSustanciaAntidoping bzd =
      empleado.resultadoBzd == null ? ResultadoSustanciaAntidoping.noAplica : ResultadoSustanciaAntidoping.values.byName(empleado.resultadoBzd!);
  ResultadoSustanciaAntidoping coc =
      empleado.resultadoCoc == null ? ResultadoSustanciaAntidoping.noAplica : ResultadoSustanciaAntidoping.values.byName(empleado.resultadoCoc!);
  ResultadoSustanciaAntidoping met =
      empleado.resultadoMet == null ? ResultadoSustanciaAntidoping.noAplica : ResultadoSustanciaAntidoping.values.byName(empleado.resultadoMet!);
  ResultadoSustanciaAntidoping opi =
      empleado.resultadoOpi == null ? ResultadoSustanciaAntidoping.noAplica : ResultadoSustanciaAntidoping.values.byName(empleado.resultadoOpi!);
  final observacionesController = TextEditingController(text: empleado.observacionesAntidoping ?? '');
  String? archivoPath;
  String? archivoNombre;
  String? errorFecha;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.antidopingEmpleadoDialogoTitulo,
    confirmLabel: l10n.antidopingEmpleadoBotonConfirmar,
    cancelLabel: l10n.antidopingEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        RisegSelect<ResultadoSustanciaAntidoping> selectorSustancia(
          String label,
          ResultadoSustanciaAntidoping valor,
          ValueChanged<ResultadoSustanciaAntidoping?> onChanged,
        ) {
          return RisegSelect<ResultadoSustanciaAntidoping>(
            label: label,
            value: valor,
            items: [
              for (final r in ResultadoSustanciaAntidoping.values)
                RisegSelectItem(value: r, label: resultadoSustanciaAntidopingLabel(l10n, r.name)),
            ],
            onChanged: onChanged,
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.evaluacionEmpleadoCampoFecha,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: selectorSustancia(
                    l10n.antidopingEmpleadoCampoAmp,
                    amp,
                    (valor) => setState(() => amp = valor ?? amp),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: selectorSustancia(
                    l10n.antidopingEmpleadoCampoBzd,
                    bzd,
                    (valor) => setState(() => bzd = valor ?? bzd),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: selectorSustancia(
                    l10n.antidopingEmpleadoCampoCoc,
                    coc,
                    (valor) => setState(() => coc = valor ?? coc),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: selectorSustancia(
                    l10n.antidopingEmpleadoCampoMet,
                    met,
                    (valor) => setState(() => met = valor ?? met),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            selectorSustancia(
              l10n.antidopingEmpleadoCampoOpi,
              opi,
              (valor) => setState(() => opi = valor ?? opi),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.evaluacionEmpleadoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    archivoNombre ?? l10n.evaluacionEmpleadoSinPdf,
                    style: AppTypography.body.copyWith(color: context.colors.textMuted),
                  ),
                ),
                RisegButton(
                  label: l10n.evaluacionEmpleadoBotonSeleccionarPdf,
                  variant: RisegButtonVariant.ghost,
                  onPressed: () async {
                    final seleccion = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                    );
                    final archivo = seleccion?.files.singleOrNull;
                    if (archivo?.path == null) return;
                    setState(() {
                      archivoPath = archivo!.path;
                      archivoNombre = archivo.name;
                    });
                  },
                ),
              ],
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      if (fecha == null) {
        errorFecha = l10n.evaluacionEmpleadoCampoFecha;
        return false;
      }

      final resultado = await ref.read(registrarAntidopingAutorizadoProvider)(
            empleadoId: empleado.id,
            fecha: fecha!,
            amp: amp,
            bzd: bzd,
            coc: coc,
            met: met,
            opi: opi,
            observaciones: observacionesController.text,
            sourceFilePath: archivoPath,
            originalFileName: archivoNombre,
            mimeType: archivoPath == null ? null : 'application/pdf',
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarAntidopingExitoso():
          RisegFeedback.showSuccess(context, l10n.antidopingEmpleadoExito);
          return true;
        case RegistrarAntidopingNoExiste():
        case RegistrarAntidopingErrorInesperado():
          RisegFeedback.showError(context, l10n.antidopingEmpleadoErrorInesperado);
          return false;
        case RegistrarAntidopingFechaInvalida():
          errorFecha = l10n.evaluacionEmpleadoErrorFechaInvalida;
          return false;
      }
    },
  );

  observacionesController.dispose();
  return resultado ?? false;
}
