import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_variante_articulo_usecase.dart';

import '../articulos_controller.dart';

/// Diálogo "Nueva talla/variante" (Etapa 7A) — "artículo + variante"
/// en vez de un producto nuevo por talla.
Future<bool> mostrarDialogoCrearVariante(BuildContext context, WidgetRef ref, {required String articuloId}) async {
  final l10n = AppLocalizations.of(context)!;
  final valorCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.crearVarianteDialogoTitulo,
    confirmLabel: l10n.crearVarianteBotonConfirmar,
    cancelLabel: l10n.crearVarianteBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              label: l10n.crearVarianteCampoValor,
              controller: valorCtrl,
              autofocus: true,
              errorText: errorGeneral,
              onChanged: (_) => setState(() => errorGeneral = null),
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(articulosControllerProvider.notifier).crearVariante(
            articuloId: articuloId,
            valor: valorCtrl.text,
          );
      if (!context.mounted) return false;

      switch (resultado) {
        case CrearVarianteArticuloExitoso():
          RisegFeedback.showSuccess(context, l10n.crearVarianteExito);
          return true;
        case CrearVarianteArticuloValorRequerido():
          errorGeneral = l10n.crearVarianteErrorValorRequerido;
          return null;
        case CrearVarianteArticuloValorDuplicado():
          errorGeneral = l10n.crearVarianteErrorDuplicado;
          return null;
        case CrearVarianteArticuloArticuloNoExiste():
        case CrearVarianteArticuloArticuloNoManejaVariante():
        case CrearVarianteArticuloErrorInesperado():
          RisegFeedback.showError(context, l10n.crearVarianteErrorInesperado);
          return false;
      }
    },
  );

  valorCtrl.dispose();
  return resultado ?? false;
}
