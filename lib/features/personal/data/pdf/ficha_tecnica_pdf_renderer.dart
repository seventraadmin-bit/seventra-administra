import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/usecases/ficha_tecnica_data.dart';

// Paleta corporativa de RISEG ONE (mismos valores que
// `AppColors.accent500/600/700`/`neutral*` del Design System de la
// app — este archivo no importa Flutter a propósito (el paquete `pdf`
// es puro Dart, generable/testeable sin bindings de Flutter), así que
// los valores se repiten aquí como constantes crudas en vez de
// reutilizar `AppColors` directo.
const _azulInstitucional = PdfColor.fromInt(0xFF1B4363); // accent700
const _azulTexto = PdfColor.fromInt(0xFF24587F); // accent600
const _carbon = PdfColor.fromInt(0xFF221E1A); // neutral900
const _grisTexto = PdfColor.fromInt(0xFF6B6156); // neutral600
const _grisLinea = PdfColor.fromInt(0xFFDDD8D2); // neutral200
const _fondoSuave = PdfColor.fromInt(0xFFEAF1F8); // accentSoftBgLight

const _resultadoLabel = {'negativo': 'Negativo', 'positivo': 'Positivo'};

/// Genera el PDF de la Ficha técnica corporativa de un Empleado (Etapa
/// 5E) — una página, o dos si el contenido real lo requiere para
/// mantener buena legibilidad (Resolución explícita de Marlon: nunca
/// forzar una sola página reduciendo tipografía/espacios en exceso),
/// vía `pw.MultiPage` (paginación automática).
///
/// Puro respecto a E/S: recibe ya resueltos los bytes de fotografía y
/// logotipo (si aplican) — nunca lee de disco ni de BD por sí mismo,
/// eso es responsabilidad del use case orquestador.
class FichaTecnicaPdfRenderer {
  Future<Uint8List> renderizar({
    required FichaTecnicaData data,
    required String folio,
    required DateTime fechaGeneracion,
    Uint8List? logoBytes,
    Uint8List? fotografiaBytes,
    String? empresaNombreComercial,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (context) => _encabezado(
          folio: folio,
          fecha: fechaGeneracion,
          logoBytes: logoBytes,
          empresaNombreComercial: empresaNombreComercial,
        ),
        footer: (context) => _pie(context),
        build: (context) => [
          _bloqueIdentidad(data, fotografiaBytes),
          pw.SizedBox(height: 18),
          _seccionExperiencia(data),
          if (data.tieneServicioOTurno) _seccion('Asignación operativa', _filasServicioTurno(data)),
          if (data.zonaResidencia != null) _seccion('Zona de residencia', [_fila('Ubicación', data.zonaResidencia!)]),
          if (data.tieneContacto) _seccion('Contacto', _filasContacto(data)),
          if (data.resumenPsicologico != null || data.resumenEstudioSocioeconomico != null)
            _seccionEvaluaciones(data),
          if (data.antidoping.isNotEmpty) _seccionAntidoping(data),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _encabezado({
    required String folio,
    required DateTime fecha,
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
                // Etapa 5B.3: la Empresa que emite el documento, no un
                // nombre fijo. Sin ella, el renglón no se dibuja.
                if (empresaNombreComercial != null)
                  pw.Text(
                    empresaNombreComercial,
                    style: const pw.TextStyle(fontSize: 9, color: _grisTexto, letterSpacing: 0.5),
                  ),
                pw.Text(
                  'Ficha técnica corporativa',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _azulInstitucional),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Folio: $folio', style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
              pw.Text(_formatearFecha(fecha), style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
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
                'Información confidencial proporcionada exclusivamente para fines de evaluación y '
                'prestación del servicio de seguridad privada. Su reproducción o distribución no '
                'autorizada está restringida.',
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

  pw.Widget _bloqueIdentidad(FichaTecnicaData data, Uint8List? fotografiaBytes) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (fotografiaBytes != null) ...[
          pw.ClipRRect(
            horizontalRadius: 44,
            verticalRadius: 44,
            child: pw.Image(pw.MemoryImage(fotografiaBytes), width: 88, height: 88, fit: pw.BoxFit.cover),
          ),
          pw.SizedBox(width: 16),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                data.nombreCompleto,
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _carbon),
              ),
              pw.SizedBox(height: 4),
              pw.Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _dato('Edad', '${data.edad} años'),
                  if (data.puestoNombre != null) _dato('Puesto', data.puestoNombre!),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _dato(String etiqueta, String valor) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text('$etiqueta: ', style: const pw.TextStyle(fontSize: 10, color: _grisTexto)),
        pw.Text(valor, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _carbon)),
      ],
    );
  }

  pw.Widget _seccionExperiencia(FichaTecnicaData data) {
    final experiencia = data.mesesExperienciaAdicionales == null || data.mesesExperienciaAdicionales == 0
        ? '${data.aniosExperiencia} años'
        : '${data.aniosExperiencia} años, ${data.mesesExperienciaAdicionales} meses';

    return _seccion('Experiencia en seguridad privada', [
      _fila('Experiencia', experiencia),
      if (data.ultimoPuestoDesempenado != null) _fila('Último puesto desempeñado', data.ultimoPuestoDesempenado!),
      if (data.resumenExperiencia != null) _parrafo(data.resumenExperiencia!),
    ]);
  }

  List<pw.Widget> _filasServicioTurno(FichaTecnicaData data) {
    return [
      if (data.servicioNombre != null) _fila('Servicio asignado', data.servicioNombre!),
      if (data.turnoNombre != null) _fila('Turno', data.turnoNombre!),
    ];
  }

  List<pw.Widget> _filasContacto(FichaTecnicaData data) {
    return [
      if (data.telefono != null) _fila('Teléfono', data.telefono!),
      if (data.contactoEmergenciaNombre != null) _fila('Contacto de emergencia', data.contactoEmergenciaNombre!),
      if (data.telefonoEmergencia != null) _fila('Teléfono de emergencia', data.telefonoEmergencia!),
      if (data.parentescoEmergencia != null) _fila('Parentesco', data.parentescoEmergencia!),
    ];
  }

  pw.Widget _seccionEvaluaciones(FichaTecnicaData data) {
    return _seccion('Evaluaciones', [
      if (data.resumenPsicologico != null) ...[
        pw.Text('Perfil psicológico', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _azulTexto)),
        pw.SizedBox(height: 2),
        _parrafo(data.resumenPsicologico!),
        pw.SizedBox(height: 8),
      ],
      if (data.resumenEstudioSocioeconomico != null) ...[
        pw.Text('Estudio socioeconómico', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _azulTexto)),
        pw.SizedBox(height: 2),
        _parrafo(data.resumenEstudioSocioeconomico!),
      ],
    ]);
  }

  pw.Widget _seccionAntidoping(FichaTecnicaData data) {
    return _seccion('Antidoping', [
      pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final r in data.antidoping) _insigniaAntidoping(r)],
      ),
    ]);
  }

  pw.Widget _insigniaAntidoping(AntidopingFichaTecnica resultado) {
    final positivo = resultado.resultado == 'positivo';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: positivo ? const PdfColor.fromInt(0xFFFBEAEA) : _fondoSuave,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        '${resultado.sustancia}: ${_resultadoLabel[resultado.resultado] ?? resultado.resultado}',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: positivo ? const PdfColor.fromInt(0xFFA23B3B) : _azulTexto,
        ),
      ),
    );
  }

  pw.Widget _seccion(String titulo, List<pw.Widget> contenido) {
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

  pw.Widget _fila(String etiqueta, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 150, child: pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 9.5, color: _grisTexto))),
          pw.Expanded(
            child: pw.Text(valor, style: const pw.TextStyle(fontSize: 9.5, color: _carbon)),
          ),
        ],
      ),
    );
  }

  pw.Widget _parrafo(String texto) {
    return pw.Text(texto, style: const pw.TextStyle(fontSize: 9.5, color: _carbon, lineSpacing: 2));
  }

  String _formatearFecha(DateTime fecha) {
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${fecha.day} de ${meses[fecha.month - 1]} de ${fecha.year}';
  }
}
