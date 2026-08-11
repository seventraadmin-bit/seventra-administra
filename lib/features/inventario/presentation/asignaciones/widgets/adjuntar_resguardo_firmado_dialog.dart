import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/adjuntar_resguardo_firmado_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import 'seleccionar_asignaciones_dialog.dart';

/// "Adjuntar resguardo firmado" (Etapa 7C) — selecciona las
/// Asignaciones que cubre el documento (nunca texto libre) y sube el
/// escaneo/foto ya firmado. Es el único paso de todo el flujo de
/// resguardo que persiste algo.
///
/// Devuelve `true` si se adjuntó correctamente.
Future<bool> mostrarDialogoAdjuntarResguardoFirmado(
  BuildContext context,
  WidgetRef ref, {
  required List<AsignacionData> asignaciones,
  required String Function(AsignacionData) detalleBuilder,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final seleccionadas = await mostrarDialogoSeleccionarAsignaciones(
    context,
    asignaciones: asignaciones,
    detalleBuilder: detalleBuilder,
    titulo: l10n.adjuntarResguardoDialogoTitulo,
    botonConfirmar: l10n.adjuntarResguardoBotonSeleccionarArchivo,
  );
  if (seleccionadas == null || !context.mounted) return false;

  final seleccion = await FilePicker.platform.pickFiles();
  final archivo = seleccion?.files.singleOrNull;
  if (archivo?.path == null) return false;
  if (!context.mounted) return false;
  final resultado = await ref.read(adjuntarResguardoFirmadoAutorizadoProvider)(
        asignacionIds: seleccionadas,
        sourceFilePath: archivo!.path!,
        originalFileName: archivo.name,
        mimeType: 'application/octet-stream',
      );
  if (!context.mounted) return false;

  switch (resultado) {
    case AdjuntarResguardoFirmadoExitoso():
      RisegFeedback.showSuccess(context, l10n.adjuntarResguardoExito);
      return true;
    case AdjuntarResguardoFirmadoSinAsignaciones():
      RisegFeedback.showError(context, l10n.adjuntarResguardoErrorSinAsignaciones);
      return false;
    case AdjuntarResguardoFirmadoDestinoInvalido():
      RisegFeedback.showError(context, l10n.adjuntarResguardoErrorDestinoInvalido);
      return false;
    case AdjuntarResguardoFirmadoAsignacionNoExiste():
    case AdjuntarResguardoFirmadoErrorInesperado():
      RisegFeedback.showError(context, l10n.adjuntarResguardoErrorInesperado);
      return false;
  }
}
