import 'package:excel/excel.dart';

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/obtener_resumen_personal_usecase.dart';
import 'reporte_xlsx_utils.dart';

/// XLSX de eventos de Personal del periodo (Etapa 12D) — una hoja por
/// tipo de evento (Altas, Reingresos, Bajas, Próximos aniversarios,
/// Alertas de recontratación), todas ya cargadas por
/// `ReportesPersonalNominaController` vía `EmpleadoReporteRow` (sin
/// CURP/RFC/NSS/bancarios/sueldo — mismo allow-list que la pantalla).
/// Los conteos por estatus/servicio (mapas pequeños) se descartan a
/// propósito: ya están en pantalla como tarjetas, sin valor de tabla.
class PersonalEventosXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required ResumenPersonalReportes resumen}) {
    final excel = crearWorkbookConInfo(contexto);

    final altas = excel['Altas'];
    altas.appendRow([TextCellValue('No. empleado'), TextCellValue('Nombre'), TextCellValue('Fecha de ingreso')]);
    for (final e in resumen.altasEnPeriodo) {
      altas.appendRow([IntCellValue(e.numeroEmpleado), TextCellValue(e.nombreCompleto), TextCellValue(formatearFechaCortaXlsx(e.fechaIngreso))]);
    }

    final reingresos = excel['Reingresos'];
    reingresos.appendRow([TextCellValue('No. empleado'), TextCellValue('Nombre'), TextCellValue('Fecha de reingreso')]);
    for (final e in resumen.reingresosEnPeriodo) {
      reingresos.appendRow([IntCellValue(e.numeroEmpleado), TextCellValue(e.nombreCompleto), TextCellValue(formatearFechaCortaXlsx(e.fechaIngreso))]);
    }

    final bajas = excel['Bajas'];
    bajas.appendRow([TextCellValue('Nombre'), TextCellValue('Fecha de baja'), TextCellValue('Motivo')]);
    for (final b in resumen.bajasEnPeriodo) {
      bajas.appendRow([TextCellValue(b.nombreCompleto), TextCellValue(formatearFechaCortaXlsx(b.fechaBaja)), TextCellValue(b.motivoBaja.name)]);
    }

    final aniversarios = excel['Proximos aniversarios'];
    aniversarios.appendRow([TextCellValue('No. empleado'), TextCellValue('Nombre'), TextCellValue('Antigüedad (años)'), TextCellValue('Próximo aniversario')]);
    for (final a in resumen.proximosAniversarios) {
      aniversarios.appendRow([
        IntCellValue(a.empleado.numeroEmpleado),
        TextCellValue(a.empleado.nombreCompleto),
        IntCellValue(a.ciclo.antiguedadAnios),
        TextCellValue(a.ciclo.fechaProximoAniversario != null ? formatearFechaCortaXlsx(a.ciclo.fechaProximoAniversario!) : '—'),
      ]);
    }

    final alertas = excel['Alertas recontratacion'];
    alertas.appendRow([TextCellValue('No. empleado'), TextCellValue('Nombre'), TextCellValue('Motivos con advertencia')]);
    for (final a in resumen.alertasRecontratacion) {
      alertas.appendRow([
        IntCellValue(a.empleado.numeroEmpleado),
        TextCellValue(a.empleado.nombreCompleto),
        TextCellValue(a.alerta.motivos.map((m) => m.name).join(', ')),
      ]);
    }

    return excel.save() ?? const [];
  }
}
