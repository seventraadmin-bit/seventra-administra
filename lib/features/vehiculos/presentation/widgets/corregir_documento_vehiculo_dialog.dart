import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_documento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_documento_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../../vehiculos_providers.dart';

/// Diálogo "Corregir documento" (schemaVersion 80).
///
/// Deliberadamente separado de "Renovar": renovar registra una vigencia
/// nueva porque el documento cambió en la realidad; corregir arregla lo
/// que se capturó mal sobre la MISMA fila. Antes de esta etapa solo
/// existía lo primero, así que un folio con un dígito de más obligaba a
/// inventar una renovación falsa que además ensuciaba las alertas de
/// vencimiento.
///
/// El `tipo` no se puede cambiar aquí: cambiarlo movería el documento a
/// otro grupo del expediente y reescribiría qué vigencia está vigente en
/// dos tipos a la vez. Si se capturó el tipo equivocado, lo correcto es
/// registrar el documento en su tipo real — no mutar este.
///
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCorregirDocumentoVehiculo(
  BuildContext context,
  WidgetRef ref,
  VehiculoDocumentoData documento,
) async {
  final l10n = AppLocalizations.of(context)!;

  final esOtro = documento.tipo == TipoDocumentoVehiculo.otro.name;
  final descripcionOtroCtrl = TextEditingController(text: documento.tipoOtroDescripcion ?? '');
  final folioCtrl = TextEditingController(text: documento.numeroFolio ?? '');
  DateTime? fechaEmision = documento.fechaEmision;
  DateTime? fechaVencimiento = documento.fechaVencimiento;
  final observacionesCtrl = TextEditingController(text: documento.observaciones ?? '');
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoDocumentoDialogoTituloCorregir,
    confirmLabel: l10n.vehiculoDocumentoBotonGuardarDocumento,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: l10n.vehiculoDocumentoCampoTipo,
                value: documento.tipo,
                enabled: false,
                items: [
                  RisegSelectItem(
                    value: documento.tipo,
                    label: tipoDocumentoVehiculoCatalogoLabel(l10n, documento.tipo),
                  ),
                ],
                onChanged: (_) {},
              ),
              if (esOtro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  label: l10n.vehiculoDocumentoCampoDescripcionOtro,
                  controller: descripcionOtroCtrl,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('vehiculo_documento_corregir_folio'),
                label: l10n.vehiculoDocumentoCampoFolio,
                controller: folioCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoDocumentoCampoFechaEmision,
                value: fechaEmision,
                onChanged: (valor) => setState(() => fechaEmision = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoDocumentoCampoFechaVencimiento,
                value: fechaVencimiento,
                onChanged: (valor) => setState(() => fechaVencimiento = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoDocumentoCampoObservaciones, controller: observacionesCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('vehiculo_documento_corregir_motivo'),
                label: l10n.vehiculoDocumentoCampoMotivoCorreccion,
                controller: motivoCtrl,
                autofocus: true,
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errorGeneral!,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final folio = folioCtrl.text.trim();
      final observaciones = observacionesCtrl.text.trim();

      final corregido = await ref.read(corregirDocumentoVehiculoAutorizadoProvider)(
            vehiculoDocumentoId: documento.id,
            tipoOtroDescripcion: esOtro ? descripcionOtroCtrl.text : null,
            numeroFolio: folio.isEmpty ? null : folio,
            // Vaciar el campo significa "este documento no tiene folio",
            // que es distinto de "no lo toques".
            limpiarNumeroFolio: folio.isEmpty,
            fechaEmision: fechaEmision,
            limpiarFechaEmision: fechaEmision == null,
            fechaVencimiento: fechaVencimiento,
            limpiarFechaVencimiento: fechaVencimiento == null,
            observaciones: observaciones.isEmpty ? null : observaciones,
            limpiarObservaciones: observaciones.isEmpty,
            motivo: motivoCtrl.text,
          );
      if (!context.mounted) return false;

      switch (corregido) {
        case CorregirDocumentoVehiculoMotivoRequerido():
          errorGeneral = l10n.vehiculoDocumentoErrorMotivoRequerido;
          return null;
        case CorregirDocumentoVehiculoDescripcionRequerida():
          errorGeneral = l10n.vehiculoDocumentoErrorDescripcionRequerida;
          return null;
        case CorregirDocumentoVehiculoFechasInvalidas():
          errorGeneral = l10n.vehiculoDocumentoErrorFechasInvalidas;
          return null;
        case CorregirDocumentoVehiculoNoExiste():
        case CorregirDocumentoVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoDocumentoErrorInesperado);
          return false;
        case CorregirDocumentoVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoDocumentoCorregidoExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    descripcionOtroCtrl.dispose();
    folioCtrl.dispose();
    observacionesCtrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
