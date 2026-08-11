import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Asociar equipo" (Etapa 9B) — liga un teléfono de Inventario
/// (disponible) a una línea sin equipo. Solo lista unidades que
/// realmente son teléfono (`ArticuloUnidadTelefono`) y están
/// `disponible` — punto 4 de Marlon. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoAsociarEquipoLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;
  final equipos = await ref.read(obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider).ejecutar();
  if (!context.mounted) return false;

  String? unidadId;
  DateTime fechaInicio = DateTime.now();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaAsociarEquipoDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaAsociarEquipoBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String?>(
                label: l10n.lineaTelefonicaEquipoCampoUnidad,
                value: unidadId,
                items: [
                  for (final e in equipos) RisegSelectItem(value: e.unidadId, label: '${e.codigo} · ${e.descripcion}'),
                ],
                onChanged: (valor) => setState(() => unidadId = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaEquipoCampoFecha,
                value: fechaInicio,
                onChanged: (valor) => setState(() => fechaInicio = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaEquipoCampoObservaciones, controller: observacionesCtrl),
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
      if (unidadId == null) {
        errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadRequerida;
        return null;
      }

      final resultado = await ref.read(asociarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            unidadId: unidadId!,
            fechaInicio: fechaInicio,
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
          );
      if (!context.mounted) return false;
      switch (resultado) {
        case AsociarEquipoLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaAsociarEquipoExito);
          return true;
        case AsociarEquipoLineaTelefonicaUnidadNoEsTelefono():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadNoEsTelefono;
          return null;
        case AsociarEquipoLineaTelefonicaUnidadNoDisponible():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadNoDisponible;
          return null;
        case AsociarEquipoLineaTelefonicaYaTieneEquipo():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorYaTieneEquipo;
          return null;
        case AsociarEquipoLineaTelefonicaLineaDeBaja():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorLineaDeBaja;
          return null;
        case AsociarEquipoLineaTelefonicaLineaNoExiste():
        case AsociarEquipoLineaTelefonicaUnidadNoExiste():
        case AsociarEquipoLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
