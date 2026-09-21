import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_perfil_psicologico_usecase.dart';

import '../../../personal_providers.dart';

/// Diálogo combinado "Perfil psicológico" (Etapa 5B) — captura
/// fecha/resumen/observaciones y, opcionalmente, el PDF en el mismo
/// paso (Resolución explícita de Marlon: nunca separar en dos
/// navegaciones). Sin PDF, se guarda igual.
///
/// Devuelve `true` si se guardó correctamente.
Future<bool> mostrarDialogoPerfilPsicologicoEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime? fecha = empleado.fechaEvaluacionPsicologica;
  final resumenController = TextEditingController(text: empleado.resumenPsicologico ?? '');
  final observacionesController = TextEditingController(text: empleado.observacionesPsicologico ?? '');
  String? archivoPath;
  String? archivoNombre;
  String? errorFecha;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.perfilPsicologicoEmpleadoDialogoTitulo,
    confirmLabel: l10n.perfilPsicologicoEmpleadoBotonConfirmar,
    cancelLabel: l10n.perfilPsicologicoEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
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
            RisegTextField(label: l10n.perfilPsicologicoEmpleadoCampoResumen, controller: resumenController, autofocus: true),
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

      final resultado = await ref.read(registrarPerfilPsicologicoAutorizadoProvider)(
            empleadoId: empleado.id,
            fecha: fecha!,
            resumen: resumenController.text,
            observaciones: observacionesController.text,
            sourceFilePath: archivoPath,
            originalFileName: archivoNombre,
            mimeType: archivoPath == null ? null : 'application/pdf',
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarPerfilPsicologicoExitoso():
          RisegFeedback.showSuccess(context, l10n.perfilPsicologicoEmpleadoExito);
          return true;
        case RegistrarPerfilPsicologicoNoExiste():
        case RegistrarPerfilPsicologicoErrorInesperado():
          RisegFeedback.showError(context, l10n.perfilPsicologicoEmpleadoErrorInesperado);
          return false;
        case RegistrarPerfilPsicologicoFechaInvalida():
          errorFecha = l10n.evaluacionEmpleadoErrorFechaInvalida;
          return false;
      }
    },
  );

  resumenController.dispose();
  observacionesController.dispose();
  return resultado ?? false;
}
