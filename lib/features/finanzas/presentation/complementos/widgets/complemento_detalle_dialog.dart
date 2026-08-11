import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_archivo_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import '../complementos_controller.dart';
import '../complementos_list_screen.dart' show complementoEstatusLabel, complementoEstatusTono;
import 'corregir_complemento_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de un Complemento de pago (Etapa 4J.3) — datos fiscales,
/// archivos PDF/XML adjuntos e historial administrativo propio
/// (`ComplementoPagoEvento`).
class ComplementoDetalleDialog extends ConsumerStatefulWidget {
  const ComplementoDetalleDialog({required this.complementoPagoId, super.key});

  final String complementoPagoId;

  @override
  ConsumerState<ComplementoDetalleDialog> createState() => _ComplementoDetalleDialogState();
}

class _ComplementoDetalleDialogState extends ConsumerState<ComplementoDetalleDialog> {
  ComplementoPagoData? _complemento;
  List<ComplementoPagoEventoData> _eventos = const [];
  List<AttachmentData> _archivos = const [];
  String? _folioPago;
  String? _clienteNombre;
  Map<String, String> _usuariosPorId = const {};
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(complementosControllerProvider.notifier);
    final complemento = await notifier.obtenerPorId(widget.complementoPagoId);
    final eventos = await notifier.listarEventos(widget.complementoPagoId);
    final archivos = await notifier.listarArchivos(widget.complementoPagoId);
    final usuarios = await ref.read(usuarioRepositoryProvider).listar();
    final usuariosPorId = {for (final u in usuarios) u.id: u.nombre};

    String? folioPago;
    String? clienteNombre;
    if (complemento != null) {
      final pago = await ref.read(pagoRepositoryProvider).obtenerPorId(complemento.pagoId);
      if (pago != null) {
        folioPago = pago.folioPago;
        final cliente = await ref.read(clienteRepositoryProvider).obtenerPorId(pago.clienteId);
        clienteNombre = cliente?.nombreComercial;
      }
    }

    if (!mounted) return;
    setState(() {
      _complemento = complemento;
      _eventos = eventos;
      _archivos = archivos;
      _folioPago = folioPago;
      _clienteNombre = clienteNombre;
      _usuariosPorId = usuariosPorId;
      _cargando = false;
    });
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoComplementoPago.values.byName(tipoEvento)) {
      TipoEventoComplementoPago.registrado => l10n.complementoDetalleHistorialEventoRegistrado,
      TipoEventoComplementoPago.corregido => l10n.complementoDetalleHistorialEventoCorregido,
      TipoEventoComplementoPago.cancelado => l10n.complementoDetalleHistorialEventoCancelado,
      TipoEventoComplementoPago.archivoAdjuntado => l10n.complementoDetalleHistorialEventoArchivoAdjuntado,
    };
  }

  String _mimeTypeParaExtension(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'xml' => 'text/xml',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _adjuntar(CategoriaAdjuntoComplementoPago categoria) async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [categoria.name],
    );
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(complementosControllerProvider.notifier).adjuntarArchivo(
          complementoPagoId: widget.complementoPagoId,
          categoria: categoria,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: _mimeTypeParaExtension(archivo.extension),
        );
    if (!mounted) return;

    switch (resultado) {
      case AdjuntarArchivoComplementoPagoExitoso():
        await _cargar();
      case AdjuntarArchivoComplementoPagoNoExiste():
      case AdjuntarArchivoComplementoPagoTipoArchivoInvalido():
      case AdjuntarArchivoComplementoPagoErrorInesperado():
        RisegFeedback.showError(context, l10n.registrarComplementoErrorInesperado);
    }
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirComplemento(context, ref, _complemento!);
    if (actualizo) await _cargar();
  }

  Future<void> _cancelar() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarComplementoConfirmacionTitulo,
      confirmLabel: l10n.cancelarComplementoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarComplementoConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cancelarComplementoConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoMotivoCampo, controller: motivoController, autofocus: true),
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
        await ref.read(complementosControllerProvider.notifier).cancelar(complementoPagoId: widget.complementoPagoId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarComplementoPagoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarComplementoExito);
        await _cargar();
      case CancelarComplementoPagoNoExiste():
      case CancelarComplementoPagoYaCancelado():
      case CancelarComplementoPagoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarComplementoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_complemento == null) {
      content = Text(l10n.complementosListadoCargaErrorMensaje);
    } else {
      final c = _complemento!;
      final cancelado = EstatusComplementoPago.values.byName(c.estatus) == EstatusComplementoPago.cancelado;

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.complementoDetalleCampoPago, value: _folioPago)),
                RisegStatusBadge(label: complementoEstatusLabel(l10n, c.estatus), tone: complementoEstatusTono(c.estatus)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.complementoDetalleCampoCliente, value: _clienteNombre),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.complementoDetalleCampoUuid, value: c.uuid),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.complementoDetalleCampoSerieFiscal, value: c.serieFiscal)),
                Expanded(child: CampoConsulta(label: l10n.complementoDetalleCampoFolioFiscal, value: c.folioFiscal)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.complementoDetalleCampoFechaTimbrado,
                    value: _formatoFecha.format(c.fechaTimbrado),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.complementoDetalleCampoMontoTotal,
                    value: formatoCentavosPago(c.montoTotal),
                  ),
                ),
              ],
            ),
            if (c.observaciones != null && c.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.complementoDetalleCampoObservaciones, value: c.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.complementoDetalleSeccionArchivos,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegButton(
                  label: l10n.complementoDetalleBotonAdjuntarPdf,
                  variant: RisegButtonVariant.ghost,
                  onPressed: () => _adjuntar(CategoriaAdjuntoComplementoPago.pdf),
                ),
                RisegButton(
                  label: l10n.complementoDetalleBotonAdjuntarXml,
                  variant: RisegButtonVariant.ghost,
                  onPressed: () => _adjuntar(CategoriaAdjuntoComplementoPago.xml),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_archivos.isEmpty)
              Text(
                l10n.complementoDetalleArchivosSinArchivos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final archivo in _archivos)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${archivo.originalFileName} · ${l10n.agendaAdjuntoTamano((archivo.sizeBytes / 1024).toStringAsFixed(1))}',
                        ),
                      ),
                      RisegButton(
                        label: l10n.agendaAdjuntoBotonAbrir,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => ref.read(complementosControllerProvider.notifier).abrirArchivo(archivo.path),
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
                      if (evento.actorUsuarioId != null)
                        Text(
                          '${l10n.complementoDetalleHistorialCampoActor}: '
                          '${_usuariosPorId[evento.actorUsuarioId] ?? evento.actorUsuarioId}',
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
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
                    label: l10n.complementoDetalleBotonCorregir,
                    variant: RisegButtonVariant.secondary,
                    onPressed: _corregir,
                  ),
                  RisegButton(
                    label: l10n.complementoDetalleBotonCancelar,
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
                      l10n.complementoDetalleDialogoTitulo,
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
