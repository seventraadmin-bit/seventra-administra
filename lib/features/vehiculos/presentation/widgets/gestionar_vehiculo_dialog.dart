import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../vehiculos_controller.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo de alta/edición de un Vehículo (Etapa 8A). Si [vehiculo] es
/// `null`, da de alta; si no, corrige metadatos — mismo patrón que
/// `mostrarDialogoGestionarArticulo`. Devuelve `true` si la operación
/// tuvo éxito.
Future<bool> mostrarDialogoGestionarVehiculo(BuildContext context, WidgetRef ref, {VehiculoData? vehiculo}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(vehiculosControllerProvider.notifier);
  final esEdicion = vehiculo != null;

  final marcaCtrl = TextEditingController(text: vehiculo?.marca ?? '');
  final modeloCtrl = TextEditingController(text: vehiculo?.modelo ?? '');
  final anioCtrl = TextEditingController(text: vehiculo?.anio?.toString() ?? '');
  final colorCtrl = TextEditingController(text: vehiculo?.color ?? '');
  final placasCtrl = TextEditingController(text: vehiculo?.placas ?? '');
  final vinCtrl = TextEditingController(text: vehiculo?.vin ?? '');
  final numeroMotorCtrl = TextEditingController(text: vehiculo?.numeroMotor ?? '');
  final costoCtrl = TextEditingController(
    text: vehiculo?.costoAdquisicion == null ? '' : (vehiculo!.costoAdquisicion! / 100).toStringAsFixed(2),
  );
  final observacionesCtrl = TextEditingController(text: vehiculo?.observaciones ?? '');
  String tipoVehiculo = vehiculo?.tipoVehiculo ?? TipoVehiculo.sedan.name;
  DateTime? fechaAdquisicion = vehiculo?.fechaAdquisicion;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esEdicion ? l10n.vehiculoDialogoTituloEdicion : l10n.vehiculoDialogoTituloAlta,
    confirmLabel: l10n.vehiculoBotonGuardar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.vehiculoCampoMarca, controller: marcaCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoModelo, controller: modeloCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String>(
                label: l10n.vehiculoCampoTipoVehiculo,
                value: tipoVehiculo,
                items: [
                  for (final t in TipoVehiculo.values) RisegSelectItem(value: t.name, label: tipoVehiculoLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipoVehiculo = valor ?? tipoVehiculo),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoAnio, controller: anioCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoColor, controller: colorCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoPlacas, controller: placasCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoVin, controller: vinCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoNumeroMotor, controller: numeroMotorCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoCampoFechaAdquisicion,
                value: fechaAdquisicion,
                onChanged: (valor) => setState(() => fechaAdquisicion = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoCampoCostoAdquisicion,
                controller: costoCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoCampoObservaciones, controller: observacionesCtrl),
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
      if (marcaCtrl.text.trim().isEmpty) {
        errorGeneral = l10n.vehiculoErrorMarcaRequerida;
        return null;
      }
      if (modeloCtrl.text.trim().isEmpty) {
        errorGeneral = l10n.vehiculoErrorModeloRequerido;
        return null;
      }
      final anioTexto = anioCtrl.text.trim();
      final anio = anioTexto.isEmpty ? null : int.tryParse(anioTexto);
      if (anioTexto.isNotEmpty && anio == null) {
        errorGeneral = l10n.vehiculoErrorAnioInvalido;
        return null;
      }
      final costo = _centavosDesdeTexto(costoCtrl.text);
      if (costoCtrl.text.trim().isNotEmpty && costo == null) {
        errorGeneral = l10n.vehiculoErrorCostoInvalido;
        return null;
      }

      if (esEdicion) {
        final resultado = await notifier.corregirVehiculo(
          vehiculoId: vehiculo.id,
          marca: marcaCtrl.text.trim(),
          modelo: modeloCtrl.text.trim(),
          anio: anio,
          color: colorCtrl.text.trim().isEmpty ? null : colorCtrl.text.trim(),
          placas: placasCtrl.text.trim().isEmpty ? null : placasCtrl.text.trim(),
          vin: vinCtrl.text.trim().isEmpty ? null : vinCtrl.text.trim(),
          numeroMotor: numeroMotorCtrl.text.trim().isEmpty ? null : numeroMotorCtrl.text.trim(),
          tipoVehiculo: tipoVehiculo,
          fechaAdquisicion: fechaAdquisicion,
          costoAdquisicion: costo,
          observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
          limpiarAnio: anioTexto.isEmpty,
          limpiarColor: colorCtrl.text.trim().isEmpty,
          limpiarPlacas: placasCtrl.text.trim().isEmpty,
          limpiarVin: vinCtrl.text.trim().isEmpty,
          limpiarNumeroMotor: numeroMotorCtrl.text.trim().isEmpty,
          limpiarCostoAdquisicion: costoCtrl.text.trim().isEmpty,
          limpiarObservaciones: observacionesCtrl.text.trim().isEmpty,
        );
        if (!context.mounted) return false;
        switch (resultado) {
          case CorregirVehiculoExitoso():
            RisegFeedback.showSuccess(context, l10n.vehiculoGuardadoExito);
            return true;
          case CorregirVehiculoNoExiste():
          case CorregirVehiculoErrorInesperado():
            RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
            return false;
          case CorregirVehiculoAnioInvalido():
            errorGeneral = l10n.vehiculoErrorAnioInvalido;
            return null;
          case CorregirVehiculoCostoInvalido():
            errorGeneral = l10n.vehiculoErrorCostoInvalido;
            return null;
          case CorregirVehiculoPlacasDuplicadas():
            errorGeneral = l10n.vehiculoErrorPlacasDuplicadas;
            return null;
          case CorregirVehiculoVinDuplicado():
            errorGeneral = l10n.vehiculoErrorVinDuplicado;
            return null;
        }
      }

      final resultado = await notifier.crearVehiculo(
        marca: marcaCtrl.text.trim(),
        modelo: modeloCtrl.text.trim(),
        anio: anio,
        color: colorCtrl.text.trim().isEmpty ? null : colorCtrl.text.trim(),
        placas: placasCtrl.text.trim().isEmpty ? null : placasCtrl.text.trim(),
        vin: vinCtrl.text.trim().isEmpty ? null : vinCtrl.text.trim(),
        numeroMotor: numeroMotorCtrl.text.trim().isEmpty ? null : numeroMotorCtrl.text.trim(),
        tipoVehiculo: tipoVehiculo,
        fechaAdquisicion: fechaAdquisicion,
        costoAdquisicion: costo,
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CrearVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoGuardadoExito);
          return true;
        case CrearVehiculoMarcaRequerida():
          errorGeneral = l10n.vehiculoErrorMarcaRequerida;
          return null;
        case CrearVehiculoModeloRequerido():
          errorGeneral = l10n.vehiculoErrorModeloRequerido;
          return null;
        case CrearVehiculoAnioInvalido():
          errorGeneral = l10n.vehiculoErrorAnioInvalido;
          return null;
        case CrearVehiculoCostoInvalido():
          errorGeneral = l10n.vehiculoErrorCostoInvalido;
          return null;
        case CrearVehiculoPlacasDuplicadas():
          errorGeneral = l10n.vehiculoErrorPlacasDuplicadas;
          return null;
        case CrearVehiculoVinDuplicado():
          errorGeneral = l10n.vehiculoErrorVinDuplicado;
          return null;
        case CrearVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
          return false;
      }
    },
  );

  // Los controladores se liberan un frame después, no en cuanto
  // `showForm` resuelve — el diálogo todavía está animando su cierre
  // en ese instante, y algunos widgets internos de `TextFormField`
  // (el borde/label animados de `InputDecorator`) siguen reconstruyendo
  // sobre el árbol viejo durante esa transición; liberar de inmediato
  // dispara "TextEditingController usado después de dispose()".
  WidgetsBinding.instance.addPostFrameCallback((_) {
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    anioCtrl.dispose();
    colorCtrl.dispose();
    placasCtrl.dispose();
    vinCtrl.dispose();
    numeroMotorCtrl.dispose();
    costoCtrl.dispose();
    observacionesCtrl.dispose();
  });

  return resultado ?? false;
}
