import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/attachment_table.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/adjuntar_archivo_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/reemplazar_archivo_documento_por_emitir_usecase.dart';

import '../agenda_controller.dart';

String _mimeTypeParaExtension(String? extension) {
  return switch (extension?.toLowerCase()) {
    'pdf' => 'application/pdf',
    'xml' => 'text/xml',
    _ => 'application/octet-stream',
  };
}

List<String>? _extensionesPermitidas(CategoriaAdjuntoDocumentoPorEmitir categoria) {
  return switch (categoria) {
    CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf ||
    CategoriaAdjuntoDocumentoPorEmitir.reciboPdf =>
      ['pdf'],
    CategoriaAdjuntoDocumentoPorEmitir.cfdiXml => ['xml'],
    CategoriaAdjuntoDocumentoPorEmitir.otroSoporte => null,
  };
}

String _categoriaLabel(AppLocalizations l10n, CategoriaAdjuntoDocumentoPorEmitir categoria) {
  return switch (categoria) {
    CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf => l10n.agendaAdjuntoCategoriaCfdiPdf,
    CategoriaAdjuntoDocumentoPorEmitir.cfdiXml => l10n.agendaAdjuntoCategoriaCfdiXml,
    CategoriaAdjuntoDocumentoPorEmitir.reciboPdf => l10n.agendaAdjuntoCategoriaReciboPdf,
    CategoriaAdjuntoDocumentoPorEmitir.otroSoporte => l10n.agendaAdjuntoCategoriaOtroSoporte,
  };
}

List<CategoriaAdjuntoDocumentoPorEmitir> _categoriasParaTipoDocumento(String tipoDocumento) {
  final esCfdi = TipoDocumentoCobro.values.byName(tipoDocumento) == TipoDocumentoCobro.cfdi;
  return esCfdi
      ? const [
          CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf,
          CategoriaAdjuntoDocumentoPorEmitir.cfdiXml,
          CategoriaAdjuntoDocumentoPorEmitir.otroSoporte,
        ]
      : const [
          CategoriaAdjuntoDocumentoPorEmitir.reciboPdf,
          CategoriaAdjuntoDocumentoPorEmitir.otroSoporte,
        ];
}

/// Sección "Adjuntos" del detalle de un `DocumentoPorEmitir` (Etapa
/// 4I.2.2) — un bloque por categoría relevante al `tipoDocumento`
/// (CFDI: PDF/XML/otro; recibo: PDF/otro), cada uno con sus archivos
/// activos (Resolución 6 de Marlon: la consulta normal nunca muestra
/// versiones archivadas), botón "Agregar" y "Reemplazar" por archivo.
class AgendaAdjuntosSection extends ConsumerStatefulWidget {
  const AgendaAdjuntosSection({required this.documento, super.key});

  final DocumentoPorEmitirData documento;

  @override
  ConsumerState<AgendaAdjuntosSection> createState() => _AgendaAdjuntosSectionState();
}

class _AgendaAdjuntosSectionState extends ConsumerState<AgendaAdjuntosSection> {
  Map<CategoriaAdjuntoDocumentoPorEmitir, List<AttachmentData>> _porCategoria = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(agendaControllerProvider.notifier);
    final resultado = <CategoriaAdjuntoDocumentoPorEmitir, List<AttachmentData>>{};
    for (final categoria in _categoriasParaTipoDocumento(widget.documento.tipoDocumento)) {
      resultado[categoria] = await notifier.listarAdjuntosActivos(widget.documento.id, categoria: categoria.name);
    }
    if (!mounted) return;
    setState(() {
      _porCategoria = resultado;
      _cargando = false;
    });
  }

  Future<void> _agregar(CategoriaAdjuntoDocumentoPorEmitir categoria) async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles(
      type: _extensionesPermitidas(categoria) == null ? FileType.any : FileType.custom,
      allowedExtensions: _extensionesPermitidas(categoria),
    );
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(agendaControllerProvider.notifier).adjuntarArchivo(
          documentoPorEmitirId: widget.documento.id,
          categoria: categoria,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: _mimeTypeParaExtension(archivo.extension),
        );
    if (!mounted) return;
    _mostrarResultadoAdjuntar(l10n, resultado);
    if (resultado is AdjuntarArchivoDocumentoPorEmitirExitoso) await _cargar();
  }

  Future<void> _reemplazar(CategoriaAdjuntoDocumentoPorEmitir categoria, AttachmentData anterior) async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.agendaReemplazarArchivoDialogoTitulo,
      confirmLabel: l10n.agendaReemplazarArchivoBotonConfirmar,
      cancelLabel: l10n.agendaReemplazarArchivoBotonCancelar,
      contentBuilder: (_) => RisegTextField(
        label: l10n.agendaReemplazarArchivoCampoMotivo,
        controller: motivoController,
        autofocus: true,
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) {
      motivoController.dispose();
      return;
    }
    if (!context.mounted) return;

    final seleccion = await FilePicker.platform.pickFiles(
      type: _extensionesPermitidas(categoria) == null ? FileType.any : FileType.custom,
      allowedExtensions: _extensionesPermitidas(categoria),
    );
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) {
      motivoController.dispose();
      return;
    }
    if (!mounted) return;

    final resultado = await ref.read(agendaControllerProvider.notifier).reemplazarArchivo(
          documentoPorEmitirId: widget.documento.id,
          attachmentAnteriorId: anterior.id,
          categoria: categoria,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: _mimeTypeParaExtension(archivo.extension),
          motivo: motivoController.text.trim().isEmpty ? null : motivoController.text.trim(),
        );
    motivoController.dispose();
    if (!mounted) return;
    _mostrarResultadoReemplazar(l10n, resultado);
    if (resultado is ReemplazarArchivoDocumentoPorEmitirExitoso) await _cargar();
  }

  void _mostrarResultadoAdjuntar(AppLocalizations l10n, AdjuntarArchivoDocumentoPorEmitirResultado resultado) {
    switch (resultado) {
      case AdjuntarArchivoDocumentoPorEmitirExitoso():
        RisegFeedback.showSuccess(context, l10n.agendaAdjuntoExitoAgregado);
      case AdjuntarArchivoDocumentoPorEmitirDocumentoNoExiste():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorDocumentoNoExiste);
      case AdjuntarArchivoDocumentoPorEmitirCategoriaIncompatible():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorCategoriaIncompatible);
      case AdjuntarArchivoDocumentoPorEmitirTipoArchivoInvalido():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorTipoArchivoInvalido);
      case AdjuntarArchivoDocumentoPorEmitirErrorInesperado():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorInesperado);
    }
  }

  void _mostrarResultadoReemplazar(AppLocalizations l10n, ReemplazarArchivoDocumentoPorEmitirResultado resultado) {
    switch (resultado) {
      case ReemplazarArchivoDocumentoPorEmitirExitoso():
        RisegFeedback.showSuccess(context, l10n.agendaAdjuntoExitoReemplazado);
      case ReemplazarArchivoDocumentoPorEmitirDocumentoNoExiste():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorDocumentoNoExiste);
      case ReemplazarArchivoDocumentoPorEmitirArchivoAnteriorNoExiste():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorArchivoAnteriorNoExiste);
      case ReemplazarArchivoDocumentoPorEmitirArchivoYaArchivado():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorArchivoYaArchivado);
      case ReemplazarArchivoDocumentoPorEmitirCategoriaIncompatible():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorCategoriaIncompatible);
      case ReemplazarArchivoDocumentoPorEmitirTipoArchivoInvalido():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorTipoArchivoInvalido);
      case ReemplazarArchivoDocumentoPorEmitirErrorInesperado():
        RisegFeedback.showError(context, l10n.agendaAdjuntoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.agendaDetalleSeccionAdjuntos, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        for (final entry in _porCategoria.entries) ...[
          Row(
            children: [
              Expanded(child: Text(_categoriaLabel(l10n, entry.key), style: AppTypography.label)),
              RisegButton(
                label: l10n.agendaAdjuntoBotonAgregar,
                variant: RisegButtonVariant.ghost,
                onPressed: () => _agregar(entry.key),
              ),
            ],
          ),
          if (entry.value.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(l10n.agendaAdjuntoSinArchivos, style: AppTypography.caption.copyWith(color: colors.textMuted)),
            )
          else
            for (final adjunto in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${adjunto.originalFileName} · ${l10n.agendaAdjuntoTamano((adjunto.sizeBytes / 1024).toStringAsFixed(1))}',
                      ),
                    ),
                    RisegButton(
                      label: l10n.agendaAdjuntoBotonAbrir,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () => ref.read(agendaControllerProvider.notifier).abrirArchivo(adjunto.path),
                    ),
                    RisegButton(
                      label: l10n.agendaAdjuntoBotonReemplazar,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () => _reemplazar(entry.key, adjunto),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
