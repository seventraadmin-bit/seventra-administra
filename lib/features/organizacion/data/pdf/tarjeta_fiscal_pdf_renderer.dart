import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/usecases/tarjeta_fiscal_data.dart';

// Paleta corporativa de RISEG ONE (mismos valores que
// `recibo_pago_pdf_renderer.dart`/`ficha_tecnica_pdf_renderer.dart`).
const _azulInstitucional = PdfColor.fromInt(0xFF1B4363); // accent700
const _carbon = PdfColor.fromInt(0xFF221E1A); // neutral900
const _grisTexto = PdfColor.fromInt(0xFF6B6156); // neutral600
const _grisLinea = PdfColor.fromInt(0xFFDDD8D2); // neutral200

/// Genera el PDF de la Tarjeta fiscal de Empresa (Etapa 16) — documento
/// operativo para solicitar facturas a proveedores, NUNCA un CFDI ni
/// publicidad. Puro respecto a E/S: recibe ya resueltos los bytes del
/// logotipo (si aplica) y [TarjetaFiscalData] ya construido — mismo
/// criterio que `ReciboPagoPdfRenderer`/`FichaTecnicaPdfRenderer`.
class TarjetaFiscalPdfRenderer {
  Future<Uint8List> renderizar({required TarjetaFiscalData data, Uint8List? logoBytes}) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _encabezado(data, logoBytes),
            pw.SizedBox(height: 20),
            _seccion('Datos para facturación', [
              _fila('Razón social', data.razonSocial),
              pw.SizedBox(height: 6),
              _fila('RFC', data.rfc),
            ]),
            if (data.domicilioLineas.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              _seccion('Domicilio fiscal', [
                for (final linea in data.domicilioLineas) pw.Text(linea, style: const pw.TextStyle(fontSize: 10, color: _carbon)),
              ]),
            ],
            if (_datosContacto(data).isNotEmpty) ...[
              pw.SizedBox(height: 16),
              _seccion('Contacto', [
                for (final entrada in _datosContacto(data)) _fila(entrada.$1, entrada.$2),
              ]),
            ],
            pw.Spacer(),
            _pie(data),
          ],
        ),
      ),
    );

    return doc.save();
  }

  List<(String, String)> _datosContacto(TarjetaFiscalData data) {
    return [
      if (data.correo != null) ('Correo', data.correo!),
      if (data.telefono != null) ('Teléfono', data.telefono!),
      if (data.sitioWeb != null) ('Sitio web', data.sitioWeb!),
    ];
  }

  pw.Widget _encabezado(TarjetaFiscalData data, Uint8List? logoBytes) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _azulInstitucional, width: 2))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoBytes != null) ...[
            pw.Image(pw.MemoryImage(logoBytes), width: 38, height: 38),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Etapa 5B.3: aquí había un rótulo fijo con el nombre de la
                // empresa piloto, encima del nombre real que ya sale de la
                // Empresa. Sobraba y mentía para cualquier otra.
                pw.Text(
                  data.nombreComercial,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
                ),
              ],
            ),
          ),
          pw.Text(
            'TARJETA FISCAL',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azulInstitucional, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  pw.Widget _seccion(String titulo, List<pw.Widget> contenido) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo.toUpperCase(),
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _azulInstitucional, letterSpacing: 0.8),
        ),
        pw.SizedBox(height: 6),
        ...contenido,
      ],
    );
  }

  pw.Widget _fila(String etiqueta, String valor) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 110, child: pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 9.5, color: _grisTexto))),
        pw.Expanded(child: pw.Text(valor, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _carbon))),
      ],
    );
  }

  pw.Widget _pie(TarjetaFiscalData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: _grisLinea, thickness: 0.75),
        pw.SizedBox(height: 4),
        pw.Text(
          'Información proporcionada para fines de facturación.',
          style: const pw.TextStyle(fontSize: 7.5, color: _grisTexto),
        ),
        pw.SizedBox(height: 2),
        pw.Text('Generado el ${_formatearFecha(data.generadoEn)}', style: const pw.TextStyle(fontSize: 7, color: _grisTexto)),
      ],
    );
  }

  String _formatearFecha(DateTime fecha) {
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]} de ${fecha.year}';
  }
}
