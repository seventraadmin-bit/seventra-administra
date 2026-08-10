import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/usecases/resguardo_data.dart';

// Misma paleta institucional que `FichaTecnicaPdfRenderer` (Etapa 5E)
// — repetida aquí a propósito, ver el doc comment de ese archivo
// sobre por qué este paquete no importa el Design System de Flutter.
const _azulInstitucional = PdfColor.fromInt(0xFF1B4363);
const _grisTexto = PdfColor.fromInt(0xFF6B6156);
const _carbon = PdfColor.fromInt(0xFF221E1A);
const _grisLinea = PdfColor.fromInt(0xFFDDD8D2);

String _formatearFecha(DateTime fecha) {
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  return '${fecha.day} de ${meses[fecha.month - 1]} de ${fecha.year}';
}

/// Genera el PDF de entrega/resguardo de Inventario (Etapa 7C) — mismo
/// criterio que `FichaTecnicaPdfRenderer`: puro respecto a E/S, recibe
/// ya resueltos los datos y el logotipo (si aplica), nunca lee de
/// disco/BD por sí mismo. Este documento es siempre de una sola
/// página lógica (`pw.Page`, no `pw.MultiPage`): una entrega/resguardo
/// no debería nunca acumular tantos renglones como para justificar
/// paginación — si eso llegara a pasar, es señal de que se está
/// combinando demasiado en una sola firma.
///
/// **No persiste nada** — el use case orquestador (
/// `GenerarDocumentoResguardoUseCase`) escribe estos bytes a un
/// archivo temporal para imprimir. El documento que sí se guarda como
/// `Attachment` es el escaneo/foto ya firmado, subido después vía
/// `AdjuntarResguardoFirmadoUseCase` — este renderer no interviene en
/// ese segundo paso.
class ResguardoPdfRenderer {
  Future<Uint8List> renderizar({required ResguardoData data, Uint8List? logoBytes}) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _encabezado(data, logoBytes),
            pw.SizedBox(height: 18),
            _tablaArticulos(data.items),
            pw.SizedBox(height: 32),
            _bloqueFirma(),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _encabezado(ResguardoData data, Uint8List? logoBytes) {
    final destino = data.empleadoNombre ?? data.servicioNombre ?? '—';
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
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
                pw.Text('RISEG - Seguridad Privada', style: const pw.TextStyle(fontSize: 9, color: _grisTexto, letterSpacing: 0.5)),
                pw.Text(
                  'Entrega / resguardo de equipo',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
                ),
                pw.SizedBox(height: 4),
                pw.Text(destino, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _carbon)),
              ],
            ),
          ),
          pw.Text(_formatearFecha(data.fechaGeneracion), style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
        ],
      ),
    );
  }

  pw.Widget _tablaArticulos(List<ResguardoItem> items) {
    return pw.Table(
      border: pw.TableBorder.all(color: _grisLinea, width: 0.75),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _grisLinea),
          children: [
            _celda('Artículo', encabezado: true),
            _celda('Talla / serie', encabezado: true),
            _celda('Cantidad', encabezado: true),
            _celda('Condición', encabezado: true),
          ],
        ),
        for (final item in items)
          pw.TableRow(
            children: [
              _celda(item.sustituyeA == null ? item.articuloNombre : '${item.articuloNombre}\n(Sustituye a: ${item.sustituyeA})'),
              _celda(item.varianteLabel ?? item.unidadLabel ?? '—'),
              _celda(item.cantidad.toString()),
              _celda(item.condicionEntrega ?? '—'),
            ],
          ),
      ],
    );
  }

  pw.Widget _celda(String texto, {bool encabezado = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: encabezado ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: _carbon,
        ),
      ),
    );
  }

  pw.Widget _bloqueFirma() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Declaro haber recibido en las condiciones descritas el equipo listado, comprometiéndome '
          'a su buen uso, cuidado y devolución cuando me sea requerido.',
          style: const pw.TextStyle(fontSize: 9, color: _grisTexto),
        ),
        pw.SizedBox(height: 40),
        pw.Container(width: 220, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _carbon)))),
        pw.SizedBox(height: 4),
        pw.Text('Firma de recepción', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
      ],
    );
  }
}
