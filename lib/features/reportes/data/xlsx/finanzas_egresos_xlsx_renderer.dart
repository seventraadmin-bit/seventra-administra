import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'reporte_xlsx_utils.dart';

const _origenLabel = {
  OrigenEgreso.compra: 'Compra',
  OrigenEgreso.nomina: 'Nómina',
  OrigenEgreso.tiempoExtra: 'Tiempo extra',
  OrigenEgreso.deuda: 'Pago de deuda',
  OrigenEgreso.descuentoProgramado: 'Préstamo a empleado',
  OrigenEgreso.vehiculo: 'Vehículo',
  OrigenEgreso.manual: 'Manual',
};

/// XLSX de Egresos con origen (Etapa 12D) — reutiliza exactamente
/// `egresosPorOrigen.detalle` ya cargado por `ReportesFinanzasController`,
/// sin ninguna consulta nueva. Útil para conciliar egresos con
/// proveedores/nómina.
class FinanzasEgresosXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required List<EgresoConOrigen> detalle}) {
    final excel = crearWorkbookConInfo(contexto);

    final hoja = excel['Egresos'];
    hoja.appendRow([
      TextCellValue('Folio'),
      TextCellValue('Fecha'),
      TextCellValue('Concepto'),
      TextCellValue('Beneficiario'),
      TextCellValue('Forma de pago'),
      TextCellValue('Origen'),
      TextCellValue('Monto'),
    ]);
    for (final fila in detalle) {
      hoja.appendRow([
        TextCellValue(fila.egreso.folioEgreso),
        TextCellValue(formatearFechaCortaXlsx(fila.egreso.fecha)),
        TextCellValue(fila.egreso.concepto),
        TextCellValue(fila.egreso.beneficiario ?? '—'),
        TextCellValue(fila.egreso.formaPago),
        TextCellValue(_origenLabel[fila.origen] ?? fila.origen.name),
        DoubleCellValue(fila.egreso.monto / 100),
      ]);
    }

    return excel.save() ?? const [];
  }
}
