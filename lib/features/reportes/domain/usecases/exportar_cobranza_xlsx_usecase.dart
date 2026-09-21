import 'package:riseg_one/core/attachments/attachment_storage.dart';

import '../../data/xlsx/cobranza_xlsx_renderer.dart';
import '../analitica/obtener_analisis_cobranza_usecase.dart';
import '../analitica/obtener_analisis_deuda_usecase.dart';
import '../analitica/obtener_analisis_pagos_usecase.dart';
import '../export/exportar_reporte_resultado.dart';
import '../export/guardar_y_abrir_reporte.dart';
import '../export/reporte_export_context.dart';

/// Exporta la cartera tal como está en pantalla.
///
/// Recibe la lista YA filtrada; no vuelve a consultar. Ese es justo el
/// punto: el Excel tiene que traer el mismo universo que el usuario
/// está mirando, no "todas las cuentas" ni un filtro reinterpretado.
class ExportarCuentasPorCobrarXlsxUseCase {
  ExportarCuentasPorCobrarXlsxUseCase(this._renderer, this._attachmentStorage, this._reportesDir);

  final CuentasPorCobrarXlsxRenderer _renderer;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required List<CuentaPorCobrarProyectada> cuentas,
  }) async {
    try {
      final bytes = _renderer.generar(contexto: contexto, cuentas: cuentas);
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

/// Exporta los Pagos del periodo: una fila por Pago, con las
/// aplicaciones en su propia hoja.
class ExportarPagosXlsxUseCase {
  ExportarPagosXlsxUseCase(this._renderer, this._attachmentStorage, this._reportesDir);

  final PagosXlsxRenderer _renderer;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required List<PagoProyectado> pagos,
  }) async {
    try {
      final bytes = _renderer.generar(contexto: contexto, pagos: pagos);
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

/// Exporta deudas y sus movimientos del periodo.
class ExportarDeudasXlsxUseCase {
  ExportarDeudasXlsxUseCase(this._renderer, this._attachmentStorage, this._reportesDir);

  final DeudasXlsxRenderer _renderer;
  final AttachmentStorage _attachmentStorage;
  final String _reportesDir;

  Future<ExportarReporteResultado> ejecutar({
    required ReporteExportContext contexto,
    required AnalisisDeuda analisis,
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
