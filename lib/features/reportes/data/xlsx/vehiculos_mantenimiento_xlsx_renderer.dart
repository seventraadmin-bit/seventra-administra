import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/obtener_resumen_vehiculos_usecase.dart';
import 'reporte_xlsx_utils.dart';

/// XLSX de mantenimientos/incidencias del periodo (Etapa 12D) — usa
/// `detalleMantenimientos`, agregado en `ObtenerResumenVehiculosUseCase`
/// (Etapa 12D) a partir de filas que el use case ya recorría para sumar
/// los totales del resumen; no es una consulta nueva.
class VehiculosMantenimientoXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required ResumenVehiculosReportes resumen}) {
    final excel = crearWorkbookConInfo(contexto);

    final hoja = excel['Mantenimientos'];
    hoja.appendRow([
      TextCellValue('Vehículo'),
      TextCellValue('Fecha'),
      TextCellValue('Tipo'),
      TextCellValue('Descripción'),
      TextCellValue('Taller / proveedor'),
      TextCellValue('Costo'),
    ]);
    for (final m in resumen.detalleMantenimientos) {
      hoja.appendRow([
        TextCellValue(m.vehiculoLabel),
        TextCellValue(formatearFechaCortaXlsx(m.registro.fecha)),
        TextCellValue(m.registro.tipo),
        TextCellValue(m.registro.descripcion),
        TextCellValue(m.registro.tallerProveedor ?? '—'),
        DoubleCellValue((m.registro.costo ?? 0) / 100),
      ]);
    }

    return excel.save() ?? const [];
  }
}
