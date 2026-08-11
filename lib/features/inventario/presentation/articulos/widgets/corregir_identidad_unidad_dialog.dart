import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_identidad_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

/// Diálogo "Corregir identificación de unidad" (Etapa 9D, tercer ajuste
/// posterior) — número de serie, marca, modelo y, si la unidad ya es un
/// teléfono configurado (tiene fila `ArticuloUnidadTelefono`), IMEI 1/
/// IMEI 2. Deliberadamente NO es lo mismo que "Configurar equipo"/
/// "Editar IMEI" (`mostrarDialogoConfigurarEquipoTelefonico`, uso
/// operativo diario sin motivo): esta es una corrección sensible que
/// exige motivo y queda auditada campo por campo en
/// `ArticuloUnidadEvento`. Vive en Inventario (no en Telefonía) porque
/// la unidad sigue siendo la misma `ArticuloUnidad` — Telefonía solo
/// importa este diálogo para ofrecer el mismo acceso desde el
/// expediente del Equipo.
///
/// Precarga los campos con los valores actuales de [unidad]/[telefono]
/// — el usuario solo cambia lo que está mal, el resto se reenvía tal
/// cual (el caso de uso trata cada campo de forma independiente: si no
/// cambió respecto al valor previo, `InventarioRepository.corregirIdentidadUnidad`
/// no genera evento para ese campo).
Future<bool> mostrarDialogoCorregirIdentidadUnidad(
  BuildContext context,
  WidgetRef ref, {
  required ArticuloUnidadData unidad,
  ArticuloUnidadTelefonoData? telefono,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final corregir = ref.read(corregirIdentidadUnidadAutorizadoProvider);

  final numeroSerieCtrl = TextEditingController(text: unidad.numeroSerie);
  final marcaCtrl = TextEditingController(text: unidad.marca ?? '');
  final modeloCtrl = TextEditingController(text: unidad.modelo ?? '');
  final imei1Ctrl = TextEditingController(text: telefono?.imei ?? '');
  final imei2Ctrl = TextEditingController(text: telefono?.imei2 ?? '');
  final motivoCtrl = TextEditingController();
  final esTelefono = telefono != null;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirIdentidadUnidadDialogoTitulo,
    confirmLabel: l10n.corregirIdentidadUnidadBotonGuardar,
    cancelLabel: l10n.corregirIdentidadUnidadBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.corregirIdentidadUnidadDialogoDescripcion,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirIdentidadUnidadCampoNumeroSerie, controller: numeroSerieCtrl),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirIdentidadUnidadCampoMarca, controller: marcaCtrl),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirIdentidadUnidadCampoModelo, controller: modeloCtrl),
                if (esTelefono) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(label: l10n.equipoTelefonicoConfigurarCampoImei1, controller: imei1Ctrl),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(label: l10n.equipoTelefonicoConfigurarCampoImei2, controller: imei2Ctrl),
                ],
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.corregirIdentidadUnidadCampoMotivo, controller: motivoCtrl),
                if (errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
        );
      },
    ),
    onConfirm: () async {
      final resultado = await corregir(
        unidadId: unidad.id,
        motivo: motivoCtrl.text,
        numeroSerie: numeroSerieCtrl.text,
        marca: marcaCtrl.text,
        modelo: modeloCtrl.text,
        imei: esTelefono ? imei1Ctrl.text : null,
        imei2: esTelefono ? imei2Ctrl.text : null,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CorregirIdentidadUnidadExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirIdentidadUnidadExito);
          return true;
        case CorregirIdentidadUnidadMotivoRequerido():
          errorGeneral = l10n.corregirIdentidadUnidadErrorMotivoRequerido;
          return null;
        case CorregirIdentidadUnidadNumeroSerieRequerido():
          errorGeneral = l10n.corregirIdentidadUnidadErrorNumeroSerieRequerido;
          return null;
        case CorregirIdentidadUnidadNumeroSerieDuplicado(:final detalle):
          errorGeneral = detalle;
          return null;
        case CorregirIdentidadUnidadImeiDuplicado(:final detalle):
          errorGeneral = detalle;
          return null;
        case CorregirIdentidadUnidadNoExiste():
        case CorregirIdentidadUnidadErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirIdentidadUnidadErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    numeroSerieCtrl.dispose();
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    imei1Ctrl.dispose();
    imei2Ctrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
