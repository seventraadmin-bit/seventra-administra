import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_detalle.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/resumen_iva_documento_por_emitir.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../../../organizacion_providers.dart';
import '../agenda_controller.dart';
import '../agenda_list_screen.dart' show formatoCentavosAgenda;

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Detalle de un `DocumentoPorEmitir` (Etapa 4I.1) — expediente completo
/// de solo consulta salvo la máquina de estados de 4 estados. El ajuste
/// manual se muestra de solo lectura: su interfaz de captura completa
/// se difiere a la Etapa 4I.2 (autorización explícita de Marlon).
class AgendaDetalleDialog extends ConsumerStatefulWidget {
  const AgendaDetalleDialog({required this.documentoPorEmitirId, super.key});

  final String documentoPorEmitirId;

  @override
  ConsumerState<AgendaDetalleDialog> createState() => _AgendaDetalleDialogState();
}

class _AgendaDetalleDialogState extends ConsumerState<AgendaDetalleDialog> {
  DocumentoPorEmitirDetalle? _detalle;
  bool _cargando = true;
  bool _procesando = false;
  final Map<String, String> _nombresServicio = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final detalle = await ref.read(agendaControllerProvider.notifier).obtenerDetalle(widget.documentoPorEmitirId);
    if (!mounted) return;

    if (detalle != null) {
      for (final servicioId in detalle.servicioIds) {
        if (_nombresServicio.containsKey(servicioId)) continue;
        final servicio = await ref.read(servicioRepositoryProvider).obtenerPorId(servicioId);
        if (servicio != null) _nombresServicio[servicioId] = '${servicio.codigo} — ${servicio.nombre}';
      }
    }

    if (!mounted) return;
    setState(() {
      _detalle = detalle;
      _cargando = false;
    });
  }

  String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
    return switch (TipoDocumentoCobro.values.byName(valor)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  String _agrupacionLabel(AppLocalizations l10n, String valor) {
    return switch (AgrupacionCobro.values.byName(valor)) {
      AgrupacionCobro.porServicio => l10n.servicioCobroAgrupacionPorServicio,
      AgrupacionCobro.porEntidadFiscal => l10n.servicioCobroAgrupacionPorEntidadFiscal,
      AgrupacionCobro.porCliente => l10n.servicioCobroAgrupacionPorCliente,
      AgrupacionCobro.manual => l10n.servicioCobroAgrupacionManual,
    };
  }

  String _metodoLabel(AppLocalizations l10n, String valor) {
    return switch (MetodoPagoCobro.values.byName(valor)) {
      MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
      MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
      MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
    };
  }

  String _tratamientoIvaLabel(AppLocalizations l10n, String valor) {
    return switch (TratamientoIva.values.byName(valor)) {
      TratamientoIva.masIva => l10n.servicioComercialTratamientoIvaMasIva,
      TratamientoIva.ivaIncluido => l10n.servicioComercialTratamientoIvaIvaIncluido,
      TratamientoIva.noAplica => l10n.servicioComercialTratamientoIvaNoAplica,
    };
  }

  String _resumenIvaLabel(AppLocalizations l10n, ResumenIvaDocumento resumen) {
    return switch (resumen) {
      ResumenIvaDocumento.masIva => l10n.agendaDetalleResumenIvaMasIva,
      ResumenIvaDocumento.ivaIncluido => l10n.agendaDetalleResumenIvaIvaIncluido,
      ResumenIvaDocumento.noAplica => l10n.agendaDetalleResumenIvaNoAplica,
      ResumenIvaDocumento.mixto => l10n.agendaDetalleResumenIvaMixto,
    };
  }

  String _estatusLabel(AppLocalizations l10n, String valor) {
    return switch (EstatusDocumentoPorEmitir.values.byName(valor)) {
      EstatusDocumentoPorEmitir.pendiente => l10n.agendaEstatusPendiente,
      EstatusDocumentoPorEmitir.enPreparacion => l10n.agendaEstatusEnPreparacion,
      EstatusDocumentoPorEmitir.cancelado => l10n.agendaEstatusCancelado,
      EstatusDocumentoPorEmitir.noRequerido => l10n.agendaEstatusNoRequerido,
    };
  }

  Future<String?> _pedirMotivo(AppLocalizations l10n) async {
    final controller = TextEditingController();
    final motivo = await RisegDialog.showForm<String>(
      context: context,
      title: l10n.agendaDetalleMotivoDialogoTitulo,
      confirmLabel: l10n.agendaDetalleMotivoBotonConfirmar,
      cancelLabel: l10n.agendaDetalleMotivoBotonCancelar,
      contentBuilder: (_) => RisegTextField(
        label: l10n.agendaDetalleMotivoCampo,
        controller: controller,
        autofocus: true,
      ),
      onConfirm: () async => controller.text,
    );
    controller.dispose();
    return motivo;
  }

  Future<void> _cambiarEstatus(EstatusDocumentoPorEmitir nuevo, {bool requiereMotivo = false}) async {
    final l10n = AppLocalizations.of(context)!;
    String? motivo;
    if (requiereMotivo) {
      motivo = await _pedirMotivo(l10n);
      if (motivo == null || motivo.trim().isEmpty) return;
    }
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(agendaControllerProvider.notifier).cambiarEstatus(
          documentoPorEmitirId: widget.documentoPorEmitirId,
          nuevo: nuevo,
          motivo: motivo,
        );
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CambiarEstatusDocumentoPorEmitirExitoso():
        RisegFeedback.showSuccess(context, l10n.agendaDetalleCambiarEstatusExito);
        await _cargar();
      case CambiarEstatusDocumentoPorEmitirMotivoRequerido():
        RisegFeedback.showError(context, l10n.agendaDetalleCambiarEstatusErrorMotivoRequerido);
      case CambiarEstatusDocumentoPorEmitirTransicionInvalida():
      case CambiarEstatusDocumentoPorEmitirNoExiste():
      case CambiarEstatusDocumentoPorEmitirErrorInesperado():
      case null:
        RisegFeedback.showError(context, l10n.agendaDetalleCambiarEstatusErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_detalle == null) {
      content = Text(l10n.agendaListadoCargaErrorMensaje);
    } else {
      final d = _detalle!.documento;
      final estatusActual = EstatusDocumentoPorEmitir.values.byName(d.estatus);

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(label: l10n.agendaDetalleCampoCodigo, value: d.codigo),
                ),
                RisegStatusBadge(
                  label: _estatusLabel(l10n, d.estatus),
                  tone: switch (estatusActual) {
                    EstatusDocumentoPorEmitir.pendiente => RisegStatusTone.info,
                    EstatusDocumentoPorEmitir.enPreparacion => RisegStatusTone.warning,
                    EstatusDocumentoPorEmitir.cancelado => RisegStatusTone.neutral,
                    EstatusDocumentoPorEmitir.noRequerido => RisegStatusTone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoTipoDocumento, value: _tipoDocumentoLabel(l10n, d.tipoDocumento))),
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoAgrupacion, value: _agrupacionLabel(l10n, d.agrupacion))),
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoMetodo, value: _metodoLabel(l10n, d.metodo))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(
              label: l10n.agendaDetalleCampoPeriodo,
              value: '${_formatoFecha.format(d.periodoInicio)} - ${_formatoFecha.format(d.periodoFin)}',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.agendaDetalleCampoFechaEmision,
                    value: d.fechaEmisionProgramada == null
                        ? l10n.agendaFechaSinCalcular
                        : _formatoFecha.format(d.fechaEmisionProgramada!),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.agendaDetalleCampoFechaProcesamiento,
                    value: d.fechaProcesamientoProgramada == null
                        ? null
                        : _formatoFecha.format(d.fechaProcesamientoProgramada!),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.agendaDetalleCampoFechaPago,
                    value: d.fechaPagoEsperadoProgramada == null
                        ? l10n.agendaFechaSinCalcular
                        : _formatoFecha.format(d.fechaPagoEsperadoProgramada!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoImporteBase, value: formatoCentavosAgenda(d.importeBaseEsperado))),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.agendaDetalleCampoAjusteManual,
                    value: d.ajusteManual == null ? null : formatoCentavosAgenda(d.ajusteManual!),
                  ),
                ),
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoImporteFinal, value: formatoCentavosAgenda(d.importeFinalEsperado))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.agendaDetalleCampoResumenIva, value: _resumenIvaLabel(l10n, _detalle!.resumenIva)),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.agendaDetalleCampoServicios, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xxs),
            for (final servicioId in _detalle!.servicioIds)
              Text(_nombresServicio[servicioId] ?? servicioId, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.agendaDetalleSeccionLineas, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            RisegTableBase<DocumentoPorEmitirLineaData>(
              rows: _detalle!.lineas,
              columns: [
                RisegColumn(label: l10n.agendaDetalleLineaColumnaPuesto, cellBuilder: (l) => Text(l.puestoNombre)),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaModalidad,
                  cellBuilder: (l) => Text(l.modalidadTurnoNombre),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaCantidad,
                  width: 70,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text('${l.cantidadElementos}'),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaPrecio,
                  width: 100,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text(formatoCentavosAgenda(l.precioUnitario)),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaIva,
                  width: 100,
                  cellBuilder: (l) => Text(_tratamientoIvaLabel(l10n, l.tratamientoIva)),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaDias,
                  width: 60,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text('${l.diasAplicables}'),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaSubtotal,
                  width: 100,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text(formatoCentavosAgenda(l.subtotalProporcional)),
                ),
              ],
            ),
            if (_detalle!.correos.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              CampoConsulta(label: l10n.agendaDetalleCampoCorreos, value: _detalle!.correos.join(', ')),
            ],
            if (d.observaciones != null && d.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              CampoConsulta(label: l10n.agendaDetalleCampoObservaciones, value: d.observaciones),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (estatusActual == EstatusDocumentoPorEmitir.pendiente)
                  RisegButton(
                    label: l10n.agendaDetalleBotonMarcarEnPreparacion,
                    variant: RisegButtonVariant.secondary,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.enPreparacion),
                  ),
                if (estatusActual == EstatusDocumentoPorEmitir.pendiente ||
                    estatusActual == EstatusDocumentoPorEmitir.enPreparacion) ...[
                  RisegButton(
                    label: l10n.agendaDetalleBotonCancelar,
                    variant: RisegButtonVariant.danger,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.cancelado, requiereMotivo: true),
                  ),
                  RisegButton(
                    label: l10n.agendaDetalleBotonMarcarNoRequerido,
                    variant: RisegButtonVariant.ghost,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.noRequerido, requiereMotivo: true),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.agendaDetalleDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
