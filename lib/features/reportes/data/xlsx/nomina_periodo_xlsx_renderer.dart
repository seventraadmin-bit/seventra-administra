import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'reporte_xlsx_utils.dart';

/// XLSX de Nóminas del periodo (Etapa 12D) — una fila por Nómina con
/// todos sus desgloses ya calculados por `ObtenerResumenNominaUseCase`
/// (sin datos bancarios: la fuente es `NominaEmpleadoReporteRow`, nunca
/// el renglón crudo de la tabla). Una Nómina en `borrador` se incluye
/// igual que en pantalla, con su estatus visible en la columna
/// correspondiente — nunca se oculta ni se mezcla sin distinción.
class NominaPeriodoXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required ResumenNominaReportes resumen}) {
    final excel = crearWorkbookConInfo(contexto);

    final hoja = excel['Nominas'];
    hoja.appendRow([
      TextCellValue('Folio'),
      TextCellValue('Periodo'),
      TextCellValue('Estatus'),
      TextCellValue('Empleados incluidos'),
      TextCellValue('Generado'),
      TextCellValue('Pagado'),
      TextCellValue('Pendiente'),
      TextCellValue('Fiscal'),
      TextCellValue('No fiscal'),
      TextCellValue('Bono'),
      TextCellValue('Faltas'),
      TextCellValue('Préstamo'),
      TextCellValue('Tiempo extra'),
      TextCellValue('Otros descuentos'),
      TextCellValue('Pago parcial'),
    ]);

    for (final n in resumen.nominas) {
      hoja.appendRow([
        TextCellValue(n.nomina.folio),
        TextCellValue('${formatearFechaCortaXlsx(n.nomina.fechaInicioPeriodo)} - ${formatearFechaCortaXlsx(n.nomina.fechaFinPeriodo)}'),
        TextCellValue(n.nomina.estatus),
        IntCellValue(n.empleadosIncluidos),
        DoubleCellValue(n.totalGenerado / 100),
        DoubleCellValue(n.totalPagado / 100),
        DoubleCellValue(n.saldoPendiente / 100),
        DoubleCellValue(n.totalFiscal / 100),
        DoubleCellValue(n.totalNoFiscal / 100),
        DoubleCellValue(n.totalBono / 100),
        DoubleCellValue(n.totalFaltas / 100),
        DoubleCellValue(n.totalPrestamo / 100),
        DoubleCellValue(n.totalTiempoExtra / 100),
        DoubleCellValue(n.totalOtrosDescuentos / 100),
        TextCellValue(n.esPagoParcial ? 'Sí' : 'No'),
      ]);
    }

    return excel.save() ?? const [];
  }
}
