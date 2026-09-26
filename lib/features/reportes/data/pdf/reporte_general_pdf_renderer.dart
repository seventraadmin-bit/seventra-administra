import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/obtener_resumen_general_usecase.dart';
import 'reporte_pdf_encabezado.dart';

/// PDF ejecutivo del Reporte General (Etapa 12D) — replica campo por
/// campo la misma condición `!= null` que ya usa `ReportesGeneralScreen`
/// para omitir tarjetas: un campo ausente en el resumen (sección sin
/// autorización) nunca aparece en el PDF, ni siquiera como "$0" (eso
/// sería indistinguible de un cero real y autorizado).
class ReporteGeneralPdfRenderer {
  Future<Uint8List> renderizar({
    required ReporteExportContext contexto,
    required ResumenGeneralReportes resumen,
    Uint8List? logoBytes,
    String? empresaNombreComercial,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (context) => context.pageNumber == 1
            ? construirEncabezadoReporte(
                contexto,
                logoBytes: logoBytes,
                empresaNombreComercial: empresaNombreComercial,
              )
            : pw.SizedBox(),
        footer: (context) => construirPiePaginaReporte(context),
        build: (context) => [
          construirSeccionReporte('Finanzas del periodo', _filasFinanzas(resumen)),
          construirSeccionReporte('Indicadores informativos del periodo', _filasInformativos(resumen)),
          construirSeccionReporte('Situación actual (a la fecha de generación)', _filasSnapshot(resumen)),
        ],
      ),
    );

    return doc.save();
  }

  List<pw.Widget> _filasFinanzas(ResumenGeneralReportes r) {
    final filas = <pw.Widget>[];
    if (r.totalIngresos != null) filas.add(construirFilaReporte('Ingresos', formatearMonedaReporte(r.totalIngresos!)));
    // 'Gasto operativo' y no 'Egresos': la cifra es la misma que
    // muestra la pantalla y la misma que usa Finanzas — incluye el
    // gasto financiado con tarjeta y excluye los pagos de deuda. La
    // salida de caja real va aparte, abajo, porque es otra cosa.
    if (r.gastoOperativo != null) {
      filas.add(construirFilaReporte('Gasto operativo', formatearMonedaReporte(r.gastoOperativo!)));
    }
    if (r.salidasDeEfectivo != null) {
      filas.add(construirFilaReporte('Salidas de efectivo (informativo)', formatearMonedaReporte(r.salidasDeEfectivo!)));
    }
    if (r.resultadoOperativo != null) {
      filas.add(construirFilaReporte('Resultado operativo', formatearMonedaReporte(r.resultadoOperativo!), destacado: true));
    }
    if (filas.isEmpty) filas.add(construirFilaReporte('Finanzas', 'Sin autorización para esta sección'));
    return filas;
  }

  List<pw.Widget> _filasInformativos(ResumenGeneralReportes r) {
    final filas = <pw.Widget>[];
    if (r.totalComprasPeriodo != null) {
      filas.add(construirFilaReporte('Compras del periodo (informativo)', formatearMonedaReporte(r.totalComprasPeriodo!)));
    }
    if (r.totalNominaPagadaPeriodo != null) {
      filas.add(construirFilaReporte('Nómina pagada (informativo)', formatearMonedaReporte(r.totalNominaPagadaPeriodo!)));
    }
    if (filas.isEmpty) filas.add(construirFilaReporte('Compras / Nómina', 'Sin autorización para esta sección'));
    return filas;
  }

  List<pw.Widget> _filasSnapshot(ResumenGeneralReportes r) {
    final filas = <pw.Widget>[];
    if (r.personalActivoActual != null) filas.add(construirFilaReporte('Personal activo', '${r.personalActivoActual}'));
    if (r.serviciosActivosActual != null) {
      filas.add(construirFilaReporte('Servicios activos', '${r.serviciosActivosActual}'));
    }
    if (filas.isEmpty) filas.add(construirFilaReporte('Personal / Servicios', 'Sin autorización para esta sección'));
    return filas;
  }
}
