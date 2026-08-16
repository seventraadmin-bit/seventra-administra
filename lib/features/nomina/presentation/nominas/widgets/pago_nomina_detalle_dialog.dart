import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/nomina/domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../nominas_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String pagoNominaEstatusLabel(AppLocalizations l10n, String valor) {
  return valor == 'cancelado' ? l10n.pagoNominaEstatusCancelado : l10n.pagoNominaEstatusRegistrado;
}

RisegStatusTone pagoNominaEstatusTono(String valor) {
  return valor == 'cancelado' ? RisegStatusTone.neutral : RisegStatusTone.success;
}

/// Detalle de un `PagoNomina` (Etapa 6D) — empleados cubiertos por este
/// lote, comprobantes, y la acción de cancelarlo (cascada automática:
/// revierte `estatusPago` de cada renglón y cancela el `Egreso`
/// ligado).
///
/// Devuelve `true` (al cerrarse) si algo cambió.
class PagoNominaDetalleDialog extends ConsumerStatefulWidget {
  const PagoNominaDetalleDialog({required this.pagoNominaId, super.key});

  final String pagoNominaId;

  @override
  ConsumerState<PagoNominaDetalleDialog> createState() => _PagoNominaDetalleDialogState();
}

class _PagoNominaDetalleDialogState extends ConsumerState<PagoNominaDetalleDialog> {
  PagoNominaData? _pagoNomina;
  List<AplicacionPagoNominaData> _aplicaciones = const [];
  List<AttachmentData> _comprobantes = const [];
  Map<String, String> _nombresPorRenglon = const {};
  bool _cargando = true;
  bool _procesando = false;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(nominasControllerProvider.notifier);
    final pagoNomina = await notifier.obtenerPagoPorId(widget.pagoNominaId);
    final aplicaciones = await notifier.listarAplicacionesPorPagoNomina(widget.pagoNominaId);
    final comprobantes = await notifier.listarComprobantesPagoNomina(widget.pagoNominaId);

    final nombres = <String, String>{};
    for (final ap in aplicaciones) {
      final renglon = await notifier.obtenerRenglon(ap.nominaEmpleadoId);
      if (renglon != null) nombres[ap.nominaEmpleadoId] = renglon.nombreCompleto;
    }

    if (!mounted) return;
    setState(() {
      _pagoNomina = pagoNomina;
      _aplicaciones = aplicaciones;
      _comprobantes = comprobantes;
      _nombresPorRenglon = nombres;
      _cargando = false;
    });
  }

  Future<void> _adjuntarComprobante() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles();
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(nominasControllerProvider.notifier).adjuntarComprobantePagoNomina(
          pagoNominaId: widget.pagoNominaId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'application/octet-stream',
        );
    if (!mounted) return;

    switch (resultado) {
      case AdjuntarComprobantePagoNominaExitoso():
        await _cargar();
      case AdjuntarComprobantePagoNominaNoExiste():
      case AdjuntarComprobantePagoNominaErrorInesperado():
        RisegFeedback.showError(context, l10n.pagoNominaDetalleErrorInesperado);
    }
  }

  Future<void> _cancelar() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarPagoNominaConfirmacionTitulo,
      confirmLabel: l10n.cancelarPagoNominaConfirmacionConfirmar,
      cancelLabel: l10n.cancelarPagoNominaConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cancelarPagoNominaConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoNominaMotivoCampo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    // Diferido con `addPostFrameCallback` — mismo hallazgo real
    // encontrado en Finanzas (`egreso_detalle_dialog.dart`, Etapa 15):
    // destruir el controller de forma síncrona mientras el diálogo de
    // confirmación sigue en su transición de cierre producía "A
    // TextEditingController was used after being disposed".
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).cancelarPago(pagoNominaId: widget.pagoNominaId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarPagoNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarPagoNominaExito);
        _huboCambios = true;
        await _cargar();
      case CancelarPagoNominaNoExiste():
      case CancelarPagoNominaYaCancelado():
      case CancelarPagoNominaErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarPagoNominaErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else {
      final p = _pagoNomina!;
      final cancelado = p.estatus == 'cancelado';

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.folioPagoNomina, style: AppTypography.heading3.copyWith(color: colors.textPrimary))),
                RisegStatusBadge(label: pagoNominaEstatusLabel(l10n, p.estatus), tone: pagoNominaEstatusTono(p.estatus)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.pagoNominaDetalleCampoFecha, value: _formatoFecha.format(p.fechaPago))),
                Expanded(child: CampoConsulta(label: l10n.pagoNominaDetalleCampoFormaPago, value: formaPagoLabel(l10n, p.formaPago))),
                Expanded(child: CampoConsulta(label: l10n.pagoNominaDetalleCampoMonto, value: formatoCentavosPago(p.montoTotal))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.pagoNominaDetalleCampoReferencia, value: p.referencia)),
                Expanded(child: CampoConsulta(label: l10n.pagoNominaDetalleCampoCuentaOrigen, value: p.cuentaBancariaOrigen)),
              ],
            ),
            if (p.observaciones != null && p.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.pagoNominaDetalleCampoObservaciones, value: p.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(l10n.pagoNominaDetalleSeccionEmpleados, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            for (final ap in _aplicaciones)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text('${_nombresPorRenglon[ap.nominaEmpleadoId] ?? ap.nominaEmpleadoId} · ${formatoCentavosPago(ap.monto)}'),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(l10n.pagoNominaDetalleSeccionComprobantes, style: AppTypography.label.copyWith(color: colors.textMuted)),
                ),
                if (!cancelado)
                  RisegButton(
                    label: l10n.pagoNominaDetalleBotonAdjuntarComprobante,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _adjuntarComprobante,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_comprobantes.isEmpty)
              Text(l10n.pagoNominaDetalleComprobantesVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
            else
              for (final archivo in _comprobantes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(archivo.originalFileName)),
                      RisegButton(
                        label: l10n.agendaAdjuntoBotonAbrir,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => ref.read(nominasControllerProvider.notifier).abrirArchivo(archivo.path),
                      ),
                    ],
                  ),
                ),
            if (!cancelado) ...[
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: RisegButton(
                  label: l10n.pagoNominaDetalleBotonCancelar,
                  variant: RisegButtonVariant.danger,
                  loading: _procesando,
                  onPressed: _cancelar,
                ),
              ),
            ],
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
                    Text(l10n.pagoNominaDetalleDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(_huboCambios)),
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
