import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/export/reporte_export_context.dart';
import '../../domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import '../../presentation/finanzas/reportes_finanzas_state.dart';
import 'reporte_pdf_encabezado.dart';

const _rangoAntiguedadLabel = {
  'alCorriente': 'Al corriente',
  'dias0a30': '0 a 30 días',
  'dias31a60': '31 a 60 días',
  'dias61a90': '61 a 90 días',
  'dias90Mas': 'Más de 90 días',
};

/// PDF resumen financiero (Etapa 12D) — solo se genera cuando el
/// controller ya autorizó `finanzas.ver` (`!sinAutorizacion`); nunca
/// consulta nada por su cuenta, recibe exactamente el `state` ya
/// cargado en pantalla.
class ReporteFinanzasPdfRenderer {
  Future<Uint8List> renderizar({
    required ReporteExportContext contexto,
    required ReportesFinanzasState state,
    Uint8List? logoBytes,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (context) => context.pageNumber == 1
            ? construirEncabezadoReporte(contexto, logoBytes: logoBytes)
            : pw.SizedBox(),
        footer: (context) => construirPiePaginaReporte(context),
        build: (context) => [
          construirSeccionReporte('Resumen financiero', [
            construirFilaReporte('Ingresos', formatearMonedaReporte(state.totalIngresos)),
            construirFilaReporte('Egresos', formatearMonedaReporte(state.totalEgresos)),
            construirFilaReporte('Resultado operativo', formatearMonedaReporte(state.resultadoOperativo), destacado: true),
            construirFilaReporte('Pagos recibidos', formatearMonedaReporte(state.totalPagosRecibidos)),
          ]),
          if (state.egresosPorOrigen != null) construirSeccionReporte('Egresos por origen', _filasOrigen(state.egresosPorOrigen!)),
          construirSeccionReporte('Cuentas por cobrar - antigüedad (a la fecha de hoy)', _filasAging(state)),
          if (state.ingresosPorCategoria.isNotEmpty)
            construirSeccionReporte('Ingresos por categoría', _filasCategoria(state.ingresosPorCategoria)),
          if (state.egresosPorCategoria.isNotEmpty)
            construirSeccionReporte('Egresos por categoría', _filasCategoria(state.egresosPorCategoria)),
        ],
      ),
    );

    return doc.save();
  }

  List<pw.Widget> _filasOrigen(ResumenEgresosPorOrigen origen) {
    return [
      construirFilaReporte('Origen Compras', formatearMonedaReporte(origen.totalCompra)),
      construirFilaReporte('Origen Nómina', formatearMonedaReporte(origen.totalNomina)),
      construirFilaReporte('Origen manual', formatearMonedaReporte(origen.totalManual)),
    ];
  }

  List<pw.Widget> _filasAging(ReportesFinanzasState state) {
    final filas = <pw.Widget>[];
    for (final rango in state.montoPorCobrarPorRango.keys) {
      final cuentas = state.cuentasPorCobrarPorRango[rango] ?? 0;
      final monto = state.montoPorCobrarPorRango[rango] ?? 0;
      filas.add(construirFilaReporte(
        _rangoAntiguedadLabel[rango.name] ?? rango.name,
        '$cuentas cuenta(s) - ${formatearMonedaReporte(monto)}',
      ));
    }
    if (filas.isEmpty) filas.add(construirFilaReporte('Cuentas por cobrar', 'Sin cuentas pendientes'));
    return filas;
  }

  List<pw.Widget> _filasCategoria(List<TotalPorCategoria> categorias) {
    return [for (final c in categorias) construirFilaReporte(c.nombreCategoria, formatearMonedaReporte(c.total))];
  }
}
