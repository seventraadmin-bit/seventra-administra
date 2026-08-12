import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';

String formatearFechaCortaXlsx(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

String formatearPeriodoXlsx(DateTime? inicio, DateTime? fin) {
  if (inicio == null && fin == null) return 'Sin periodo definido';
  if (inicio == null) return 'Hasta ${formatearFechaCortaXlsx(fin!)}';
  if (fin == null) return 'Desde ${formatearFechaCortaXlsx(inicio)}';
  return '${formatearFechaCortaXlsx(inicio)} – ${formatearFechaCortaXlsx(fin)}';
}

/// Arma un workbook nuevo con una hoja "Info" (nombre del reporte,
/// periodo, quién y cuándo lo generó) — mismo contenido de contexto
/// que el encabezado de los PDF, para que un XLSX exportado nunca
/// pierda esa trazabilidad solo por no llevar branding visual.
/// Reutiliza la hoja por defecto de `Excel.createExcel()` en vez de
/// crear una y borrar la otra.
Excel crearWorkbookConInfo(ReporteExportContext contexto) {
  final excel = Excel.createExcel();
  final hojaDefecto = excel.getDefaultSheet()!;
  excel.rename(hojaDefecto, 'Info');

  final info = excel['Info'];
  info.appendRow([TextCellValue('Reporte'), TextCellValue(contexto.nombreReporte)]);
  info.appendRow([TextCellValue('Periodo'), TextCellValue(formatearPeriodoXlsx(contexto.rangoInicio, contexto.rangoFin))]);
  info.appendRow([TextCellValue('Generado por'), TextCellValue(contexto.generadoPor)]);
  info.appendRow([TextCellValue('Generado en'), TextCellValue(formatearFechaCortaXlsx(contexto.generadoEn))]);

  return excel;
}
