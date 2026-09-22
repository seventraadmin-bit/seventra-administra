import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../agenda_controller.dart';
import '../agenda_list_screen.dart' show formatoCentavosAgenda;

/// Abre el diálogo "Ajuste manual" (Etapa 4I.2.2 — la interfaz de
/// captura que 4I.1/4I.2.1 difirieron deliberadamente). Muestra en vivo
/// Descuento/Incremento/Sin ajuste y el importe final resultante.
/// Devuelve `true` si se guardó el ajuste.
Future<bool> mostrarDialogoAjusteManual(BuildContext context, WidgetRef ref, DocumentoPorEmitirData documento) async {
  final l10n = AppLocalizations.of(context)!;

  var datos = DatosAjusteComercial(
    ajusteCentavos: documento.ajusteManual,
    motivo: documento.motivoAjuste ?? '',
  );

  final resultado = await RisegDialog.showForm<ActualizarAjusteManualDocumentoPorEmitirResultado?>(
    context: context,
    title: l10n.agendaAjusteManualDialogoTitulo,
    confirmLabel: l10n.agendaAjusteManualBotonConfirmar,
    cancelLabel: l10n.agendaAjusteManualBotonCancelar,
    contentBuilder: (_) => AjusteComercialForm(
      importeBase: documento.importeBaseEsperado,
      datosIniciales: datos,
      onCambio: (nuevo) => datos = nuevo,
    ),
    onConfirm: () async {
      return ref.read(agendaControllerProvider.notifier).actualizarAjusteManual(
            documentoPorEmitirId: documento.id,
            ajusteManual: datos.ajusteCentavos,
            motivoAjuste: datos.motivo.trim().isEmpty ? null : datos.motivo.trim(),
          );
    },
  );

  if (!context.mounted) return false;

  switch (resultado) {
    case ActualizarAjusteManualDocumentoPorEmitirExitoso():
      RisegFeedback.showSuccess(context, l10n.agendaAjusteManualExito);
      return true;
    case ActualizarAjusteManualDocumentoPorEmitirMotivoRequerido():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorMotivoRequerido);
    case ActualizarAjusteManualDocumentoPorEmitirCongelado():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorCongelado);
    case ActualizarAjusteManualDocumentoPorEmitirImporteNegativo():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorImporteNegativo);
    case ActualizarAjusteManualDocumentoPorEmitirNoExiste():
    case ActualizarAjusteManualDocumentoPorEmitirErrorInesperado():
      RisegFeedback.showError(context, l10n.agendaAjusteManualErrorInesperado);
    case null:
      break;
  }
  return false;
}

/// Importe con signo + motivo comercial libre — lo que el usuario captura,
/// tanto en el ajuste normal como en la correccion historica Maestro.
class DatosAjusteComercial {
  const DatosAjusteComercial({this.ajusteCentavos, this.motivo = ''});
  final int? ajusteCentavos;
  final String motivo;
}

/// Captura del ajuste comercial, compartida por el ajuste previo a la
/// emision y por la correccion historica: el dato es el mismo, cambia solo
/// quien puede tocarlo y que mas se le exige alrededor.
class AjusteComercialForm extends StatefulWidget {
  const AjusteComercialForm({required this.importeBase, required this.datosIniciales, required this.onCambio});

  final int importeBase;
  final DatosAjusteComercial datosIniciales;
  final void Function(DatosAjusteComercial datos) onCambio;

  @override
  State<AjusteComercialForm> createState() => AjusteComercialFormState();
}

class AjusteComercialFormState extends State<AjusteComercialForm> {
  late final _ajusteController = TextEditingController(
    text: widget.datosIniciales.ajusteCentavos == null
        ? ''
        : (widget.datosIniciales.ajusteCentavos! / 100).toStringAsFixed(2),
  );
  late final _motivoController = TextEditingController(text: widget.datosIniciales.motivo);
  int? _ajusteCentavos;

  @override
  void initState() {
    super.initState();
    _ajusteCentavos = widget.datosIniciales.ajusteCentavos;
  }

  @override
  void dispose() {
    _ajusteController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  int? _parsearAjuste() {
    final texto = _ajusteController.text.trim().replaceAll(',', '');
    if (texto.isEmpty) return null;
    final valor = double.tryParse(texto);
    if (valor == null) return null;
    return (valor * 100).round();
  }

  void _notificar() {
    _ajusteCentavos = _parsearAjuste();
    setState(() {});
    widget.onCambio(DatosAjusteComercial(ajusteCentavos: _ajusteCentavos, motivo: _motivoController.text));
  }

  String _etiquetaAjuste(AppLocalizations l10n) {
    final ajuste = _ajusteCentavos;
    if (ajuste == null || ajuste == 0) return l10n.agendaAjusteEtiquetaSinAjuste;
    final monto = formatoCentavosAgenda(ajuste.abs());
    return ajuste < 0 ? l10n.agendaAjusteEtiquetaDescuento(monto) : l10n.agendaAjusteEtiquetaIncremento(monto);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final importeFinal = widget.importeBase + (_ajusteCentavos ?? 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.agendaAjusteManualCampoAjuste,
          controller: _ajusteController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          helperText: _etiquetaAjuste(l10n),
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.agendaAjusteManualCampoMotivo,
          controller: _motivoController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        CampoConsulta(label: l10n.agendaAjusteManualCampoImporteFinal, value: formatoCentavosAgenda(importeFinal)),
      ],
    );
  }
}
