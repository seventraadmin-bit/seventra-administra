import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_ingreso_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../../../finanzas_providers.dart';
import '../../cuentas_financieras/cuentas_financieras_controller.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import '../../planeacion/planeacion_financiera_controller.dart';
import '../../resumen/resumen_financiero_controller.dart';
import '../ingresos_controller.dart';
import '../ingresos_list_screen.dart' show ingresoEstatusLabel, ingresoEstatusTono;
import 'corregir_ingreso_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de un Ingreso (Etapa 4K.1) — datos administrativos,
/// comprobante adjunto e historial (`IngresoEvento`). Cuando el Ingreso
/// es automático (`pagoId != null`) el botón "Cancelar" no aparece:
/// solo se cancela junto con su `Pago` (ver `CancelarIngresoUseCase`).
class IngresoDetalleDialog extends ConsumerStatefulWidget {
  const IngresoDetalleDialog({required this.ingresoId, super.key});

  final String ingresoId;

  @override
  ConsumerState<IngresoDetalleDialog> createState() => _IngresoDetalleDialogState();
}

class _IngresoDetalleDialogState extends ConsumerState<IngresoDetalleDialog> {
  IngresoData? _ingreso;
  List<IngresoEventoData> _eventos = const [];
  List<AttachmentData> _comprobantes = const [];
  String? _folioPago;
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(ingresosControllerProvider.notifier);
    final ingreso = await notifier.obtenerPorId(widget.ingresoId);
    final eventos = await notifier.listarEventos(widget.ingresoId);
    final comprobantes = await notifier.listarComprobantes(widget.ingresoId);

    String? folioPago;
    if (ingreso?.pagoId != null) {
      final pago = await ref.read(pagoRepositoryProvider).obtenerPorId(ingreso!.pagoId!);
      folioPago = pago?.folioPago;
    }

    if (!mounted) return;
    setState(() {
      _ingreso = ingreso;
      _eventos = eventos;
      _comprobantes = comprobantes;
      _folioPago = folioPago;
      _cargando = false;
    });
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoIngreso.values.byName(tipoEvento)) {
      TipoEventoIngreso.registrado => l10n.ingresoDetalleHistorialEventoRegistrado,
      TipoEventoIngreso.corregido => l10n.ingresoDetalleHistorialEventoCorregido,
      TipoEventoIngreso.cancelado => l10n.ingresoDetalleHistorialEventoCancelado,
      TipoEventoIngreso.comprobanteAdjuntado => l10n.ingresoDetalleHistorialEventoComprobanteAdjuntado,
    };
  }

  Future<void> _adjuntarComprobante() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles();
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(ingresosControllerProvider.notifier).adjuntarComprobante(
          ingresoId: widget.ingresoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'application/octet-stream',
        );
    if (!mounted) return;

    switch (resultado) {
      case AdjuntarComprobanteIngresoExitoso():
        await _cargar();
      case AdjuntarComprobanteIngresoNoExiste():
      case AdjuntarComprobanteIngresoErrorInesperado():
        RisegFeedback.showError(context, l10n.ingresoDetalleErrorAdjuntar);
    }
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirIngreso(context, ref, _ingreso!);
    if (actualizo) {
      await _cargar();
      ref.invalidate(ingresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
  }

  Future<void> _cancelar() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    String? errorMotivo;
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarIngresoConfirmacionTitulo,
      confirmLabel: l10n.cancelarIngresoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarIngresoConfirmacionCancelar,
      contentBuilder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cancelarIngresoConfirmacionMensaje, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.corregirIngresoCampoMotivo,
              controller: motivoController,
              autofocus: true,
              errorText: errorMotivo,
              onChanged: (_) => setState(() => errorMotivo = null),
            ),
          ],
        ),
      ),
      onConfirm: () async {
        if (motivoController.text.trim().isEmpty) {
          errorMotivo = l10n.corregirIngresoErrorMotivoRequerido;
          return null;
        }
        return true;
      },
    );
    // Diferido con `addPostFrameCallback` — mismo hallazgo real de
    // `egreso_detalle_dialog.dart` (Etapa 15): el diálogo de
    // confirmación sigue en su transición de cierre cuando este `await`
    // regresa; destruir el controller de forma síncrona producía "A
    // TextEditingController was used after being disposed".
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado =
        await ref.read(ingresosControllerProvider.notifier).cancelar(ingresoId: widget.ingresoId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarIngresoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarIngresoExito);
        await _cargar();
        ref.invalidate(ingresosControllerProvider);
        ref.invalidate(cuentasFinancierasControllerProvider);
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
      case CancelarIngresoNoExiste():
      case CancelarIngresoYaCancelado():
      case CancelarIngresoPagoAutomatico():
      case CancelarIngresoMotivoRequerido():
      case CancelarIngresoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarIngresoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_ingreso == null) {
      content = Text(l10n.ingresosListadoCargaErrorMensaje);
    } else {
      final i = _ingreso!;
      final cancelado = EstatusIngreso.values.byName(i.estatus) == EstatusIngreso.cancelado;
      final automatico = i.pagoId != null;

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.ingresoDetalleCampoFolio, value: i.folioIngreso)),
                RisegStatusBadge(label: ingresoEstatusLabel(l10n, i.estatus), tone: ingresoEstatusTono(i.estatus)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(
              label: l10n.ingresoDetalleCampoOrigen,
              value: automatico ? '${l10n.ingresosOrigenAutomatico} · $_folioPago' : l10n.ingresosOrigenManual,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.ingresoDetalleCampoFecha, value: _formatoFecha.format(i.fecha))),
                Expanded(child: CampoConsulta(label: l10n.ingresoDetalleCampoMonto, value: formatoCentavosPago(i.monto))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.ingresoDetalleCampoConcepto, value: i.concepto),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.ingresoDetalleCampoFormaPago, value: formaPagoLabel(l10n, i.formaPago)),
            if (i.observaciones != null && i.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.ingresoDetalleCampoObservaciones, value: i.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.ingresoDetalleSeccionComprobante,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegButton(
                  label: l10n.ingresoDetalleBotonAdjuntar,
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
                        onPressed: () => ref.read(ingresosControllerProvider.notifier).abrirArchivo(comprobante.path),
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
                          Expanded(
                            child: Text(
                              _eventoLabel(l10n, evento.tipoEvento),
                              style: AppTypography.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            if (!cancelado) ...[
              // Etapa 6 (hallazgo real de auditoría): un Ingreso
              // automático (`pagoId != null`) ya no se corrige aquí
              // directamente — `CorregirIngresoUseCase` lo rechaza
              // (`CorregirIngresoPagoAutomatico`) para nunca
              // desincronizarlo en silencio de su Pago de origen;
              // corregirlo pasa por "Corregir Pago" (mismo criterio ya
              // establecido para el botón "Cancelar").
              if (automatico)
                Text(l10n.ingresoDetalleAvisoAutomaticoSoloDesdePago, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (!automatico)
                    RisegButton(
                      label: l10n.ingresoDetalleBotonCorregir,
                      variant: RisegButtonVariant.secondary,
                      onPressed: _corregir,
                    ),
                  if (!automatico)
                    RisegButton(
                      label: l10n.ingresoDetalleBotonCancelar,
                      variant: RisegButtonVariant.danger,
                      loading: _procesando,
                      onPressed: _cancelar,
                    ),
                ],
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
                    Expanded(
                      child: Text(
                        l10n.ingresoDetalleDialogoTitulo,
                        style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
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
