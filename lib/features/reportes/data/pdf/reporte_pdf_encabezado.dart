import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/export/reporte_export_context.dart';

// Misma paleta institucional que `FichaTecnicaPdfRenderer`/
// `ResguardoPdfRenderer` — repetida aquí a propósito (paquete `pdf`
// puro Dart, sin import de Flutter/Design System).
const _azulInstitucional = PdfColor.fromInt(0xFF1B4363);
const _grisTexto = PdfColor.fromInt(0xFF6B6156);
const _carbon = PdfColor.fromInt(0xFF221E1A);
const _grisLinea = PdfColor.fromInt(0xFFDDD8D2);

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String formatearFechaReporte(DateTime fecha) => '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year}';

String formatearFechaCorta(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

/// Formato de moneda en pesos mexicanos a partir de centavos — mismo
/// criterio que `formatoCentavosPago` (Flutter, Finanzas), duplicado
/// aquí en Dart puro por la misma razón que el resto de este archivo.
String formatearMonedaReporte(int centavos) {
  final pesos = centavos / 100;
  final negativo = pesos < 0;
  final absoluto = pesos.abs();
  final parteEntera = absoluto.truncate().toString();
  final parteDecimal = ((absoluto - absoluto.truncate()) * 100).round().toString().padLeft(2, '0');

  final buffer = StringBuffer();
  for (var i = 0; i < parteEntera.length; i++) {
    if (i > 0 && (parteEntera.length - i) % 3 == 0) buffer.write(',');
    buffer.write(parteEntera[i]);
  }

  return '${negativo ? '-' : ''}\$$buffer.$parteDecimal';
}

String formatearPeriodoReporte(DateTime? inicio, DateTime? fin) {
  if (inicio == null && fin == null) return 'Sin periodo definido';
  if (inicio == null) return 'Hasta ${formatearFechaCorta(fin!)}';
  if (fin == null) return 'Desde ${formatearFechaCorta(inicio)}';
  return '${formatearFechaCorta(inicio)} - ${formatearFechaCorta(fin)}';
}

/// Encabezado compartido por todos los PDF de Reportes (Etapa 12D) —
/// única desviación deliberada del criterio "cada renderer duplica su
/// propio encabezado" (FichaTecnica/Resguardo): a diferencia de esos
/// dos casos, aquí el contenido del encabezado (branding, nombre del
/// reporte, periodo, quién y cuándo lo generó) es idéntico para todos
/// los reportes exportados desde este módulo, así que compartirlo es
/// lo correcto, no una excepción al patrón.
pw.Widget construirEncabezadoReporte(
  ReporteExportContext contexto, {
  Uint8List? logoBytes,
  String? empresaNombreComercial,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _azulInstitucional, width: 2))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoBytes != null) ...[
          pw.Image(pw.MemoryImage(logoBytes), width: 34, height: 34),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Etapa 5B.3: la Empresa que exporta el reporte, no un
              // nombre fijo. Sin ella, el renglón no se dibuja.
              if (empresaNombreComercial != null)
                pw.Text(
                  empresaNombreComercial,
                  style: const pw.TextStyle(fontSize: 9, color: _grisTexto, letterSpacing: 0.5),
                ),
              pw.Text(
                contexto.nombreReporte,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Periodo: ${formatearPeriodoReporte(contexto.rangoInicio, contexto.rangoFin)}',
                style: const pw.TextStyle(fontSize: 9.5, color: _carbon),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Generado por: ${contexto.generadoPor}', style: const pw.TextStyle(fontSize: 8.5, color: _grisTexto)),
            pw.Text(formatearFechaReporte(contexto.generadoEn), style: const pw.TextStyle(fontSize: 8.5, color: _grisTexto)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget construirPiePaginaReporte(pw.Context context) {
  return pw.Column(
    children: [
      pw.Divider(color: _grisLinea, thickness: 0.75),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              'Información confidencial de uso interno.',
              style: const pw.TextStyle(fontSize: 7, color: _grisTexto),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: _grisTexto),
          ),
        ],
      ),
    ],
  );
}

/// Tarjeta de cifra — mismo vocabulario visual de "sección" que
/// `FichaTecnicaPdfRenderer._seccion`, adaptado para pares
/// etiqueta/valor de una sola línea.
pw.Widget construirSeccionReporte(String titulo, List<pw.Widget> contenido) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo.toUpperCase(),
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _azulInstitucional, letterSpacing: 0.8),
        ),
        pw.SizedBox(height: 4),
        pw.Divider(color: _grisLinea, thickness: 0.75),
        pw.SizedBox(height: 6),
        ...contenido,
      ],
    ),
  );
}

pw.Widget construirFilaReporte(String etiqueta, String valor, {bool destacado = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 180, child: pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 9.5, color: _grisTexto))),
        pw.Expanded(
          child: pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: destacado ? 11 : 9.5,
              fontWeight: destacado ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _carbon,
            ),
          ),
        ),
      ],
    ),
  );
}
