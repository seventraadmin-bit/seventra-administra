import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_usecase.dart';

import '../articulos_controller.dart';

/// Diálogo "Registrar baja" (Etapa 7A) — se adapta según
/// `articulo.manejaSerie`: selecciona una unidad concreta (nunca texto
/// libre) o captura cantidad + talla/variante. Siempre requiere
/// motivo/observaciones.
Future<bool> mostrarDialogoRegistrarBaja(
  BuildContext context,
  WidgetRef ref, {
  required ArticuloData articulo,
  required List<ArticuloVarianteData> variantes,
  required List<ArticuloUnidadData> unidadesDisponibles,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(articulosControllerProvider.notifier);

  String? varianteId = variantes.length == 1 ? variantes.single.id : null;
  String? unidadId = unidadesDisponibles.length == 1 ? unidadesDisponibles.single.id : null;
  final cantidadCtrl = TextEditingController(text: '1');
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarBajaDialogoTitulo,
    confirmLabel: l10n.registrarBajaBotonConfirmar,
    cancelLabel: l10n.registrarBajaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (articulo.manejaSerie) ...[
                RisegSelect<String?>(
                  label: l10n.registrarBajaCampoUnidad,
                  value: unidadId,
                  items: [for (final u in unidadesDisponibles) RisegSelectItem(value: u.id, label: '${u.codigo} · ${u.numeroSerie}')],
                  onChanged: (valor) => setState(() => unidadId = valor),
                ),
              ] else ...[
                if (articulo.manejaVariante) ...[
                  RisegSelect<String?>(
                    label: l10n.registrarBajaCampoVariante,
                    value: varianteId,
                    items: [for (final v in variantes) RisegSelectItem(value: v.id, label: v.valor)],
                    onChanged: (valor) => setState(() => varianteId = valor),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                RisegTextField(
                  label: l10n.registrarBajaCampoCantidad,
                  controller: cantidadCtrl,
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.registrarBajaCampoObservaciones, controller: observacionesCtrl, autofocus: true),
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
      if (observacionesCtrl.text.trim().isEmpty) {
        errorGeneral = l10n.registrarBajaErrorObservacionesRequeridas;
        return null;
      }
      if (articulo.manejaSerie) {
        if (unidadId == null) {
          errorGeneral = l10n.registrarBajaCampoUnidad;
          return null;
        }
        final resultado = await notifier.registrarBajaUnidad(unidadId: unidadId!, observaciones: observacionesCtrl.text.trim());
        if (!context.mounted) return false;
        switch (resultado) {
          case RegistrarBajaUnidadExitoso():
            RisegFeedback.showSuccess(context, l10n.registrarBajaExito);
            return true;
          case RegistrarBajaUnidadObservacionesRequeridas():
            errorGeneral = l10n.registrarBajaErrorObservacionesRequeridas;
            return null;
          case RegistrarBajaUnidadYaDeBaja():
            errorGeneral = l10n.registrarBajaErrorYaDeBaja;
            return null;
          case RegistrarBajaUnidadAsignada():
            errorGeneral = l10n.registrarBajaErrorUnidadAsignada;
            return null;
          case RegistrarBajaUnidadTraeLineaTelefonica():
            errorGeneral = l10n.registrarBajaErrorTraeLineaTelefonica;
            return null;
          case RegistrarBajaUnidadNoExiste():
          case RegistrarBajaUnidadErrorInesperado():
            RisegFeedback.showError(context, l10n.registrarBajaErrorInesperado);
            return false;
        }
      }

      final cantidad = int.tryParse(cantidadCtrl.text.trim());
      if (cantidad == null || cantidad <= 0) {
        errorGeneral = l10n.registrarBajaErrorCantidadInvalida;
        return null;
      }

      final resultado = await notifier.registrarBaja(
        articuloId: articulo.id,
        varianteId: varianteId,
        cantidad: cantidad,
        observaciones: observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegistrarBajaExitoso():
          RisegFeedback.showSuccess(context, l10n.registrarBajaExito);
          return true;
        case RegistrarBajaCantidadInvalida():
          errorGeneral = l10n.registrarBajaErrorCantidadInvalida;
          return null;
        case RegistrarBajaObservacionesRequeridas():
          errorGeneral = l10n.registrarBajaErrorObservacionesRequeridas;
          return null;
        case RegistrarBajaSobrepasaDisponible(:final disponible):
          errorGeneral = l10n.registrarBajaErrorSobrepasaDisponible(disponible);
          return null;
        case RegistrarBajaArticuloNoExiste():
        case RegistrarBajaArticuloManejaSerie():
        case RegistrarBajaVarianteInvalida():
        case RegistrarBajaErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarBajaErrorInesperado);
          return false;
      }
    },
  );

  cantidadCtrl.dispose();
  observacionesCtrl.dispose();

  return resultado ?? false;
}
