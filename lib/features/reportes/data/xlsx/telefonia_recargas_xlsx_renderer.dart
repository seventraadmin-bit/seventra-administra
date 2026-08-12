import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'reporte_xlsx_utils.dart';

/// XLSX de recargas del periodo, por Servicio y por Empleado (Etapa
/// 12D) — reutiliza `recargasPorServicio`/`recargasPorEmpleado` ya
/// calculados por `ObtenerResumenTelefoniaUseCase` con atribución
/// histórica (nunca la asignación actual). **Nunca** importa
/// `EquipoTelefonicoRepository` ni ningún dato de credenciales —
/// coherente con la regla dura de Telefonía en Reportes.
class TelefoniaRecargasXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required ResumenTelefoniaReportes resumen}) {
    final excel = crearWorkbookConInfo(contexto);

    void volcar(String nombreHoja, List<RecargaPorClave> filas) {
      final hoja = excel[nombreHoja];
      hoja.appendRow([TextCellValue(nombreHoja), TextCellValue('Total recargado')]);
      for (final fila in filas) {
        hoja.appendRow([TextCellValue(fila.clave), DoubleCellValue(fila.total / 100)]);
      }
    }

    volcar('Por servicio', resumen.recargasPorServicio);
    volcar('Por empleado', resumen.recargasPorEmpleado);

    final resumenHoja = excel['Resumen'];
    resumenHoja.appendRow([TextCellValue('Total recargado en el periodo'), DoubleCellValue(resumen.totalRecargasEnPeriodo / 100)]);
    resumenHoja.appendRow([TextCellValue('Sin atribución'), DoubleCellValue(resumen.recargasSinAtribucion / 100)]);

    return excel.save() ?? const [];
  }
}
