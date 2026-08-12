import 'package:riseg_one/core/attachments/attachment_storage.dart';

import '../../data/xlsx/finanzas_egresos_xlsx_renderer.dart';
import '../export/exportar_reporte_resultado.dart';
import '../export/guardar_y_abrir_reporte.dart';
import '../export/reporte_export_context.dart';
import 'clasificar_egresos_por_origen_usecase.dart';

class ExportarFinanzasEgresosXlsxUseCase {
  ExportarFinanzasEgresosXlsxUseCase(this._renderer, this._attachmentStorage, this._reportesDir);

  final FinanzasEgresosXlsxRenderer _renderer;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required List<EgresoConOrigen> detalle,
  }) async {
    try {
      final bytes = _renderer.generar(contexto: contexto, detalle: detalle);
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
