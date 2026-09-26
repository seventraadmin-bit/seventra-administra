import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/export/reporte_export_context.dart';
import '../../domain/analitica/obtener_analisis_cobranza_usecase.dart';
import '../../domain/analitica/obtener_analisis_deuda_usecase.dart';
import '../../domain/analitica/obtener_analisis_pagos_usecase.dart';
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
          construirSeccionReporte('Resumen financiero', [
            construirFilaReporte('Ingresos', formatearMonedaReporte(state.totalIngresos)),
            construirFilaReporte('Gasto operativo', formatearMonedaReporte(state.gastoOperativo)),
            construirFilaReporte('Salidas de efectivo', formatearMonedaReporte(state.salidasDeEfectivo)),
            construirFilaReporte('Cargado a tarjetas', formatearMonedaReporte(state.cargosDeTarjeta)),
            construirFilaReporte('Resultado operativo', formatearMonedaReporte(state.resultadoOperativo), destacado: true),
            construirFilaReporte('Pagos recibidos', formatearMonedaReporte(state.totalPagosRecibidos)),
          ]),
          if (state.egresosPorOrigen != null) construirSeccionReporte('Egresos por origen', _filasOrigen(state.egresosPorOrigen!)),
          // Resumen ejecutivo, no un Excel impreso: KPI, antigüedad,
          // concentración, pagos y deuda — cada bloque en una línea por
          // concepto, nunca el detalle fila por fila (para eso está el
          // XLSX de cada sección).
          if (state.cobranza case final cobranza?) construirSeccionReporte('Cartera (a la fecha de hoy)', _filasCartera(cobranza)),
          construirSeccionReporte('Antigüedad de la cartera (a la fecha de hoy)', _filasAging(state)),
          if (state.cobranza case final cobranza?)
            if (cobranza.concentracion.isNotEmpty)
              construirSeccionReporte('Concentración por cliente', _filasConcentracion(cobranza)),
          if (state.pagos case final pagos?) construirSeccionReporte('Pagos del periodo', _filasPagos(pagos)),
          if (state.deuda case final deuda?) construirSeccionReporte('Deuda y crédito', _filasDeuda(deuda)),
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

  List<pw.Widget> _filasCartera(AnalisisCobranza cobranza) {
    final porcentaje = cobranza.porcentajeVencido;
    final atraso = cobranza.diasAtrasoPromedio;
    return [
      construirFilaReporte('Saldo por cobrar', formatearMonedaReporte(cobranza.saldoPendiente), destacado: true),
      construirFilaReporte('Saldo vencido', formatearMonedaReporte(cobranza.saldoVencido)),
      // Sin saldo no hay porcentaje ni promedio: se dice, no se
      // imprime un 0 que afirmaría lo contrario.
      construirFilaReporte('Porcentaje vencido', porcentaje == null ? 'Sin base' : '${(porcentaje * 100).toStringAsFixed(1)} %'),
      construirFilaReporte('Cuentas con saldo', '${cobranza.cuentasConSaldo}'),
      construirFilaReporte('Clientes con saldo', '${cobranza.clientesConSaldo}'),
      construirFilaReporte('Atraso promedio', atraso == null ? 'Sin cartera vencida' : '${atraso.toStringAsFixed(0)} días'),
    ];
  }

  List<pw.Widget> _filasConcentracion(AnalisisCobranza cobranza) {
    return [
      for (final cliente in cobranza.concentracion)
        construirFilaReporte(
          cliente.esOtros ? 'Otros clientes' : cliente.nombre,
          formatearMonedaReporte(cliente.saldo),
        ),
    ];
  }

  List<pw.Widget> _filasPagos(AnalisisPagos pagos) {
    return [
      construirFilaReporte('Pagos recibidos', '${pagos.pagosRecibidos}'),
      construirFilaReporte('Importe recibido', formatearMonedaReporte(pagos.importeRecibido), destacado: true),
      construirFilaReporte('Importe aplicado', formatearMonedaReporte(pagos.importeAplicado)),
      construirFilaReporte('Por aplicar', formatearMonedaReporte(pagos.importePorAplicar)),
      construirFilaReporte('Clientes que pagaron', '${pagos.clientesQuePagaron}'),
      construirFilaReporte('Complementos pendientes', '${pagos.complementosPendientes}'),
      construirFilaReporte('Complementos registrados', '${pagos.complementosRegistrados}'),
    ];
  }

  List<pw.Widget> _filasDeuda(AnalisisDeuda deuda) {
    final utilizacion = deuda.utilizacionGlobal;
    return [
      construirFilaReporte('Deuda total (a la fecha)', formatearMonedaReporte(deuda.saldoTotal), destacado: true),
      construirFilaReporte('Saldo en tarjetas', formatearMonedaReporte(deuda.saldoTarjetas)),
      construirFilaReporte('Otras deudas', formatearMonedaReporte(deuda.saldoOtrasDeudas)),
      construirFilaReporte(
        'Crédito disponible',
        deuda.hayTarjetas ? formatearMonedaReporte(deuda.creditoDisponible) : 'Sin tarjetas activas',
      ),
      construirFilaReporte(
        'Utilización de crédito',
        utilizacion == null ? 'Sin límite capturado' : '${(utilizacion * 100).toStringAsFixed(0)} %',
      ),
      construirFilaReporte('Cargos del periodo', formatearMonedaReporte(deuda.cargosDelPeriodo)),
      construirFilaReporte('Pagos del periodo', formatearMonedaReporte(deuda.pagosDelPeriodo)),
      construirFilaReporte('Ajustes y reversiones', formatearMonedaReporte(deuda.ajustesDelPeriodo)),
    ];
  }

  List<pw.Widget> _filasCategoria(List<TotalPorCategoria> categorias) {
    return [for (final c in categorias) construirFilaReporte(c.nombreCategoria, formatearMonedaReporte(c.total))];
  }
}
