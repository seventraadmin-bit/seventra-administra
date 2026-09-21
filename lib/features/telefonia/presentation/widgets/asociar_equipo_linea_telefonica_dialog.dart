import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'coherencia_linea_equipo_mensajes.dart';

/// Diálogo "Asociar equipo" (Etapa 9B) — liga un teléfono de Inventario
/// a una línea sin equipo. Sólo lista unidades que realmente son
/// teléfono (`ArticuloUnidadTelefono`), que pueden traer una SIM y que
/// no traen ya otra línea.
///
/// Si el aparato está bajo custodia de alguien y la línea no tiene
/// asignación, pide confirmación explícita para asignar la línea a ese
/// mismo destino (§7) — nunca en silencio, porque crea una asignación
/// de línea. Jamás toca la custodia en Inventario.
/// Devuelve `true` si tuvo éxito.
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
  DestinoTelefonia? custodiaAAlinear;
  bool alinearConfirmado = false;
  final nombres = await NombresDestinoTelefonia.cargar(ref);
  if (!context.mounted) return false;

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
              if (custodiaAAlinear != null) ...[
                const SizedBox(height: AppSpacing.xs),
                CheckboxListTile(
                  key: const Key('asociar_equipo_confirmar_alinear'),
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
      final resultado = await ref.read(asociarEquipoLineaTelefonicaAutorizadoProvider)(
            lineaTelefonicaId: lineaTelefonicaId,
            unidadId: unidadId!,
            fechaInicio: fechaInicio,
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            alinearLineaConCustodia: alinearConfirmado,
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
        case AsociarEquipoLineaTelefonicaUnidadYaTraeOtraLinea():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorUnidadYaTraeOtraLinea;
          return null;
        case AsociarEquipoLineaTelefonicaEquipoPendienteRecuperacion(:final custodia):
          errorGeneral = l10n.lineaTelefonicaCoherenciaPendienteRecuperacionAsociar(nombres.etiqueta(custodia, l10n));
          return null;
        case AsociarEquipoLineaTelefonicaYaTieneEquipo():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorYaTieneEquipo;
          return null;
        case AsociarEquipoLineaTelefonicaLineaDeBaja():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorLineaDeBaja;
          return null;
        case AsociarEquipoLineaTelefonicaRequiereAlinearLinea(:final custodia):
          // El aparato ya está en manos de alguien: la línea se alinea
          // con ESA custodia, previa confirmación. Inventario no se toca.
          custodiaAAlinear = custodia;
          errorGeneral = null;
          return null;
        case AsociarEquipoLineaTelefonicaEquipoSinCustodia(:final destinoLinea):
          errorGeneral = l10n.lineaTelefonicaCoherenciaEquipoSinCustodia(nombres.etiqueta(destinoLinea, l10n));
          return null;
        case AsociarEquipoLineaTelefonicaDestinosDistintos(:final destinoLinea, :final custodia):
          errorGeneral = l10n.lineaTelefonicaCoherenciaDestinosDistintos(
            nombres.etiqueta(destinoLinea, l10n),
            nombres.etiqueta(custodia, l10n),
          );
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
