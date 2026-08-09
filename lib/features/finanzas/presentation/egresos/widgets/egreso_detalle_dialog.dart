import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import '../egresos_controller.dart';
import '../egresos_list_screen.dart' show egresoEstatusLabel, egresoEstatusTono;
import 'corregir_egreso_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de un Egreso (Etapa 4K.1) — datos administrativos,
/// comprobante adjunto e historial (`EgresoEvento`).
class EgresoDetalleDialog extends ConsumerStatefulWidget {
  const EgresoDetalleDialog({required this.egresoId, super.key});

  final String egresoId;

  @override
  ConsumerState<EgresoDetalleDialog> createState() => _EgresoDetalleDialogState();
}

class _EgresoDetalleDialogState extends ConsumerState<EgresoDetalleDialog> {
  EgresoData? _egreso;
  List<EgresoEventoData> _eventos = const [];
  List<AttachmentData> _comprobantes = const [];
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(egresosControllerProvider.notifier);
    final egreso = await notifier.obtenerPorId(widget.egresoId);
    final eventos = await notifier.listarEventos(widget.egresoId);
    final comprobantes = await notifier.listarComprobantes(widget.egresoId);

    if (!mounted) return;
    setState(() {
      _egreso = egreso;
      _eventos = eventos;
      _comprobantes = comprobantes;
      _cargando = false;
    });
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoEgreso.values.byName(tipoEvento)) {
      TipoEventoEgreso.registrado => l10n.egresoDetalleHistorialEventoRegistrado,
      TipoEventoEgreso.corregido => l10n.egresoDetalleHistorialEventoCorregido,
      TipoEventoEgreso.cancelado => l10n.egresoDetalleHistorialEventoCancelado,
      TipoEventoEgreso.comprobanteAdjuntado => l10n.egresoDetalleHistorialEventoComprobanteAdjuntado,
    };
  }

  Future<void> _adjuntarComprobante() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles();
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(egresosControllerProvider.notifier).adjuntarComprobante(
          egresoId: widget.egresoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'application/octet-stream',
        );
    if (!mounted) return;

    switch (resultado) {
      case AdjuntarComprobanteEgresoExitoso():
        await _cargar();
      case AdjuntarComprobanteEgresoNoExiste():
      case AdjuntarComprobanteEgresoErrorInesperado():
        RisegFeedback.showError(context, l10n.egresoDetalleErrorAdjuntar);
    }
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirEgreso(context, ref, _egreso!);
    if (actualizo) await _cargar();
  }

  Future<void> _cancelar() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarEgresoConfirmacionTitulo,
      confirmLabel: l10n.cancelarEgresoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarEgresoConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cancelarEgresoConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.corregirEgresoCampoMotivo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) {
      motivoController.dispose();
      return;
    }
    final motivo = motivoController.text.trim();
    motivoController.dispose();
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado =
        await ref.read(egresosControllerProvider.notifier).cancelar(egresoId: widget.egresoId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarEgresoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarEgresoExito);
        await _cargar();
      case CancelarEgresoNoExiste():
      case CancelarEgresoYaCancelado():
      case CancelarEgresoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarEgresoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_egreso == null) {
      content = Text(l10n.egresosListadoCargaErrorMensaje);
    } else {
      final e = _egreso!;
      final cancelado = EstatusEgreso.values.byName(e.estatus) == EstatusEgreso.cancelado;

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoFolio, value: e.folioEgreso)),
                RisegStatusBadge(label: egresoEstatusLabel(l10n, e.estatus), tone: egresoEstatusTono(e.estatus)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoFecha, value: _formatoFecha.format(e.fecha))),
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoMonto, value: formatoCentavosPago(e.monto))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.egresoDetalleCampoConcepto, value: e.concepto),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoBeneficiario, value: e.beneficiario)),
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoFormaPago, value: formaPagoLabel(l10n, e.formaPago))),
              ],
            ),
            if (e.observaciones != null && e.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.egresoDetalleCampoObservaciones, value: e.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.egresoDetalleSeccionComprobante,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegButton(
                  label: l10n.egresoDetalleBotonAdjuntar,
                  variant: RisegButtonVariant.ghost,
                  onPressed: _adjuntarComprobante,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_comprobantes.isEmpty)
              Text(
                l10n.complementoDetalleArchivosSinArchivos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final comprobante in _comprobantes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${comprobante.originalFileName} · ${l10n.agendaAdjuntoTamano((comprobante.sizeBytes / 1024).toStringAsFixed(1))}',
                        ),
                      ),
                      RisegButton(
                        label: l10n.agendaAdjuntoBotonAbrir,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => ref.read(egresosControllerProvider.notifier).abrirArchivo(comprobante.path),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.complementoDetalleSeccionHistorial,
              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_eventos.isEmpty)
              Text(
                l10n.complementoDetalleHistorialSinEventos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final evento in _eventos)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatoFechaHora.format(evento.fechaHora),
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(_eventoLabel(l10n, evento.tipoEvento), style: AppTypography.label),
                        ],
                      ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            if (!cancelado)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  RisegButton(
                    label: l10n.egresoDetalleBotonCorregir,
                    variant: RisegButtonVariant.secondary,
                    onPressed: _corregir,
                  ),
                  RisegButton(
                    label: l10n.egresoDetalleBotonCancelar,
                    variant: RisegButtonVariant.danger,
                    loading: _procesando,
                    onPressed: _cancelar,
                  ),
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
                    Text(
                      l10n.egresoDetalleDialogoTitulo,
                      style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
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
