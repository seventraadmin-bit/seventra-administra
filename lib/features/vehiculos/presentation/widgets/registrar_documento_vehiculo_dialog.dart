import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_documento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/adjuntar_archivo_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_documento_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../../vehiculos_providers.dart';

/// Diálogo "Agregar documento" / "Renovar documento" (Etapa 8C) — el
/// mismo formulario sirve para ambos casos (renovar es exactamente
/// registrar de nuevo con el mismo `tipo`, ver el doc comment de
/// `RegistrarDocumentoVehiculoUseCase`); [tipoPreseleccionado] solo
/// precarga el selector cuando se invoca como "renovar". El archivo es
/// opcional — se selecciona aquí y se adjunta después de crear el
/// documento (mismo patrón ya usado para fotografía/documentos de
/// Empleado). Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRegistrarDocumentoVehiculo(
  BuildContext context,
  WidgetRef ref,
  String vehiculoId, {
  TipoDocumentoVehiculo? tipoPreseleccionado,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final esRenovacion = tipoPreseleccionado != null;

  TipoDocumentoVehiculo tipo = tipoPreseleccionado ?? TipoDocumentoVehiculo.tarjetaCirculacion;
  final descripcionOtroCtrl = TextEditingController();
  final folioCtrl = TextEditingController();
  DateTime? fechaEmision;
  DateTime? fechaVencimiento;
  final observacionesCtrl = TextEditingController();
  String? archivoPath;
  String? archivoNombre;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esRenovacion ? l10n.vehiculoDocumentoDialogoTituloRenovar : l10n.vehiculoDocumentoDialogoTituloNuevo,
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
              RisegSelect<TipoDocumentoVehiculo>(
                label: l10n.vehiculoDocumentoCampoTipo,
                value: tipo,
                enabled: !esRenovacion,
                items: [
                  for (final t in TipoDocumentoVehiculo.values)
                    RisegSelectItem(value: t, label: tipoDocumentoVehiculoCatalogoLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipo = valor ?? tipo),
              ),
              if (tipo == TipoDocumentoVehiculo.otro) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.vehiculoDocumentoCampoDescripcionOtro, controller: descripcionOtroCtrl),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoDocumentoCampoFolio, controller: folioCtrl),
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
              Text(l10n.vehiculoDocumentoCampoArchivo, style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              if (archivoPath == null)
                RisegButton(
                  label: l10n.vehiculoDocumentoBotonSeleccionarArchivo,
                  variant: RisegButtonVariant.secondary,
                  icon: Icons.attach_file,
                  onPressed: () async {
                    final seleccion = await FilePicker.platform.pickFiles();
                    final archivo = seleccion?.files.singleOrNull;
                    if (archivo?.path == null) return;
                    setState(() {
                      archivoPath = archivo!.path;
                      archivoNombre = archivo.name;
                    });
                  },
                )
              else
                Row(
                  children: [
                    Expanded(child: Text(archivoNombre ?? '', overflow: TextOverflow.ellipsis)),
                    RisegButton(
                      label: l10n.crearEmpleadoBotonQuitar,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () => setState(() {
                        archivoPath = null;
                        archivoNombre = null;
                      }),
                    ),
                  ],
                ),
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
      final registrado = await ref.read(registrarDocumentoVehiculoAutorizadoProvider)(
            vehiculoId: vehiculoId,
            tipo: tipo.name,
            tipoOtroDescripcion: descripcionOtroCtrl.text,
            numeroFolio: folioCtrl.text.trim().isEmpty ? null : folioCtrl.text.trim(),
            fechaEmision: fechaEmision,
            fechaVencimiento: fechaVencimiento,
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
          );
      if (!context.mounted) return false;

      switch (registrado) {
        case RegistrarDocumentoVehiculoDescripcionRequerida():
          errorGeneral = l10n.vehiculoDocumentoErrorDescripcionRequerida;
          return null;
        case RegistrarDocumentoVehiculoFechasInvalidas():
          errorGeneral = l10n.vehiculoDocumentoErrorFechasInvalidas;
          return null;
        case RegistrarDocumentoVehiculoVehiculoNoExiste():
        case RegistrarDocumentoVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoDocumentoErrorInesperado);
          return false;
        case RegistrarDocumentoVehiculoExitoso(:final documento):
          if (archivoPath != null) {
            final adjuntado = await ref.read(adjuntarArchivoDocumentoVehiculoUseCaseProvider).ejecutar(
                  vehiculoDocumentoId: documento.id,
                  sourceFilePath: archivoPath!,
                  originalFileName: archivoNombre!,
                  mimeType: 'application/octet-stream',
                );
            if (!context.mounted) return false;
            if (adjuntado is! AdjuntarArchivoDocumentoVehiculoExitoso) {
              RisegFeedback.showError(context, l10n.vehiculoDocumentoErrorInesperado);
              return true;
            }
          }
          RisegFeedback.showSuccess(context, l10n.vehiculoDocumentoGuardadoExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    descripcionOtroCtrl.dispose();
    folioCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
