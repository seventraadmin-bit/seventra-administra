import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/usecases/recibo_pago_pdf_data.dart';

// Paleta corporativa de RISEG ONE (mismos valores que
// `ficha_tecnica_pdf_renderer.dart` — el paquete `pdf` es puro Dart, así
// que la paleta se repite aquí como constantes crudas en vez de
// reutilizar `AppColors` directo).
const _azulInstitucional = PdfColor.fromInt(0xFF1B4363); // accent700
const _carbon = PdfColor.fromInt(0xFF221E1A); // neutral900
const _grisTexto = PdfColor.fromInt(0xFF6B6156); // neutral600
const _grisLinea = PdfColor.fromInt(0xFFDDD8D2); // neutral200
const _fondoSuave = PdfColor.fromInt(0xFFEAF1F8); // accentSoftBgLight

/// Genera el PDF administrativo de un Recibo de pago (Etapa 15) —
/// documento entregable al Cliente, nunca un CFDI timbrado. Puro
/// respecto a E/S: recibe ya resueltos los bytes del logotipo (si
/// aplica) y todos los datos ya traducidos en [ReciboPagoPdfData] —
/// nunca lee de disco ni de BD por sí mismo (mismo criterio que
/// `FichaTecnicaPdfRenderer`).
class ReciboPagoPdfRenderer {
  Future<Uint8List> renderizar({required ReciboPagoPdfData data, Uint8List? logoBytes}) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (context) => _encabezado(data, logoBytes),
        footer: (context) => _pie(context),
        build: (context) => [
          _bloqueClienteYPeriodo(data),
          pw.SizedBox(height: 14),
          _seccionServicios(data),
          pw.SizedBox(height: 14),
          _tablaLineas(data),
          pw.SizedBox(height: 10),
          _bloqueTotales(data),
          if (data.metodoLabel != null) ...[pw.SizedBox(height: 10), _fila('Método de pago', data.metodoLabel!)],
          if (data.observaciones != null && data.observaciones!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _seccion('Observaciones', [_parrafo(data.observaciones!)]),
          ],
          pw.SizedBox(height: 18),
          _bloqueContactoEmpresa(data),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _encabezado(ReciboPagoPdfData data, Uint8List? logoBytes) {
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
                // Etapa 5B.3: fuera el rótulo fijo de la empresa piloto. El
                // nombre real ya viene de la Empresa que emite el recibo.
                pw.Text(
                  data.empresaNombreComercial,
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
                ),
                if (data.empresaRfc != null)
                  pw.Text('RFC: ${data.empresaRfc}', style: const pw.TextStyle(fontSize: 8, color: _grisTexto)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'RECIBO DE PAGO',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
              ),
              pw.SizedBox(height: 2),
              pw.Text('Folio: ${data.folio}', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
              pw.Text(_formatearFecha(data.fechaEmision), style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pie(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: _grisLinea, thickness: 0.75),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'Documento administrativo. No constituye un comprobante fiscal digital.',
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

  pw.Widget _bloqueClienteYPeriodo(ReciboPagoPdfData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _azulInstitucional, letterSpacing: 0.8)),
              pw.SizedBox(height: 3),
              pw.Text(
                data.clienteNombreComercial,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _carbon),
              ),
              pw.Text('Código: ${data.clienteCodigo}', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PERIODO', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _azulInstitucional, letterSpacing: 0.8)),
              pw.SizedBox(height: 3),
              pw.Text(
                '${_formatearFechaCorta(data.periodoInicio)} - ${_formatearFechaCorta(data.periodoFin)}',
                style: const pw.TextStyle(fontSize: 10, color: _carbon),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _seccionServicios(ReciboPagoPdfData data) {
    return _seccion('Servicio(s)', [for (final s in data.servicios) pw.Text(s, style: const pw.TextStyle(fontSize: 9.5, color: _carbon))]);
  }

  pw.Widget _tablaLineas(ReciboPagoPdfData data) {
    final headers = ['Puesto', 'Turno', 'Cant.', 'P. unitario', 'IVA', 'Subtotal'];
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: [
        for (final l in data.lineas)
          [
            l.puestoNombre,
            l.modalidadTurnoNombre,
            '${l.cantidadElementos}',
            _formatoMoneda(l.precioUnitario),
            l.tratamientoIvaLabel,
            _formatoMoneda(l.subtotalProporcional),
          ],
      ],
      headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _azulInstitucional),
      cellStyle: const pw.TextStyle(fontSize: 9, color: _carbon),
      cellAlignments: const {
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      border: pw.TableBorder.all(color: _grisLinea, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    );
  }

  pw.Widget _bloqueTotales(ReciboPagoPdfData data) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _filaTotal('Importe calculado', _formatoMoneda(data.importeBaseEsperado)),
          if (data.ajusteManual != null && data.ajusteManual != 0)
            _filaTotal('Ajuste', _formatoMoneda(data.ajusteManual!)),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(color: _fondoSuave, borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('TOTAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _azulInstitucional)),
                pw.SizedBox(width: 16),
                pw.Text(
                  _formatoMoneda(data.importeFinalEsperado),
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _filaTotal(String etiqueta, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$etiqueta: ', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
          pw.Text(valor, style: const pw.TextStyle(fontSize: 9, color: _carbon)),
        ],
      ),
    );
  }

  pw.Widget _bloqueContactoEmpresa(ReciboPagoPdfData data) {
    final datos = <String>[
      if (data.empresaTelefono != null) 'Tel: ${data.empresaTelefono}',
      if (data.empresaCorreo != null) data.empresaCorreo!,
      if (data.empresaSitioWeb != null) data.empresaSitioWeb!,
    ];
    if (datos.isEmpty) return pw.SizedBox.shrink();

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _grisLinea, width: 0.75))),
      child: pw.Text(datos.join('   |   '), style: const pw.TextStyle(fontSize: 8, color: _grisTexto)),
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
        pw.SizedBox(height: 4),
        ...contenido,
      ],
    );
  }

  pw.Widget _fila(String etiqueta, String valor) {
    return pw.Row(
      children: [
        pw.SizedBox(width: 110, child: pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 9.5, color: _grisTexto))),
        pw.Text(valor, style: const pw.TextStyle(fontSize: 9.5, color: _carbon)),
      ],
    );
  }

  pw.Widget _parrafo(String texto) {
    return pw.Text(texto, style: const pw.TextStyle(fontSize: 9.5, color: _carbon, lineSpacing: 2));
  }

  String _formatoMoneda(int centavos) {
    final pesos = centavos / 100;
    final texto = pesos.toStringAsFixed(2);
    final partes = texto.split('.');
    final entero = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '\$$entero.${partes[1]}';
  }

  String _formatearFecha(DateTime fecha) {
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]} de ${fecha.year}';
  }

  String _formatearFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }
}
