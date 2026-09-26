import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import '../../domain/export/reporte_export_context.dart';
import 'reporte_pdf_encabezado.dart';

const _estatusUnidadLabel = {
  'disponible': 'Disponible',
  'asignado': 'Asignada',
  'enLavanderia': 'En lavanderia',
  'enReparacion': 'En reparacion',
  'pendienteDesecho': 'Pendiente de desecho',
  'danado': 'Danada',
  'perdido': 'Perdida',
  'baja': 'Dada de baja',
};

/// PDF ejecutivo de Patrimonio y bajas.
///
/// Resumen, no listado: KPIs, estados físicos, principales bajas,
/// autorizaciones y descuentos, cada bloque en una línea por concepto.
/// El detalle completo —un renglón por bien— vive en el XLSX; meterlo
/// aquí produciría un documento imposible de leer.
class ReportePatrimonioPdfRenderer {
  /// Cuántos renglones se listan por bloque antes de resumir el resto.
  static const _tope = 10;

  Future<Uint8List> renderizar({
    required ReporteExportContext contexto,
    required AnalisisPatrimonio analisis,
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
          construirSeccionReporte('Resumen de bajas', _filasResumen(analisis)),
          construirSeccionReporte('Recuperacion', _filasRecuperacion(analisis)),
          if (analisis.unidadesPorEstatus.isNotEmpty)
            construirSeccionReporte('Estado fisico de los bienes recuperados', _filasEstados(analisis)),
          if (analisis.impactoPorBaja.any((i) => i.bienesEnRiesgo > 0))
            construirSeccionReporte('Bajas con mayor impacto', _filasImpacto(analisis)),
          if (analisis.problemasPorServicio.isNotEmpty)
            construirSeccionReporte('Problemas por servicio', _filasServicios(analisis)),
          if (analisis.autorizadores.isNotEmpty)
            construirSeccionReporte('Autorizaciones por administrativo', _filasAutorizadores(analisis)),
          construirSeccionReporte('Descuentos generados por conciliacion', _filasDescuentos(analisis)),
        ],
      ),
    );

    return doc.save();
  }

  List<pw.Widget> _filasResumen(AnalisisPatrimonio a) {
    return [
      construirFilaReporte('Bajas conciliadas', '${a.bajasConciliadas}', destacado: true),
      construirFilaReporte('Bienes recuperados', '${a.recuperados}'),
      // Pendiente y perdido en lineas distintas: no son lo mismo.
      construirFilaReporte('Pendientes de recuperar', '${a.pendientes}'),
      construirFilaReporte('Bienes perdidos', '${a.perdidos}'),
      construirFilaReporte('Transferidos a otra persona', '${a.transferidos}'),
    ];
  }

  List<pw.Widget> _filasRecuperacion(AnalisisPatrimonio a) {
    final tasa = a.tasaRecuperacion;
    return [
      construirFilaReporte(
        'Tasa de recuperacion',
        tasa.tasa == null ? 'Sin bienes que debieran recuperarse' : '${(tasa.tasa! * 100).toStringAsFixed(0)} %',
        destacado: true,
      ),
      construirFilaReporte('Denominador (recuperados + pendientes + perdidos)', '${tasa.debianRecuperarse}'),
      construirFilaReporte('Excluidos por transferencia', '${tasa.excluidosTransferidos}'),
      construirFilaReporte('Excluidos por autorizacion a conservar', '${tasa.excluidosAutorizados}'),
      construirFilaReporte('Valor de bienes pendientes', formatearMonedaReporte(a.valorPendiente)),
      construirFilaReporte('Valor de bienes perdidos', formatearMonedaReporte(a.valorPerdido)),
      if (a.valorEsParcial)
        construirFilaReporte('Bienes sin costo capturado', '${a.bienesSinValorConocido} (el valor es parcial)'),
    ];
  }

  List<pw.Widget> _filasEstados(AnalisisPatrimonio a) {
    return [
      for (final entrada in a.unidadesPorEstatus.entries)
        construirFilaReporte(_estatusUnidadLabel[entrada.key] ?? entrada.key, '${entrada.value}'),
    ];
  }

  List<pw.Widget> _filasImpacto(AnalisisPatrimonio a) {
    final enRiesgo = a.impactoPorBaja.where((i) => i.bienesEnRiesgo > 0).toList();
    final mostradas = enRiesgo.take(_tope).toList();
    return [
      for (final baja in mostradas)
        construirFilaReporte(
          baja.nombre,
          '${baja.bienesEnRiesgo} bien(es) - ${formatearMonedaReporte(baja.importeDescuentos)}',
        ),
      if (enRiesgo.length > mostradas.length)
        construirFilaReporte('Otras bajas con pendientes', '${enRiesgo.length - mostradas.length}'),
    ];
  }

  /// Servicio historico. Los dos casos no resolubles llevan texto
  /// propio: nunca se imprime un renglon en blanco ni se reparte su
  /// carga entre los servicios reales.
  static String _nombreServicio(ProblemaPorServicio s) => switch (s.estado) {
        EstadoServicioHistorico.resuelto => s.nombre!,
        EstadoServicioHistorico.sinAsignacion => 'Sin servicio historico resoluble',
        EstadoServicioHistorico.inconsistente => 'Inconsistencia de asignacion',
      };

  List<pw.Widget> _filasServicios(AnalisisPatrimonio a) {
    final mostrados = a.problemasPorServicio.take(_tope).toList();
    return [
      for (final servicio in mostrados)
        construirFilaReporte(
          _nombreServicio(servicio),
          '${servicio.bajas} baja(s), ${servicio.pendientes} pendiente(s), ${servicio.perdidos} perdido(s) - '
              '${formatearMonedaReporte(servicio.importeDescuentos)}',
        ),
      if (a.problemasPorServicio.length > mostrados.length)
        construirFilaReporte('Otros servicios', '${a.problemasPorServicio.length - mostrados.length}'),
    ];
  }

  List<pw.Widget> _filasAutorizadores(AnalisisPatrimonio a) {
    final mostrados = a.autorizadores.take(_tope).toList();
    return [
      for (final autorizador in mostrados)
        construirFilaReporte(
          autorizador.nombre,
          '${autorizador.decisiones} decision(es), ${autorizador.decisionesSinCobro} sin cobro - '
              '${formatearMonedaReporte(autorizador.importeInvolucrado)}',
        ),
      if (a.autorizadores.length > mostrados.length)
        construirFilaReporte('Otros autorizadores', '${a.autorizadores.length - mostrados.length}'),
    ];
  }

  List<pw.Widget> _filasDescuentos(AnalisisPatrimonio a) {
    return [
      construirFilaReporte('Importe generado', formatearMonedaReporte(a.importeDescuentos), destacado: true),
      construirFilaReporte('Aplicado', formatearMonedaReporte(a.aplicadoDescuentos)),
      construirFilaReporte('Saldo por cobrar', formatearMonedaReporte(a.saldoDescuentos)),
      construirFilaReporte('Decisiones sin cobro', '${a.decisionesSinCobro}'),
      // Es el valor del bien, no una obligacion perdonada: nunca existio
      // un descuento que condonar.
      construirFilaReporte('Valor de los bienes no cobrados', formatearMonedaReporte(a.importeNoCobrado)),
    ];
  }
}
