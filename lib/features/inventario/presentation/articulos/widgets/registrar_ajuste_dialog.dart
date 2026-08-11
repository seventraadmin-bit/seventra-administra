import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';

import '../articulos_controller.dart';

/// Diálogo "Ajuste de existencia" (Etapa 7A) — corrección de conteo
/// físico/merma, solo para Artículos por cantidad (los serializados no
/// necesitan ajuste: cada unidad ya tiene su propio estatus). Siempre
/// requiere motivo.
Future<bool> mostrarDialogoRegistrarAjuste(
  BuildContext context,
  WidgetRef ref, {
  required String articuloId,
  required bool manejaVariante,
  required List<ArticuloVarianteData> variantes,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(articulosControllerProvider.notifier);

  bool esEntrada = true;
  String? varianteId = variantes.length == 1 ? variantes.single.id : null;
  final cantidadCtrl = TextEditingController(text: '1');
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarAjusteDialogoTitulo,
    confirmLabel: l10n.registrarAjusteBotonConfirmar,
    cancelLabel: l10n.registrarAjusteBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<bool>(
                label: l10n.registrarAjusteCampoTipo,
                value: esEntrada,
                items: [
                  RisegSelectItem(value: true, label: l10n.registrarAjusteTipoEntrada),
                  RisegSelectItem(value: false, label: l10n.registrarAjusteTipoSalida),
                ],
                onChanged: (valor) => setState(() => esEntrada = valor ?? esEntrada),
              ),
              const SizedBox(height: AppSpacing.md),
              if (manejaVariante) ...[
                RisegSelect<String?>(
                  label: l10n.registrarAjusteCampoVariante,
                  value: varianteId,
                  items: [for (final v in variantes) RisegSelectItem(value: v.id, label: v.valor)],
                  onChanged: (valor) => setState(() => varianteId = valor),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              RisegTextField(label: l10n.registrarAjusteCampoCantidad, controller: cantidadCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarAjusteCampoObservaciones, controller: observacionesCtrl),
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
      final cantidad = int.tryParse(cantidadCtrl.text.trim());
      if (cantidad == null || cantidad <= 0) {
        errorGeneral = l10n.registrarAjusteErrorCantidadInvalida;
        return null;
      }
      if (observacionesCtrl.text.trim().isEmpty) {
        errorGeneral = l10n.registrarAjusteErrorObservacionesRequeridas;
        return null;
      }
      final resultado = await notifier.registrarAjuste(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        esEntrada: esEntrada,
        observaciones: observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarAjusteExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarAjusteExito);
          return true;
        case RegistrarAjusteCantidadInvalida():
          errorGeneral = l10n.registrarAjusteErrorCantidadInvalida;
          return null;
        case RegistrarAjusteObservacionesRequeridas():
          errorGeneral = l10n.registrarAjusteErrorObservacionesRequeridas;
          return null;
        case RegistrarAjusteSobrepasaDisponible():
          errorGeneral = l10n.registrarAjusteErrorSobrepasaDisponible;
          return null;
        case RegistrarAjusteArticuloNoExiste():
        case RegistrarAjusteArticuloManejaSerie():
        case RegistrarAjusteVarianteInvalida():
        case RegistrarAjusteErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarAjusteErrorInesperado);
          return false;
      }
    },
  );

  cantidadCtrl.dispose();
  observacionesCtrl.dispose();

  return resultado ?? false;
}
