import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';

import '../articulos_controller.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo de alta/edición de un Artículo (Etapa 7A). Si [articulo] es
/// `null`, da de alta; si no, corrige metadatos — `manejaVariante`/
/// `manejaSerie` solo se capturan al crear, nunca se editan después
/// (ver el doc comment de `CrearArticuloUseCase`).
///
/// Devuelve `true` si la operación tuvo éxito.
Future<bool> mostrarDialogoGestionarArticulo(BuildContext context, WidgetRef ref, {ArticuloData? articulo}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(articulosControllerProvider.notifier);
  final esEdicion = articulo != null;

  final nombreCtrl = TextEditingController(text: articulo?.nombre ?? '');
  final descripcionCtrl = TextEditingController(text: articulo?.descripcion ?? '');
  final unidadMedidaCtrl = TextEditingController(text: articulo?.unidadMedida ?? '');
  final costoCtrl = TextEditingController(
    text: articulo?.costoReferencia == null ? '' : (articulo!.costoReferencia! / 100).toStringAsFixed(2),
  );
  String? categoriaId = articulo?.categoriaId;
  bool manejaVariante = articulo?.manejaVariante ?? false;
  bool manejaSerie = articulo?.manejaSerie ?? false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esEdicion ? l10n.gestionarArticuloDialogoTituloEdicion : l10n.gestionarArticuloDialogoTituloAlta,
    confirmLabel: l10n.gestionarArticuloBotonGuardar,
    cancelLabel: l10n.gestionarArticuloBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final categorias = ref.watch(articulosControllerProvider).categorias;
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.articuloCampoNombre, controller: nombreCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.articuloCampoCategoria,
                value: categoriaId,
                items: [for (final c in categorias) RisegSelectItem(value: c.id, label: c.nombre)],
                onChanged: (valor) => setState(() => categoriaId = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.articuloCampoDescripcion, controller: descripcionCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.articuloCampoUnidadMedida, controller: unidadMedidaCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.articuloCampoCostoReferencia, controller: costoCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.md),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: manejaVariante,
                onChanged: esEdicion ? null : (valor) => setState(() => manejaVariante = valor ?? false),
                title: Text(l10n.articuloCampoManejaVariante),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: manejaSerie,
                onChanged: esEdicion ? null : (valor) => setState(() => manejaSerie = valor ?? false),
                title: Text(l10n.articuloCampoManejaSerie),
              ),
              if (esEdicion) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.articuloAvisoBanderasFijas, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
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
      if (nombreCtrl.text.trim().isEmpty) {
        errorGeneral = l10n.articuloErrorNombreRequerido;
        return null;
      }
      if (categoriaId == null) {
        errorGeneral = l10n.articuloErrorCategoriaNoExiste;
        return null;
      }
      final costo = _centavosDesdeTexto(costoCtrl.text);
      if (costoCtrl.text.trim().isNotEmpty && costo == null) {
        errorGeneral = l10n.articuloErrorCostoInvalido;
        return null;
      }

      if (esEdicion) {
        final resultado = await notifier.corregirArticulo(
          articuloId: articulo.id,
          categoriaId: categoriaId,
          nombre: nombreCtrl.text.trim(),
          descripcion: descripcionCtrl.text.trim().isEmpty ? null : descripcionCtrl.text.trim(),
          unidadMedida: unidadMedidaCtrl.text.trim().isEmpty ? null : unidadMedidaCtrl.text.trim(),
          costoReferencia: costo,
          limpiarDescripcion: descripcionCtrl.text.trim().isEmpty,
          limpiarCostoReferencia: costoCtrl.text.trim().isEmpty,
        );
        if (!context.mounted) return false;
        switch (resultado) {
          case CorregirArticuloExitoso():
            RisegFeedback.showSuccess(context, l10n.articuloGuardadoExito);
            return true;
          case CorregirArticuloNoExiste():
          case CorregirArticuloErrorInesperado():
            RisegFeedback.showError(context, l10n.articuloErrorInesperado);
            return false;
          case CorregirArticuloCategoriaNoExiste():
            errorGeneral = l10n.articuloErrorCategoriaNoExiste;
            return null;
          case CorregirArticuloCostoInvalido():
            errorGeneral = l10n.articuloErrorCostoInvalido;
            return null;
        }
      }

      final resultado = await notifier.crearArticulo(
        categoriaId: categoriaId!,
        nombre: nombreCtrl.text.trim(),
        descripcion: descripcionCtrl.text.trim().isEmpty ? null : descripcionCtrl.text.trim(),
        unidadMedida: unidadMedidaCtrl.text.trim().isEmpty ? null : unidadMedidaCtrl.text.trim(),
        manejaVariante: manejaVariante,
        manejaSerie: manejaSerie,
        costoReferencia: costo,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CrearArticuloExitoso():
          RisegFeedback.showSuccess(context, l10n.articuloGuardadoExito);
          return true;
        case CrearArticuloNombreRequerido():
          errorGeneral = l10n.articuloErrorNombreRequerido;
          return null;
        case CrearArticuloCategoriaNoExiste():
          errorGeneral = l10n.articuloErrorCategoriaNoExiste;
          return null;
        case CrearArticuloCostoInvalido():
          errorGeneral = l10n.articuloErrorCostoInvalido;
          return null;
        case CrearArticuloErrorInesperado():
          RisegFeedback.showError(context, l10n.articuloErrorInesperado);
          return false;
      }
    },
  );

  nombreCtrl.dispose();
  descripcionCtrl.dispose();
  unidadMedidaCtrl.dispose();
  costoCtrl.dispose();

  return resultado ?? false;
}
