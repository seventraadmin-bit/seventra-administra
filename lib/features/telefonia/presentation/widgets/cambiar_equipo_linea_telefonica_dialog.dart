import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_equipo_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'coherencia_linea_equipo_mensajes.dart';

/// Diálogo "Cambiar equipo" (Etapa 9B) — sustituye el teléfono asociado
/// a una línea sin crear una línea nueva (punto 9 del pedido original
/// de Telefonía). Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCambiarEquipoLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;
  final equipos = await ref.read(obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider).ejecutar();
  if (!context.mounted) return false;

  String? unidadId;
  DateTime fecha = DateTime.now();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;
  DestinoTelefonia? custodiaAAlinear;
  bool alinearConfirmado = false;
  final nombres = await NombresDestinoTelefonia.cargar(ref);
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaCambiarEquipoDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaCambiarEquipoBotonConfirmar,
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
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaEquipoCampoObservaciones, controller: observacionesCtrl),
              if (custodiaAAlinear != null) ...[
                const SizedBox(height: AppSpacing.xs),
                CheckboxListTile(
                  key: const Key('cambiar_equipo_confirmar_alinear'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    l10n.lineaTelefonicaCoherenciaAlinearConfirmacion(nombres.etiqueta(custodiaAAlinear, l10n)),
                  ),
                  value: alinearConfirmado,
                  onChanged: (valor) => setState(() => alinearConfirmado = valor ?? alinearConfirmado),
                ),
              ],
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
      final resultado = await ref.read(cambiarEquipoLineaTelefonicaAutorizadoProvider)(
            lineaTelefonicaId: lineaTelefonicaId,
            nuevaUnidadId: unidadId!,
            fecha: fecha,
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            alinearLineaConCustodia: alinearConfirmado,
          );
      if (!context.mounted) return false;
      switch (resultado) {
        case CambiarEquipoLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaCambiarEquipoExito);
          return true;
        case CambiarEquipoLineaTelefonicaUnidadNoEsTelefono():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadNoEsTelefono;
          return null;
        case CambiarEquipoLineaTelefonicaUnidadNoDisponible():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadNoDisponible;
          return null;
        case CambiarEquipoLineaTelefonicaUnidadYaTraeOtraLinea():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadYaTraeOtraLinea;
          return null;
        case CambiarEquipoLineaTelefonicaEquipoPendienteRecuperacion(:final custodia):
          errorGeneral = l10n.lineaTelefonicaCoherenciaPendienteRecuperacionAsociar(nombres.etiqueta(custodia, l10n));
          return null;
        case CambiarEquipoLineaTelefonicaSinEquipoVigente():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorSinEquipoVigente;
          return null;
        case CambiarEquipoLineaTelefonicaLineaDeBaja():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorLineaDeBaja;
          return null;
        case CambiarEquipoLineaTelefonicaRequiereAlinearLinea(:final custodia):
          custodiaAAlinear = custodia;
          errorGeneral = null;
          return null;
        case CambiarEquipoLineaTelefonicaEquipoSinCustodia(:final destinoLinea):
          errorGeneral = l10n.lineaTelefonicaCoherenciaEquipoSinCustodia(nombres.etiqueta(destinoLinea, l10n));
          return null;
        case CambiarEquipoLineaTelefonicaDestinosDistintos(:final destinoLinea, :final custodia):
          errorGeneral = l10n.lineaTelefonicaCoherenciaDestinosDistintos(
            nombres.etiqueta(destinoLinea, l10n),
            nombres.etiqueta(custodia, l10n),
          );
          return null;
        case CambiarEquipoLineaTelefonicaLineaNoExiste():
        case CambiarEquipoLineaTelefonicaUnidadNoExiste():
        case CambiarEquipoLineaTelefonicaErrorInesperado():
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
