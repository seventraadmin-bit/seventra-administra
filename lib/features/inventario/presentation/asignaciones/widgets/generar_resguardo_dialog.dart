import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/generar_documento_resguardo_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import 'seleccionar_asignaciones_dialog.dart';

/// "Generar resguardo" (Etapa 7C) — selecciona Asignaciones activas
/// (nunca texto libre) y genera el PDF para imprimir. No persiste
/// nada: el documento se firma en papel y se adjunta después vía
/// `mostrarDialogoAdjuntarResguardoFirmado`.
Future<void> mostrarDialogoGenerarResguardo(
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
    titulo: l10n.generarResguardoDialogoTitulo,
    botonConfirmar: l10n.generarResguardoBotonConfirmar,
  );
  if (seleccionadas == null || !context.mounted) return;

  final resultado = await ref.read(generarDocumentoResguardoUseCaseProvider).ejecutar(asignacionIds: seleccionadas);
  if (!context.mounted) return;

  switch (resultado) {
    case GenerarDocumentoResguardoExitoso():
      RisegFeedback.showSuccess(context, l10n.generarResguardoExito);
    case GenerarDocumentoResguardoSinAsignaciones():
      RisegFeedback.showError(context, l10n.generarResguardoErrorSinAsignaciones);
    case GenerarDocumentoResguardoDestinoInvalido():
      RisegFeedback.showError(context, l10n.generarResguardoErrorDestinoInvalido);
    case GenerarDocumentoResguardoAsignacionNoExiste():
    case GenerarDocumentoResguardoErrorInesperado():
      RisegFeedback.showError(context, l10n.generarResguardoErrorInesperado);
  }
}
