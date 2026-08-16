import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_totales_esperados_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/resumen_iva_documento_por_emitir.dart';

import '../agenda_controller.dart';
import '../agenda_list_screen.dart' show formatoCentavosAgenda;

/// Convierte centavos a un texto decimal plano (`21800.00`), compatible
/// con lo que `_importeEnCentavos` puede volver a parsear — a
/// diferencia de `formatoCentavosAgenda`, que agrega `$`/comas y no es
/// apto para prellenar un campo editable.
String _centavosATextoEditable(int centavos) => (centavos / 100).toStringAsFixed(2);

/// `null` solo para `mixto` (líneas con distinto tratamiento de IVA) —
/// `calcularTotalesEsperados` recibe un único `TratamientoIva`, y no
/// existe una tasa única correcta para aplicar a un documento mixto
/// (Etapa 15, mismo criterio que `DocumentoPorEmitirDetalle.totalesEsperados`).
TotalesEsperados? _totalesEsperados(DocumentoPorEmitirData documento, ResumenIvaDocumento resumen) {
  final tratamiento = switch (resumen) {
    ResumenIvaDocumento.masIva => TratamientoIva.masIva,
    ResumenIvaDocumento.ivaIncluido => TratamientoIva.ivaIncluido,
    ResumenIvaDocumento.noAplica => TratamientoIva.noAplica,
    ResumenIvaDocumento.mixto => null,
  };
  if (tratamiento == null) return null;
  return calcularTotalesEsperados(
    importeBaseCentavos: documento.importeBaseEsperado,
    ajusteManualCentavos: documento.ajusteManual,
    tratamientoIva: tratamiento,
  );
}

/// Abre el diálogo "Registrar emisión" (Etapa 4I.2.1) — captura los
/// datos definitivos y transiciona el documento a `Emitido`. UUID/folio
/// fiscal solo se muestra para CFDI (Resolución 11 de Marlon: un recibo
/// nunca lo captura) — Etapa 15: `serieFiscal`/`folioFiscal` se
/// eliminaron (sin consumidor real, y `folioFiscal` es el mismo dato
/// que `uuid` en cualquier CFDI real); UUID puede agregarse después,
/// nunca obligatorio al momento de emitir.
///
/// `importeEmitido` se prellena con el Total esperado (base + IVA
/// cuando `masIva`) — RISEG ONE sí calcula el 16% para control
/// comercial/cobranza (Etapa 15, segunda corrección tras el CFDI real
/// de MILUYOLE: la primera versión dejaba el campo vacío para `masIva`,
/// pero el cálculo del total esperado ya es responsabilidad del
/// dominio, así que prellenarlo dejó de ser una suposición riesgosa).
/// Sigue siendo editable: el CFDI real puede, excepcionalmente,
/// emitirse por otro monto. Solo queda vacío cuando el documento es
/// `mixto` (sin una tasa única aplicable). Devuelve `true` si se
/// registró la emisión.
Future<bool> mostrarDialogoRegistrarEmision(
  BuildContext context,
  WidgetRef ref,
  DocumentoPorEmitirData documento,
  ResumenIvaDocumento resumenIva,
) async {
  final l10n = AppLocalizations.of(context)!;
  final esCfdi = TipoDocumentoCobro.values.byName(documento.tipoDocumento) == TipoDocumentoCobro.cfdi;
  final totales = _totalesEsperados(documento, resumenIva);
  final importeInicialCentavos = totales?.totalEsperado;

  var datos = _DatosEmision(importeEmitidoCentavos: importeInicialCentavos);
  var errorImporteRequerido = false;
  var errorUuidFormatoInvalido = false;

  final resultado = await RisegDialog.showForm<RegistrarEmisionDocumentoPorEmitirResultado?>(
    context: context,
    title: l10n.agendaRegistrarEmisionDialogoTitulo,
    confirmLabel: l10n.agendaRegistrarEmisionBotonConfirmar,
    cancelLabel: l10n.agendaRegistrarEmisionBotonCancelar,
    contentBuilder: (_) => _RegistrarEmisionForm(
      esCfdi: esCfdi,
      resumenIva: resumenIva,
      totales: totales,
      importeInicialCentavos: importeInicialCentavos,
      errorImporteRequerido: errorImporteRequerido,
      errorUuidFormatoInvalido: errorUuidFormatoInvalido,
      onCambio: (nuevo) => datos = nuevo,
    ),
    onConfirm: () async {
      if (datos.importeEmitidoCentavos == null) {
        errorImporteRequerido = true;
        return null;
      }
      errorImporteRequerido = false;
      final uuid = esCfdi && datos.uuid.trim().isNotEmpty ? datos.uuid.trim() : null;
      final resultado = await ref.read(agendaControllerProvider.notifier).registrarEmision(
            documentoPorEmitirId: documento.id,
            folioDocumento: datos.folioDocumento,
            uuid: uuid,
            fechaEmisionReal: datos.fechaEmisionReal,
            importeEmitido: datos.importeEmitidoCentavos!,
            observacionesEmision: datos.observaciones.trim().isEmpty ? null : datos.observaciones.trim(),
          );
      errorUuidFormatoInvalido = resultado is RegistrarEmisionDocumentoPorEmitirUuidFormatoInvalido;
      return resultado;
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
    case RegistrarEmisionDocumentoPorEmitirUuidFormatoInvalido():
      RisegFeedback.showError(context, l10n.agendaRegistrarEmisionErrorUuidFormatoInvalido);
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
    this.uuid = '',
    DateTime? fechaEmisionReal,
    this.importeEmitidoCentavos,
    this.observaciones = '',
  }) : _fechaEmisionReal = fechaEmisionReal;

  final String folioDocumento;
  final String uuid;
  final DateTime? _fechaEmisionReal;
  final int? importeEmitidoCentavos;
  final String observaciones;

  DateTime get fechaEmisionReal => _fechaEmisionReal ?? DateTime.now();

  /// `importeEmitidoCentavos` acepta `null` como valor real (el campo
  /// nace vacío para un documento `mixto`, o el usuario lo borró) — a
  /// diferencia del resto de los campos aquí, `??` no sirve para él:
  /// confundiría "sin cambio" con "lo borré a propósito" y
  /// silenciosamente conservaría el importe anterior (Etapa 15, bug
  /// real encontrado por la propia prueba de este hallazgo).
  /// `limpiarImporte` es la señal explícita de que sí se está
  /// actualizando el campo, aunque el nuevo valor sea `null`.
  _DatosEmision copyWith({
    String? folioDocumento,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitidoCentavos,
    bool limpiarImporte = false,
    String? observaciones,
  }) {
    return _DatosEmision(
      folioDocumento: folioDocumento ?? this.folioDocumento,
      uuid: uuid ?? this.uuid,
      fechaEmisionReal: fechaEmisionReal ?? _fechaEmisionReal,
      importeEmitidoCentavos: limpiarImporte ? null : (importeEmitidoCentavos ?? this.importeEmitidoCentavos),
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

class _RegistrarEmisionForm extends StatefulWidget {
  const _RegistrarEmisionForm({
    required this.esCfdi,
    required this.resumenIva,
    required this.totales,
    required this.importeInicialCentavos,
    required this.errorImporteRequerido,
    required this.errorUuidFormatoInvalido,
    required this.onCambio,
  });

  final bool esCfdi;
  final ResumenIvaDocumento resumenIva;
  final TotalesEsperados? totales;
  final int? importeInicialCentavos;
  final bool errorImporteRequerido;
  final bool errorUuidFormatoInvalido;
  final void Function(_DatosEmision datos) onCambio;

  @override
  State<_RegistrarEmisionForm> createState() => _RegistrarEmisionFormState();
}

class _RegistrarEmisionFormState extends State<_RegistrarEmisionForm> {
  late var _datos = _DatosEmision(importeEmitidoCentavos: widget.importeInicialCentavos);
  final _folioController = TextEditingController();
  final _uuidController = TextEditingController();
  late final _importeController = TextEditingController(
    text: widget.importeInicialCentavos == null ? '' : _centavosATextoEditable(widget.importeInicialCentavos!),
  );
  final _observacionesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // El valor prellenado (cuando aplica) ya es el que se usaría si el
    // usuario confirma sin tocar el campo — se empuja de inmediato para
    // que `onConfirm` (que solo lee la última notificación) no dependa
    // de un primer `onChanged` que quizás nunca ocurra.
    widget.onCambio(_datos);
  }

  @override
  void dispose() {
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
    final importe = _importeEnCentavos();
    _datos = _datos.copyWith(
      folioDocumento: _folioController.text,
      uuid: _uuidController.text,
      importeEmitidoCentavos: importe,
      limpiarImporte: importe == null,
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
            label: l10n.agendaDetalleCampoUuid,
            controller: _uuidController,
            errorText: widget.errorUuidFormatoInvalido ? l10n.agendaRegistrarEmisionErrorUuidFormatoInvalido : null,
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
        if (widget.resumenIva == ResumenIvaDocumento.masIva && widget.totales != null) ...[
          Text(
            l10n.agendaRegistrarEmisionDesgloseMasIva(
              formatoCentavosAgenda(widget.totales!.base),
              formatoCentavosAgenda(widget.totales!.ivaEsperado),
              formatoCentavosAgenda(widget.totales!.totalEsperado),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else if (widget.resumenIva == ResumenIvaDocumento.mixto) ...[
          Text(l10n.agendaRegistrarEmisionAvisoSinCalculoAutomatico, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
        ],
        RisegTextField(
          label: l10n.agendaDetalleCampoImporteEmitido,
          controller: _importeController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: widget.errorImporteRequerido ? l10n.agendaRegistrarEmisionErrorImporteRequerido : null,
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
