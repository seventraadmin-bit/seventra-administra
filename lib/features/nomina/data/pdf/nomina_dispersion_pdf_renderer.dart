import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/usecases/nomina_dispersion_pdf_data.dart';

// Paleta corporativa de RISEG ONE (mismos valores que
// `recibo_pago_pdf_renderer.dart`/`ficha_tecnica_pdf_renderer.dart` —
// el paquete `pdf` es puro Dart, así que la paleta se repite aquí en
// vez de reutilizar `AppColors` directo).
const _azulInstitucional = PdfColor.fromInt(0xFF1B4363); // accent700
const _carbon = PdfColor.fromInt(0xFF221E1A); // neutral900
const _grisTexto = PdfColor.fromInt(0xFF6B6156); // neutral600
const _grisLinea = PdfColor.fromInt(0xFFDDD8D2); // neutral200
const _fondoAdvertencia = PdfColor.fromInt(0xFFFCEEE0); // warningBg aproximado
const _naranjaAdvertencia = PdfColor.fromInt(0xFFB5590A); // warning700 aproximado

/// Genera el PDF de control de dispersión de una Nómina Cerrada/Pagada
/// (Etapa 15) — hoja operativa para ejecutar y verificar transferencias
/// bancarias, **nunca** un CFDI/recibo/comprobante. Apaisado (letter
/// landscape) para que las 12 columnas (checkbox, No., nombre,
/// Servicio, banco, cuenta/tarjeta, CLABE, Fiscal, No fiscal, total,
/// hora, referencia) quepan sin truncar nombres ni números de cuenta.
///
/// Puro respecto a E/S: recibe ya resueltos los bytes del logotipo (si
/// aplica) y todos los datos ya traducidos en [NominaDispersionPdfData]
/// — nunca lee de disco ni de BD por sí mismo (mismo criterio que
/// `ReciboPagoPdfRenderer`/`FichaTecnicaPdfRenderer`).
class NominaDispersionPdfRenderer {
  Future<Uint8List> renderizar({
    required NominaDispersionPdfData data,
    Uint8List? logoBytes,
    String? empresaNombreComercial,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        header: (context) => _encabezado(data, logoBytes, empresaNombreComercial),
        footer: (context) => _pie(context, data),
        build: (context) => [
          if (data.totalRequierenVerificacion > 0) ...[_avisoVerificacion(data), pw.SizedBox(height: 10)],
          _tablaRenglones(data),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _encabezado(NominaDispersionPdfData data, Uint8List? logoBytes, String? empresaNombreComercial) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _azulInstitucional, width: 2))),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoBytes != null) ...[
                pw.Image(pw.MemoryImage(logoBytes), width: 30, height: 30),
                pw.SizedBox(width: 10),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Etapa 5B.3: aquí iba el nombre del producto. Va el de
                    // la Empresa que dispersa la nómina.
                    if (empresaNombreComercial != null)
                      pw.Text(
                        empresaNombreComercial,
                        style: const pw.TextStyle(fontSize: 9, color: _grisTexto, letterSpacing: 0.5),
                      ),
                    pw.Text(
                      'Control de dispersión de nómina',
                      style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Folio: ${data.folio}', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
                  pw.Text('Estatus: ${data.estatusLabel}', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
                  pw.Text('Generado: ${_formatearFechaHora(data.fechaGeneracion)}', style: const pw.TextStyle(fontSize: 8, color: _grisTexto)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _bloqueEncabezado('Periodo', '${_formatearFechaCorta(data.periodoInicio)} - ${_formatearFechaCorta(data.periodoFin)}'),
              _bloqueEncabezado('Fecha de pago', _formatearFechaCorta(data.fechaPago)),
              _bloqueEncabezado('Empleados', '${data.totalEmpleados}'),
              _bloqueEncabezado('Total Fiscal', _formatoMoneda(data.totalFiscal)),
              _bloqueEncabezado('Total No fiscal', _formatoMoneda(data.totalNoFiscal)),
              _bloqueEncabezado('Total general', _formatoMoneda(data.totalGeneral), destacado: true),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _bloqueEncabezado(String etiqueta, String valor, {bool destacado = false}) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(etiqueta.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _grisTexto, letterSpacing: 0.5)),
          pw.SizedBox(height: 1),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: destacado ? 11 : 9.5,
              fontWeight: pw.FontWeight.bold,
              color: destacado ? _azulInstitucional : _carbon,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _avisoVerificacion(NominaDispersionPdfData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(color: _fondoAdvertencia, borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Text(
        '${data.totalRequierenVerificacion} de ${data.totalEmpleados} renglon(es) requieren verificación de datos bancarios antes de dispersar. '
        'No dispersar sin verificar los datos bancarios.',
        style: pw.TextStyle(fontSize: 9, color: _naranjaAdvertencia, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _tablaRenglones(NominaDispersionPdfData data) {
    final headers = ['', 'No.', 'Nombre', 'Servicio', 'Banco', 'Cuenta / Tarjeta', 'CLABE', 'Fiscal', 'No fiscal', 'Total', 'Hora', 'Referencia'];
    final filas = data.renglones;

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: [
        for (final r in filas)
          [
            '',
            '${r.numeroEmpleado}',
            r.requiereVerificacion ? '${r.nombreCompleto}\nREQUIERE VERIFICACIÓN' : r.nombreCompleto,
            r.servicioNombre ?? '-',
            r.bancoNombre ?? '-',
            r.numeroCuentaTarjeta ?? '-',
            r.clabe ?? '-',
            _formatoMoneda(r.montoFiscal),
            _formatoMoneda(r.montoNoFiscal),
            _formatoMoneda(r.totalAPagar),
            '',
            '',
          ],
      ],
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _azulInstitucional),
      cellStyle: const pw.TextStyle(fontSize: 8, color: _carbon),
      cellAlignments: const {
        0: pw.Alignment.center,
        1: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
        9: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(16),
        1: const pw.FixedColumnWidth(24),
        2: const pw.FlexColumnWidth(2.1),
        3: const pw.FlexColumnWidth(1.6),
        4: const pw.FlexColumnWidth(1.3),
        5: const pw.FlexColumnWidth(1.4),
        6: const pw.FlexColumnWidth(1.6),
        7: const pw.FlexColumnWidth(1.0),
        8: const pw.FlexColumnWidth(1.0),
        9: const pw.FlexColumnWidth(1.1),
        10: const pw.FlexColumnWidth(0.9),
        11: const pw.FlexColumnWidth(1.3),
      },
      border: pw.TableBorder.all(color: _grisLinea, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      cellDecoration: (index, cellData, rowNum) {
        if (rowNum == 0) return const pw.BoxDecoration(color: _azulInstitucional);
        final fila = filas[rowNum - 1];
        if (fila.requiereVerificacion) return const pw.BoxDecoration(color: _fondoAdvertencia);
        return const pw.BoxDecoration();
      },
    );
  }

  pw.Widget _pie(pw.Context context, NominaDispersionPdfData data) {
    return pw.Column(
      children: [
        pw.Divider(color: _grisLinea, thickness: 0.75),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'Control interno de dispersión de nómina. NO es CFDI, recibo fiscal, comprobante bancario ni recibo individual del trabajador.',
                style: const pw.TextStyle(fontSize: 6.5, color: _grisTexto),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Text(
              'Empleados: ${data.totalEmpleados}   |   Con advertencia: ${data.totalRequierenVerificacion}   |   '
              'Fiscal: ${_formatoMoneda(data.totalFiscal)}   |   No fiscal: ${_formatoMoneda(data.totalNoFiscal)}   |   '
              'Total: ${_formatoMoneda(data.totalGeneral)}',
              style: pw.TextStyle(fontSize: 6.5, color: _carbon, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 10),
            pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 6.5, color: _grisTexto)),
          ],
        ),
      ],
    );
  }

  String _formatoMoneda(int centavos) {
    final pesos = centavos / 100;
    final texto = pesos.toStringAsFixed(2);
    final partes = texto.split('.');
    final entero = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '\$$entero.${partes[1]}';
  }

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _formatearFechaHora(DateTime fecha) {
    return '${_formatearFechaCorta(fecha)} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }
}
