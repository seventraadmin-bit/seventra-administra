import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_ajuste_historico_documento_por_emitir_usecase.dart';

import '../agenda_controller.dart';
import 'agenda_ajuste_manual_dialog.dart' show AjusteComercialForm, DatosAjusteComercial;

/// Corrección Maestro del ajuste comercial de un documento **ya emitido**.
///
/// Reutiliza el mismo formulario de captura que el ajuste normal —importe con
/// signo y motivo comercial— y le añade lo único que distingue a una
/// corrección histórica: el motivo administrativo de estar reescribiendo un
/// dato que ya es historia.
///
/// El importe lo captura la persona. Esta pantalla nunca lo propone a partir
/// de `importeEmitido - esperado`: un cuadre automático en cero escondería
/// exactamente el error que se quiere poder ver.
Future<bool> mostrarDialogoCorregirAjusteHistorico(
  BuildContext context,
  WidgetRef ref,
  DocumentoPorEmitirData documento,
) async {
  final l10n = AppLocalizations.of(context)!;

  var datos = DatosAjusteComercial(
    ajusteCentavos: documento.ajusteManual,
    motivo: documento.motivoAjuste ?? '',
  );
  final motivoCorreccionCtrl = TextEditingController();

  final resultado = await RisegDialog.showForm<CorregirAjusteHistoricoDocumentoPorEmitirResultado?>(
    context: context,
    title: l10n.agendaCorreccionHistoricaTitulo,
    confirmLabel: l10n.agendaAjusteManualBotonConfirmar,
    cancelLabel: l10n.agendaAjusteManualBotonCancelar,
    contentBuilder: (dialogContext) => SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agendaCorreccionHistoricaAdvertencia, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          AjusteComercialForm(
            importeBase: documento.importeBaseEsperado,
            datosIniciales: datos,
            onCambio: (nuevo) => datos = nuevo,
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            key: const Key('agenda_correccion_historica_motivo'),
            label: l10n.agendaCorreccionHistoricaCampoMotivoCorreccion,
            controller: motivoCorreccionCtrl,
          ),
        ],
      ),
    ),
    onConfirm: () async {
      return ref.read(agendaControllerProvider.notifier).corregirAjusteHistorico(
            documentoPorEmitirId: documento.id,
            motivoCorreccion: motivoCorreccionCtrl.text,
            ajusteManual: datos.ajusteCentavos,
            motivoAjuste: datos.motivo.trim().isEmpty ? null : datos.motivo.trim(),
          );
    },
  );

  motivoCorreccionCtrl.dispose();
  if (!context.mounted) return false;

  switch (resultado) {
    case CorregirAjusteHistoricoDocumentoPorEmitirExitoso():
      RisegFeedback.showSuccess(context, l10n.agendaCorreccionHistoricaExito);
      return true;
    case CorregirAjusteHistoricoDocumentoPorEmitirMotivoCorreccionRequerido():
      RisegFeedback.showError(context, l10n.agendaCorreccionHistoricaErrorMotivoCorreccionRequerido);
    case CorregirAjusteHistoricoDocumentoPorEmitirMotivoAjusteRequerido():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorMotivoRequerido);
    case CorregirAjusteHistoricoDocumentoPorEmitirImporteNegativo():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorImporteNegativo);
    case CorregirAjusteHistoricoDocumentoPorEmitirNoEmitido():
      RisegFeedback.showError(context, l10n.agendaCorreccionHistoricaErrorNoEmitido);
    case CorregirAjusteHistoricoDocumentoPorEmitirNoExiste():
    case CorregirAjusteHistoricoDocumentoPorEmitirErrorInesperado():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorInesperado);
    case null:
      break;
  }
  return false;
}
