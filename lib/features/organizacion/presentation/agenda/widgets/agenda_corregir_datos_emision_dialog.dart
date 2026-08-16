import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_datos_emision_documento_por_emitir_usecase.dart';

import '../agenda_controller.dart';

/// Abre el diálogo "Corregir datos de emisión" (Etapa 4I.2.1) — nunca
/// una edición silenciosa: exige motivo, deja los campos en blanco por
/// defecto (un campo vacío significa "no tocar ese campo", no
/// "bórralo"). Solo disponible mientras el documento está
/// `Emitido`/`Enviado` (nunca después de `Procesado/Aceptado`).
/// Devuelve `true` si se guardó la corrección.
Future<bool> mostrarDialogoCorregirDatosEmision(
  BuildContext context,
  WidgetRef ref,
  DocumentoPorEmitirData documento,
) async {
  final l10n = AppLocalizations.of(context)!;
  final esCfdi = TipoDocumentoCobro.values.byName(documento.tipoDocumento) == TipoDocumentoCobro.cfdi;

  var datos = const _DatosCorreccion();
  var errorUuidFormatoInvalido = false;

  final resultado = await RisegDialog.showForm<CorregirDatosEmisionDocumentoPorEmitirResultado?>(
    context: context,
    title: l10n.agendaCorregirDatosEmisionDialogoTitulo,
    confirmLabel: l10n.agendaCorregirDatosEmisionBotonConfirmar,
    cancelLabel: l10n.agendaCorregirDatosEmisionBotonCancelar,
    contentBuilder: (_) => _CorregirDatosEmisionForm(
      esCfdi: esCfdi,
      documento: documento,
      errorUuidFormatoInvalido: errorUuidFormatoInvalido,
      onCambio: (nuevo) => datos = nuevo,
    ),
    onConfirm: () async {
      final resultado = await ref.read(agendaControllerProvider.notifier).corregirDatosEmision(
            documentoPorEmitirId: documento.id,
            motivo: datos.motivo,
            folioDocumento: datos.folioDocumento.trim().isEmpty ? null : datos.folioDocumento.trim(),
            uuid: esCfdi && datos.uuid.trim().isNotEmpty ? datos.uuid.trim() : null,
            fechaEmisionReal: datos.fechaEmisionReal,
            importeEmitido: datos.importeEmitidoCentavos,
            observacionesEmision: datos.observacionesEmision.trim().isEmpty ? null : datos.observacionesEmision.trim(),
          );
      errorUuidFormatoInvalido = resultado is CorregirDatosEmisionDocumentoPorEmitirUuidFormatoInvalido;
      return resultado;
    },
  );

  if (!context.mounted) return false;

  switch (resultado) {
    case CorregirDatosEmisionDocumentoPorEmitirExitoso():
      RisegFeedback.showSuccess(context, l10n.agendaCorregirDatosEmisionExito);
      return true;
    case CorregirDatosEmisionDocumentoPorEmitirMotivoRequerido():
      RisegFeedback.showError(context, l10n.agendaCorregirDatosEmisionErrorMotivoRequerido);
    case CorregirDatosEmisionDocumentoPorEmitirNoPermitido():
      RisegFeedback.showError(context, l10n.agendaCorregirDatosEmisionErrorNoPermitido);
    case CorregirDatosEmisionDocumentoPorEmitirCamposNoPermitidosParaRecibo():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorCamposNoPermitidosParaRecibo);
    case CorregirDatosEmisionDocumentoPorEmitirUuidFormatoInvalido():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorUuidFormatoInvalido);
    case CorregirDatosEmisionDocumentoPorEmitirImporteInvalido():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorImporteInvalido);
    case CorregirDatosEmisionDocumentoPorEmitirNoExiste():
    case CorregirDatosEmisionDocumentoPorEmitirErrorInesperado():
      RisegFeedback.showError(context, l10n.agendaCorregirDatosEmisionErrorInesperado);
    case null:
      break;
  }
  return false;
}

class _DatosCorreccion {
  const _DatosCorreccion({
    this.motivo = '',
    this.folioDocumento = '',
    this.uuid = '',
    this.fechaEmisionReal,
    this.importeEmitidoCentavos,
    this.observacionesEmision = '',
  });

  final String motivo;
  final String folioDocumento;
  final String uuid;
  final DateTime? fechaEmisionReal;
  final int? importeEmitidoCentavos;
  final String observacionesEmision;

  _DatosCorreccion copyWith({
    String? motivo,
    String? folioDocumento,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitidoCentavos,
    String? observacionesEmision,
  }) {
    return _DatosCorreccion(
      motivo: motivo ?? this.motivo,
      folioDocumento: folioDocumento ?? this.folioDocumento,
      uuid: uuid ?? this.uuid,
      fechaEmisionReal: fechaEmisionReal ?? this.fechaEmisionReal,
      importeEmitidoCentavos: importeEmitidoCentavos ?? this.importeEmitidoCentavos,
      observacionesEmision: observacionesEmision ?? this.observacionesEmision,
    );
  }
}

class _CorregirDatosEmisionForm extends StatefulWidget {
  const _CorregirDatosEmisionForm({
    required this.esCfdi,
    required this.documento,
    required this.errorUuidFormatoInvalido,
    required this.onCambio,
  });

  final bool esCfdi;
  final DocumentoPorEmitirData documento;
  final bool errorUuidFormatoInvalido;
  final void Function(_DatosCorreccion datos) onCambio;

  @override
  State<_CorregirDatosEmisionForm> createState() => _CorregirDatosEmisionFormState();
}

class _CorregirDatosEmisionFormState extends State<_CorregirDatosEmisionForm> {
  var _datos = const _DatosCorreccion();
  final _motivoController = TextEditingController();
  final _folioController = TextEditingController();
  final _uuidController = TextEditingController();
  final _importeController = TextEditingController();
  final _observacionesController = TextEditingController();

  @override
  void dispose() {
    _motivoController.dispose();
    _folioController.dispose();
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
      motivo: _motivoController.text,
      folioDocumento: _folioController.text,
      uuid: _uuidController.text,
      importeEmitidoCentavos: _importeEnCentavos(),
      observacionesEmision: _observacionesController.text,
    );
    widget.onCambio(_datos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = widget.documento;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.agendaCorregirDatosEmisionCampoMotivo,
          controller: _motivoController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.agendaDetalleCampoFolioDocumento,
          controller: _folioController,
          hint: d.folioDocumento,
          onChanged: (_) => _notificar(),
        ),
        if (widget.esCfdi) ...[
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.agendaDetalleCampoUuid,
            controller: _uuidController,
            hint: d.uuid,
            errorText: widget.errorUuidFormatoInvalido ? l10n.agendaRegistrarEmisionErrorUuidFormatoInvalido : null,
            onChanged: (_) => _notificar(),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.agendaDetalleCampoFechaEmisionReal,
          value: _datos.fechaEmisionReal,
          onChanged: (valor) {
            setState(() => _datos = _datos.copyWith(fechaEmisionReal: valor));
            widget.onCambio(_datos);
          },
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
