import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';

import '../articulos_controller.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo "Registrar entrada" (Etapa 7A) — se adapta según
/// `articulo.manejaSerie`: por cantidad (con talla/variante si
/// aplica) o unidad serializada (con IMEI/número telefónico solo si
/// la categoría es teléfono — la UI los muestra siempre que
/// `manejaSerie` sea `true` y el usuario decide si los llena).
Future<bool> mostrarDialogoRegistrarEntrada(
  BuildContext context,
  WidgetRef ref, {
  required ArticuloData articulo,
  required List<ArticuloVarianteData> variantes,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(articulosControllerProvider.notifier);

  String? varianteId = variantes.length == 1 ? variantes.single.id : null;
  final cantidadCtrl = TextEditingController(text: '1');
  final numeroSerieCtrl = TextEditingController();
  final marcaCtrl = TextEditingController();
  final modeloCtrl = TextEditingController();
  final imeiCtrl = TextEditingController();
  final numeroTelefonicoCtrl = TextEditingController();
  final costoCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  DateTime? fecha = DateTime.now();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarEntradaDialogoTitulo,
    confirmLabel: l10n.registrarEntradaBotonConfirmar,
    cancelLabel: l10n.registrarEntradaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (articulo.manejaSerie) ...[
                RisegTextField(label: l10n.registrarEntradaCampoNumeroSerie, controller: numeroSerieCtrl, autofocus: true),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: RisegTextField(label: l10n.registrarEntradaCampoMarca, controller: marcaCtrl)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: RisegTextField(label: l10n.registrarEntradaCampoModelo, controller: modeloCtrl)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: RisegTextField(label: l10n.registrarEntradaCampoImei, controller: imeiCtrl)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: RisegTextField(label: l10n.registrarEntradaCampoNumeroTelefonico, controller: numeroTelefonicoCtrl),
                    ),
                  ],
                ),
              ] else ...[
                if (articulo.manejaVariante) ...[
                  RisegSelect<String?>(
                    label: l10n.registrarEntradaCampoVariante,
                    value: varianteId,
                    items: [for (final v in variantes) RisegSelectItem(value: v.id, label: v.valor)],
                    onChanged: (valor) => setState(() => varianteId = valor),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                RisegTextField(
                  label: l10n.registrarEntradaCampoCantidad,
                  controller: cantidadCtrl,
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarEntradaCampoCostoUnitario, controller: costoCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.registrarEntradaCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarEntradaCampoObservaciones, controller: observacionesCtrl),
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
      final costo = _centavosDesdeTexto(costoCtrl.text);
      if (costoCtrl.text.trim().isNotEmpty && costo == null) {
        errorGeneral = l10n.registrarEntradaErrorCostoInvalido;
        return null;
      }
      final observaciones = observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim();

      if (articulo.manejaSerie) {
        if (numeroSerieCtrl.text.trim().isEmpty) {
          errorGeneral = l10n.registrarEntradaErrorNumeroSerieRequerido;
          return null;
        }
        final resultado = await notifier.registrarEntradaUnidad(
          articuloId: articulo.id,
          numeroSerie: numeroSerieCtrl.text.trim(),
          marca: marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
          modelo: modeloCtrl.text.trim().isEmpty ? null : modeloCtrl.text.trim(),
          imei: imeiCtrl.text.trim().isEmpty ? null : imeiCtrl.text.trim(),
          numeroTelefonico: numeroTelefonicoCtrl.text.trim().isEmpty ? null : numeroTelefonicoCtrl.text.trim(),
          costoUnitario: costo,
          fecha: fecha ?? DateTime.now(),
          observaciones: observaciones,
        );
        if (!context.mounted) return false;
        switch (resultado) {
          case RegistrarEntradaUnidadExitoso():
            RisegFeedback.showSuccess(context, l10n.registrarEntradaExito);
            return true;
          case RegistrarEntradaUnidadNumeroSerieRequerido():
            errorGeneral = l10n.registrarEntradaErrorNumeroSerieRequerido;
            return null;
          case RegistrarEntradaUnidadCostoInvalido():
            errorGeneral = l10n.registrarEntradaErrorCostoInvalido;
            return null;
          case RegistrarEntradaUnidadArticuloNoExiste():
          case RegistrarEntradaUnidadArticuloNoManejaSerie():
          case RegistrarEntradaUnidadErrorInesperado():
            RisegFeedback.showError(context, l10n.registrarEntradaErrorInesperado);
            return false;
        }
      }

      if (articulo.manejaVariante && varianteId == null) {
        errorGeneral = l10n.registrarEntradaErrorVarianteInvalida;
        return null;
      }
      final cantidad = int.tryParse(cantidadCtrl.text.trim());
      if (cantidad == null || cantidad <= 0) {
        errorGeneral = l10n.registrarEntradaErrorCantidadInvalida;
        return null;
      }

      final resultado = await notifier.registrarEntrada(
        articuloId: articulo.id,
        varianteId: varianteId,
        cantidad: cantidad,
        costoUnitario: costo,
        fecha: fecha ?? DateTime.now(),
        observaciones: observaciones,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarEntradaExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarEntradaExito);
          return true;
        case RegistrarEntradaVarianteInvalida():
          errorGeneral = l10n.registrarEntradaErrorVarianteInvalida;
          return null;
        case RegistrarEntradaCantidadInvalida():
          errorGeneral = l10n.registrarEntradaErrorCantidadInvalida;
          return null;
        case RegistrarEntradaCostoInvalido():
          errorGeneral = l10n.registrarEntradaErrorCostoInvalido;
          return null;
        case RegistrarEntradaArticuloNoExiste():
        case RegistrarEntradaArticuloManejaSerie():
        case RegistrarEntradaErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarEntradaErrorInesperado);
          return false;
      }
    },
  );

  cantidadCtrl.dispose();
  numeroSerieCtrl.dispose();
  marcaCtrl.dispose();
  modeloCtrl.dispose();
  imeiCtrl.dispose();
  numeroTelefonicoCtrl.dispose();
  costoCtrl.dispose();
  observacionesCtrl.dispose();

  return resultado ?? false;
}
