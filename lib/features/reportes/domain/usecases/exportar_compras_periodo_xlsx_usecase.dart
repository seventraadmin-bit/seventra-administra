import 'package:riseg_one/core/attachments/attachment_storage.dart';

import '../../data/xlsx/compras_periodo_xlsx_renderer.dart';
import '../export/exportar_reporte_resultado.dart';
import '../export/guardar_y_abrir_reporte.dart';
import '../export/reporte_export_context.dart';
import 'obtener_resumen_compras_usecase.dart';

class ExportarComprasPeriodoXlsxUseCase {
  ExportarComprasPeriodoXlsxUseCase(this._renderer, this._attachmentStorage, this._reportesDir);

  final ComprasPeriodoXlsxRenderer _renderer;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required ResumenComprasReportes resumen,
  }) async {
    try {
      final bytes = _renderer.generar(contexto: contexto, resumen: resumen);
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
