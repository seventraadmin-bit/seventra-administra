import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../domain/usecases/regularizar_perfil_asignacion_usecase.dart';
import '../../../personal_providers.dart';
import 'sueldo_acordado_fields.dart' show etiquetaLineaComercial;

/// Diálogo "Regularizar perfil de asignación" (Etapa 15, corrección del
/// bug real de atribución histórica) — Maestro-only. Completa el
/// `lineaComercialId` de una asignación vigente que quedó `NULL` (dato
/// previo a Etapa 15): NUNCA crea una asignación nueva, ni toca fecha
/// de inicio/sueldo/bono/historial — solo la clasificación por línea
/// comercial que faltaba. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRegularizarPerfilAsignacion(
  BuildContext context,
  WidgetRef ref,
  AsignacionServicioData asignacion,
) async {
  final l10n = AppLocalizations.of(context)!;
  final regularizar = ref.read(regularizarPerfilAsignacionAutorizadoProvider);

  final lineas = (await ref.read(servicioComercialRepositoryProvider).listarLineas(asignacion.servicioId))
      .where((l) => l.vigenciaActual != null)
      .toList();
  if (!context.mounted) return false;

  if (lineas.isEmpty) {
    RisegFeedback.showError(context, l10n.regularizarPerfilAsignacionSinLineasDisponibles);
    return false;
  }

  String? lineaComercialId = lineas.length == 1 ? lineas.single.linea.id : null;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.regularizarPerfilAsignacionDialogoTitulo,
    confirmLabel: l10n.regularizarPerfilAsignacionBotonConfirmar,
    cancelLabel: l10n.regularizarPerfilAsignacionBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.regularizarPerfilAsignacionDialogoExplicacion,
                style: AppTypography.body.copyWith(color: context.colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.regularizarPerfilAsignacionCampoLinea,
                value: lineaComercialId,
                errorText: errorGeneral,
                items: [
                  for (final l in lineas) RisegSelectItem(value: l.linea.id, label: etiquetaLineaComercial(l10n, l)),
                ],
                onChanged: (valor) => setState(() {
                  lineaComercialId = valor;
                  errorGeneral = null;
                }),
              ),
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final elegida = lineaComercialId;
      if (elegida == null) {
        errorGeneral = l10n.regularizarPerfilAsignacionErrorLineaRequerida;
        return null;
      }

      final resultado = await regularizar(asignacionServicioId: asignacion.id, lineaComercialId: elegida);
      if (!context.mounted) return null;
      switch (resultado) {
        case RegularizarPerfilAsignacionExitoso():
          RisegFeedback.showSuccess(context, l10n.regularizarPerfilAsignacionExito);
          return true;
        case RegularizarPerfilAsignacionLineaInvalida():
          errorGeneral = l10n.regularizarPerfilAsignacionErrorLineaInvalida;
          return null;
        case RegularizarPerfilAsignacionNoExiste():
        case RegularizarPerfilAsignacionNoVigente():
        case RegularizarPerfilAsignacionYaTienePerfil():
        case RegularizarPerfilAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.regularizarPerfilAsignacionErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}
