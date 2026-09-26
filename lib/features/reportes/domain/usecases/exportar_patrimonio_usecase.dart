import 'dart:io';
import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/empresa_repository.dart';

import '../../data/pdf/reporte_patrimonio_pdf_renderer.dart';
import '../../data/xlsx/patrimonio_xlsx_renderer.dart';
import '../analitica/obtener_analisis_patrimonio_usecase.dart';
import '../export/exportar_reporte_resultado.dart';
import '../export/guardar_y_abrir_reporte.dart';
import '../export/reporte_export_context.dart';

/// Exporta Patrimonio y bajas a Excel.
///
/// Recibe el análisis YA filtrado; no vuelve a consultar. El archivo
/// trae exactamente el universo que la pantalla está mostrando.
class ExportarPatrimonioXlsxUseCase {
  ExportarPatrimonioXlsxUseCase(this._renderer, this._attachmentStorage, this._reportesDir);

  final PatrimonioXlsxRenderer _renderer;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required AnalisisPatrimonio analisis,
  }) async {
    try {
      final bytes = _renderer.generar(contexto: contexto, analisis: analisis);
      return guardarYAbrirReporte(
        bytes: bytes,
        nombreBase: contexto.nombreReporte,
        extension: 'xlsx',
        generadoEn: contexto.generadoEn,
        reportesDir: _reportesDir,
        attachmentStorage: _attachmentStorage,
      );
    } catch (e) {
      return ExportarReporteErrorInesperado(e.toString());
    }
  }
}

/// Exporta el resumen ejecutivo de Patrimonio y bajas a PDF.
///
/// Misma infraestructura que el resto de los PDF del módulo (encabezado
/// con logo de la empresa, pie con paginación) — no se construye un
/// motor nuevo.
class ExportarPatrimonioPdfUseCase {
  ExportarPatrimonioPdfUseCase(
    this._renderer,
    this._empresaRepository,
    this._attachmentRepository,
    this._attachmentStorage,
    this._reportesDir,
  );

  final ReportePatrimonioPdfRenderer _renderer;
  final EmpresaRepository _empresaRepository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required AnalisisPatrimonio analisis,
  }) async {
    try {
      final empresa = await _empresaRepository.obtenerActiva();
      final logoBytes = await _leerBytesAttachment(empresa.logoAttachmentId);

      final bytes = await _renderer.renderizar(
        contexto: contexto,
        analisis: analisis,
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
