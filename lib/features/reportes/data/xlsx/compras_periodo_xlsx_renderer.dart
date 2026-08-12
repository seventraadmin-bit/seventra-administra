import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/obtener_resumen_compras_usecase.dart';
import 'reporte_xlsx_utils.dart';

/// XLSX de Compras del periodo (Etapa 12D) — tres desgloses ya
/// calculados por `ObtenerResumenComprasUseCase` (proveedor, forma de
/// pago, artículo/concepto), para conciliar con proveedores. Compras
/// canceladas quedan fuera de estos desgloses por diseño (mismo
/// criterio que `totalCompradoEnRango`) — nunca se mezclan aquí.
class ComprasPeriodoXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required ResumenComprasReportes resumen}) {
    final excel = crearWorkbookConInfo(contexto);

    void volcarClave(String nombreHoja, List<TotalPorClave> filas) {
      final hoja = excel[nombreHoja];
      hoja.appendRow([TextCellValue(nombreHoja), TextCellValue('Total')]);
      for (final fila in filas) {
        hoja.appendRow([TextCellValue(fila.clave), DoubleCellValue(fila.total / 100)]);
      }
    }

    volcarClave('Por proveedor', resumen.porProveedor);
    volcarClave('Por forma de pago', resumen.porFormaPago);
    volcarClave('Por articulo o concepto', resumen.porArticuloOConcepto);

    return excel.save() ?? const [];
  }
}
