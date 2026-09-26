import 'dart:io';
import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/empresa_repository.dart';

import '../../data/pdf/reporte_general_pdf_renderer.dart';
import '../export/exportar_reporte_resultado.dart';
import '../export/guardar_y_abrir_reporte.dart';
import '../export/reporte_export_context.dart';
import 'obtener_resumen_general_usecase.dart';

/// Orquesta la exportación del PDF ejecutivo del Reporte General
/// (Etapa 12D) — recibe el `ResumenGeneralReportes` ya autorizado y
/// cargado por `ReportesGeneralController`; nunca consulta ningún
/// repositorio de datos financieros/operativos por su cuenta (solo el
/// logotipo de la Empresa, mismo criterio que
/// `GenerarDocumentoResguardoUseCase`).
class ExportarReporteGeneralPdfUseCase {
  ExportarReporteGeneralPdfUseCase(
    this._renderer,
    this._empresaRepository,
    this._attachmentRepository,
    this._attachmentStorage,
    this._reportesDir,
  );

  final ReporteGeneralPdfRenderer _renderer;
  final EmpresaRepository _empresaRepository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required ResumenGeneralReportes resumen,
  }) async {
    try {
      final empresa = await _empresaRepository.obtenerActiva();
      final logoBytes = await _leerBytesAttachment(empresa.logoAttachmentId);

      final bytes = await _renderer.renderizar(
        contexto: contexto,
        resumen: resumen,
        logoBytes: logoBytes,
        empresaNombreComercial: empresa.nombreComercial,
      );

      return guardarYAbrirReporte(
        bytes: bytes,
        nombreBase: contexto.nombreReporte,
        extension: 'pdf',
        generadoEn: contexto.generadoEn,
        reportesDir: _reportesDir,
        attachmentStorage: _attachmentStorage,
      );
    } catch (e) {
      return ExportarReporteErrorInesperado(e.toString());
    }
  }

  Future<Uint8List?> _leerBytesAttachment(String? attachmentId) async {
    if (attachmentId == null) return null;
    final attachment = await _attachmentRepository.obtenerPorId(attachmentId);
    if (attachment == null) return null;
    final file = File(attachment.path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }
}
