import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/adjuntar_comprobante_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../../vehiculos_providers.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo "Registrar mantenimiento o incidencia" (Etapa 8D) — un solo
/// formulario para ambos conceptos (ver el doc comment de
/// `VehiculoMantenimiento`); el selector `tipo` ya distingue cuál es
/// cuál. El comprobante es opcional y se adjunta después de crear el
/// registro (mismo patrón ya usado para documentos 8C/fotografía 8A).
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRegistrarMantenimientoVehiculo(BuildContext context, WidgetRef ref, String vehiculoId) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime fecha = DateTime.now();
  final kilometrajeCtrl = TextEditingController();
  TipoMantenimientoVehiculo tipo = TipoMantenimientoVehiculo.preventivo;
  final descripcionCtrl = TextEditingController();
  final tallerCtrl = TextEditingController();
  final costoCtrl = TextEditingController();
  DateTime? proximoFecha;
  final proximoKilometrajeCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  String? archivoPath;
  String? archivoNombre;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoMantenimientoDialogoTitulo,
    confirmLabel: l10n.vehiculoMantenimientoBotonGuardar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.vehiculoMantenimientoCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoMantenimientoCampoKilometraje,
                controller: kilometrajeCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<TipoMantenimientoVehiculo>(
                label: l10n.vehiculoMantenimientoCampoTipo,
                value: tipo,
                items: [
                  for (final t in TipoMantenimientoVehiculo.values)
                    RisegSelectItem(value: t, label: tipoMantenimientoVehiculoLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipo = valor ?? tipo),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoMantenimientoCampoDescripcion, controller: descripcionCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoMantenimientoCampoTallerProveedor, controller: tallerCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoMantenimientoCampoCosto,
                controller: costoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoMantenimientoCampoProximoFecha,
                value: proximoFecha,
                onChanged: (valor) => setState(() => proximoFecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoMantenimientoCampoProximoKilometraje,
                controller: proximoKilometrajeCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoMantenimientoCampoObservaciones, controller: observacionesCtrl),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.vehiculoMantenimientoCampoComprobante, style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              if (archivoPath == null)
                RisegButton(
                  label: l10n.vehiculoMantenimientoBotonSeleccionarComprobante,
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
      final kilometraje = kilometrajeCtrl.text.trim().isEmpty ? null : int.tryParse(kilometrajeCtrl.text.trim());
      final proximoKilometraje =
          proximoKilometrajeCtrl.text.trim().isEmpty ? null : int.tryParse(proximoKilometrajeCtrl.text.trim());
      final costo = _centavosDesdeTexto(costoCtrl.text);

      final registrado = await ref.read(registrarMantenimientoVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            fecha: fecha,
            kilometraje: kilometraje,
            tipo: tipo.name,
            descripcion: descripcionCtrl.text,
            tallerProveedor: tallerCtrl.text,
            costo: costo,
            proximoMantenimientoFecha: proximoFecha,
            proximoMantenimientoKilometraje: proximoKilometraje,
            observaciones: observacionesCtrl.text,
          );
      if (!context.mounted) return false;

      switch (registrado) {
        case RegistrarMantenimientoVehiculoDescripcionRequerida():
          errorGeneral = l10n.vehiculoMantenimientoErrorDescripcionRequerida;
          return null;
        case RegistrarMantenimientoVehiculoProximoInvalido():
          errorGeneral = l10n.vehiculoMantenimientoErrorProximoInvalido;
          return null;
        case RegistrarMantenimientoVehiculoKilometrajeMenorAlActual(:final actual):
          errorGeneral = l10n.vehiculoMantenimientoErrorKilometrajeMenorAlActual(actual);
          return null;
        case RegistrarMantenimientoVehiculoVehiculoNoExiste():
        case RegistrarMantenimientoVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoMantenimientoErrorInesperado);
          return false;
        case RegistrarMantenimientoVehiculoExitoso(:final registro):
          if (archivoPath != null) {
            final adjuntado = await ref.read(adjuntarComprobanteMantenimientoVehiculoUseCaseProvider).ejecutar(
                  vehiculoMantenimientoId: registro.id,
                  sourceFilePath: archivoPath!,
                  originalFileName: archivoNombre!,
                  mimeType: 'application/octet-stream',
                );
            if (!context.mounted) return false;
            if (adjuntado is! AdjuntarComprobanteMantenimientoVehiculoExitoso) {
              RisegFeedback.showError(context, l10n.vehiculoMantenimientoErrorInesperado);
              return true;
            }
          }
          RisegFeedback.showSuccess(context, l10n.vehiculoMantenimientoGuardadoExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    kilometrajeCtrl.dispose();
    descripcionCtrl.dispose();
    tallerCtrl.dispose();
    costoCtrl.dispose();
    proximoKilometrajeCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
