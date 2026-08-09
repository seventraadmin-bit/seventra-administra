import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';

import '../agenda_controller.dart';

/// Abre el diálogo "Registrar emisión" (Etapa 4I.2.1) — captura los
/// datos definitivos y transiciona el documento a `Emitido`. Serie
/// fiscal/folio fiscal/UUID solo se muestran para CFDI (Resolución 11
/// de Marlon: un recibo nunca los captura). UUID/XML pueden agregarse
/// después — nunca obligatorios al momento de emitir. Devuelve `true`
/// si se registró la emisión.
Future<bool> mostrarDialogoRegistrarEmision(BuildContext context, WidgetRef ref, DocumentoPorEmitirData documento) async {
  final l10n = AppLocalizations.of(context)!;
  final esCfdi = TipoDocumentoCobro.values.byName(documento.tipoDocumento) == TipoDocumentoCobro.cfdi;

  var datos = const _DatosEmision();

  final resultado = await RisegDialog.showForm<RegistrarEmisionDocumentoPorEmitirResultado?>(
    context: context,
    title: l10n.agendaRegistrarEmisionDialogoTitulo,
    confirmLabel: l10n.agendaRegistrarEmisionBotonConfirmar,
    cancelLabel: l10n.agendaRegistrarEmisionBotonCancelar,
    contentBuilder: (_) => _RegistrarEmisionForm(esCfdi: esCfdi, onCambio: (nuevo) => datos = nuevo),
    onConfirm: () async {
      return ref.read(agendaControllerProvider.notifier).registrarEmision(
            documentoPorEmitirId: documento.id,
            folioDocumento: datos.folioDocumento,
            serieFiscal: esCfdi && datos.serieFiscal.trim().isNotEmpty ? datos.serieFiscal.trim() : null,
            folioFiscal: esCfdi && datos.folioFiscal.trim().isNotEmpty ? datos.folioFiscal.trim() : null,
            uuid: esCfdi && datos.uuid.trim().isNotEmpty ? datos.uuid.trim() : null,
            fechaEmisionReal: datos.fechaEmisionReal,
            importeEmitido: datos.importeEmitidoCentavos ?? 0,
            observacionesEmision: datos.observaciones.trim().isEmpty ? null : datos.observaciones.trim(),
          );
    },
  );

  if (!context.mounted) return false;

  switch (resultado) {
    case RegistrarEmisionDocumentoPorEmitirExitoso():
      RisegFeedback.showSuccess(context, l10n.agendaRegistrarEmisionExito);
      return true;
    case RegistrarEmisionDocumentoPorEmitirFolioRequerido():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorFolioRequerido);
    case RegistrarEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorCamposNoPermitidosParaRecibo);
    case RegistrarEmisionDocumentoPorEmitirImporteInvalido():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorImporteInvalido);
    case RegistrarEmisionDocumentoPorEmitirTransicionInvalida():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorTransicionInvalida);
    case RegistrarEmisionDocumentoPorEmitirNoExiste():
    case RegistrarEmisionDocumentoPorEmitirErrorInesperado():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorInesperado);
    case null:
      break;
  }
  return false;
}

class _DatosEmision {
  const _DatosEmision({
    this.folioDocumento = '',
    this.serieFiscal = '',
    this.folioFiscal = '',
    this.uuid = '',
    DateTime? fechaEmisionReal,
    this.importeEmitidoCentavos,
    this.observaciones = '',
  }) : _fechaEmisionReal = fechaEmisionReal;

  final String folioDocumento;
  final String serieFiscal;
  final String folioFiscal;
  final String uuid;
  final DateTime? _fechaEmisionReal;
  final int? importeEmitidoCentavos;
  final String observaciones;

  DateTime get fechaEmisionReal => _fechaEmisionReal ?? DateTime.now();

  _DatosEmision copyWith({
    String? folioDocumento,
    String? serieFiscal,
    String? folioFiscal,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitidoCentavos,
    String? observaciones,
  }) {
    return _DatosEmision(
      folioDocumento: folioDocumento ?? this.folioDocumento,
      serieFiscal: serieFiscal ?? this.serieFiscal,
      folioFiscal: folioFiscal ?? this.folioFiscal,
      uuid: uuid ?? this.uuid,
      fechaEmisionReal: fechaEmisionReal ?? _fechaEmisionReal,
      importeEmitidoCentavos: importeEmitidoCentavos ?? this.importeEmitidoCentavos,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

class _RegistrarEmisionForm extends StatefulWidget {
  const _RegistrarEmisionForm({required this.esCfdi, required this.onCambio});

  final bool esCfdi;
  final void Function(_DatosEmision datos) onCambio;

  @override
  State<_RegistrarEmisionForm> createState() => _RegistrarEmisionFormState();
}

class _RegistrarEmisionFormState extends State<_RegistrarEmisionForm> {
  var _datos = const _DatosEmision();
  final _folioController = TextEditingController();
  final _serieController = TextEditingController();
  final _folioFiscalController = TextEditingController();
  final _uuidController = TextEditingController();
  final _importeController = TextEditingController();
  final _observacionesController = TextEditingController();

  @override
  void dispose() {
    _folioController.dispose();
    _serieController.dispose();
    _folioFiscalController.dispose();
    _uuidController.dispose();
    _importeController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  int? _importeEnCentavos() {
    final texto = _importeController.text.trim().replaceAll(',', '');
    if (texto.isEmpty) return null;
    final valor = double.tryParse(texto);
    if (valor == null) return null;
    return (valor * 100).round();
  }

  void _notificar() {
    _datos = _datos.copyWith(
      folioDocumento: _folioController.text,
      serieFiscal: _serieController.text,
      folioFiscal: _folioFiscalController.text,
      uuid: _uuidController.text,
      importeEmitidoCentavos: _importeEnCentavos(),
      observaciones: _observacionesController.text,
    );
    widget.onCambio(_datos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.agendaDetalleCampoFolioDocumento,
          controller: _folioController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        if (widget.esCfdi) ...[
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.agendaDetalleCampoSerieFiscal,
            controller: _serieController,
            onChanged: (_) => _notificar(),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.agendaDetalleCampoFolioFiscal,
            controller: _folioFiscalController,
            onChanged: (_) => _notificar(),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.agendaDetalleCampoUuid,
            controller: _uuidController,
            onChanged: (_) => _notificar(),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.agendaDetalleCampoFechaEmisionReal,
          value: _datos.fechaEmisionReal,
          onChanged: (valor) => setState(() {
            _datos = _datos.copyWith(fechaEmisionReal: valor);
            widget.onCambio(_datos);
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.agendaDetalleCampoImporteEmitido,
          controller: _importeController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.agendaDetalleCampoObservacionesEmision,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
