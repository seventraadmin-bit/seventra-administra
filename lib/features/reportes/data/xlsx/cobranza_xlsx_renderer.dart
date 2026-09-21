import 'package:excel/excel.dart';

import '../../domain/analitica/obtener_analisis_cobranza_usecase.dart';
import '../../domain/analitica/obtener_analisis_deuda_usecase.dart';
import '../../domain/analitica/obtener_analisis_pagos_usecase.dart';
import '../../domain/export/reporte_export_context.dart';
import 'reporte_xlsx_utils.dart';

/// Etiquetas de exportación.
///
/// Deliberadamente constantes locales y no `AppLocalizations`: un
/// renderizador no tiene `BuildContext`, y el resto de los XLSX del
/// proyecto ya resuelven así sus etiquetas. Los textos coinciden con los
/// de pantalla.
const _cubetaLabel = {
  'alCorriente': 'Al corriente',
  'dias0a30': '0-30 días',
  'dias31a60': '31-60 días',
  'dias61a90': '61-90 días',
  'dias90Mas': 'Más de 90 días',
};

const _complementoLabel = {
  EstadoComplementoPago.noAplica: 'No aplica',
  EstadoComplementoPago.pendiente: 'Pendiente',
  EstadoComplementoPago.registrado: 'Registrado',
};

const _tipoMovimientoLabel = {
  'altaInicial': 'Apertura',
  'cargoCompra': 'Cargo',
  'pago': 'Pago',
  'ajustePositivo': 'Ajuste (+)',
  'ajusteNegativo': 'Ajuste (-)',
  'cancelacion': 'Cancelación',
  'reversionPago': 'Reversión de pago',
};

const _origenMovimientoLabel = {
  OrigenMovimientoDeuda.compra: 'Compra',
  OrigenMovimientoDeuda.tiempoExtra: 'Tiempo extra',
  OrigenMovimientoDeuda.costoAdicionalTiempoExtra: 'Costo adicional de tiempo extra',
  OrigenMovimientoDeuda.vehiculo: 'Vehículo',
  OrigenMovimientoDeuda.egreso: 'Egreso',
  OrigenMovimientoDeuda.pago: 'Pago de la deuda',
  OrigenMovimientoDeuda.apertura: 'Apertura',
  OrigenMovimientoDeuda.sinOrigen: 'Sin origen',
};

/// XLSX de Cuentas por cobrar — **una fila por CxC**.
///
/// Recibe la lista YA filtrada por la pantalla, así que el archivo
/// contiene exactamente el mismo universo que el usuario está viendo:
/// no vuelve a consultar ni re-filtra por su cuenta.
class CuentasPorCobrarXlsxRenderer {
  List<int> generar({
    required ReporteExportContext contexto,
    required List<CuentaPorCobrarProyectada> cuentas,
  }) {
    final excel = crearWorkbookConInfo(contexto);

    final hoja = excel['Cuentas por cobrar'];
    hoja.appendRow([
      TextCellValue('Cliente'),
      TextCellValue('Entidad fiscal'),
      TextCellValue('Servicio'),
      TextCellValue('Documento'),
      TextCellValue('Emisión'),
      TextCellValue('Pago esperado'),
      TextCellValue('Método'),
      TextCellValue('Estado'),
      TextCellValue('Antigüedad'),
      TextCellValue('Días de atraso'),
      TextCellValue('Complemento'),
      TextCellValue('Total'),
      TextCellValue('Aplicado'),
      TextCellValue('Saldo'),
    ]);

    for (final c in cuentas) {
      hoja.appendRow([
        TextCellValue(c.clienteNombre),
        TextCellValue(c.entidadFiscalNombre ?? '—'),
        TextCellValue(c.serviciosNombres.isEmpty ? '—' : c.serviciosNombres.join(' / ')),
        TextCellValue(c.cuenta.folioDocumento ?? '—'),
        TextCellValue(formatearFechaCortaXlsx(c.cuenta.fechaEmisionReal)),
        TextCellValue(c.cuenta.fechaVencimiento == null ? '—' : formatearFechaCortaXlsx(c.cuenta.fechaVencimiento!)),
        TextCellValue(c.cuenta.metodo.toUpperCase()),
        TextCellValue(c.cuenta.estatus),
        TextCellValue(_cubetaLabel[c.cubeta.name] ?? c.cubeta.name),
        // Sin atraso se exporta vacío, no 0: cero días de atraso
        // significaría "vence hoy".
        c.diasAtraso == null ? TextCellValue('—') : IntCellValue(c.diasAtraso!),
        TextCellValue(c.complementoPendiente ? 'Pendiente' : '—'),
        DoubleCellValue(c.cuenta.importeEmitido / 100),
        DoubleCellValue(c.aplicado / 100),
        DoubleCellValue(c.saldo / 100),
      ]);
    }

    return excel.encode()!;
  }
}

/// XLSX de Pagos — hoja principal con **una fila por Pago** y una hoja
/// secundaria con las aplicaciones.
///
/// Nunca se repite el Pago en la hoja principal: un pago de $50,000
/// aplicado a dos facturas aparece una vez en "Pagos" (por $50,000) y
/// dos veces en "Aplicaciones" (por $20,000 y $30,000). Sumar la hoja
/// principal da el importe recibido real.
class PagosXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required List<PagoProyectado> pagos}) {
    final excel = crearWorkbookConInfo(contexto);

    final hoja = excel['Pagos'];
    hoja.appendRow([
      TextCellValue('Folio'),
      TextCellValue('Fecha'),
      TextCellValue('Cliente'),
      TextCellValue('Forma de pago'),
      TextCellValue('Cuenta financiera'),
      TextCellValue('Documentos cubiertos'),
      TextCellValue('Complemento'),
      TextCellValue('Importe'),
      TextCellValue('Aplicado'),
      TextCellValue('Por aplicar'),
    ]);

    for (final p in pagos) {
      hoja.appendRow([
        TextCellValue(p.pago.folioPago),
        TextCellValue(formatearFechaCortaXlsx(p.pago.fechaPago)),
        TextCellValue(p.clienteNombre),
        TextCellValue(p.pago.formaPago),
        TextCellValue(p.cuentaFinancieraNombre ?? '—'),
        IntCellValue(p.documentosCubiertos),
        TextCellValue(_complementoLabel[p.estadoComplemento] ?? ''),
        DoubleCellValue(p.importe / 100),
        DoubleCellValue(p.aplicado / 100),
        DoubleCellValue(p.porAplicar / 100),
      ]);
    }

    final aplicaciones = excel['Aplicaciones'];
    aplicaciones.appendRow([
      TextCellValue('Folio del pago'),
      TextCellValue('Fecha'),
      TextCellValue('Cliente'),
      TextCellValue('Documento cubierto'),
      TextCellValue('Importe aplicado'),
    ]);
    for (final p in pagos) {
      for (final a in p.aplicaciones) {
        aplicaciones.appendRow([
          TextCellValue(p.pago.folioPago),
          TextCellValue(formatearFechaCortaXlsx(p.pago.fechaPago)),
          TextCellValue(p.clienteNombre),
          TextCellValue(a.folioDocumento ?? '—'),
          DoubleCellValue(a.monto / 100),
        ]);
      }
    }

    return excel.encode()!;
  }
}

/// XLSX de Deudas — resumen por deuda y movimientos en hoja aparte.
class DeudasXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required AnalisisDeuda analisis}) {
    final excel = crearWorkbookConInfo(contexto);

    final hoja = excel['Deudas'];
    hoja.appendRow([
      TextCellValue('Deuda'),
      TextCellValue('Tipo'),
      TextCellValue('Saldo actual'),
      TextCellValue('Límite de crédito'),
      TextCellValue('Disponible'),
      TextCellValue('% utilizado'),
      TextCellValue('Próximo corte'),
      TextCellValue('Fecha límite de pago'),
    ]);

    final tarjetaPorId = {for (final t in analisis.tarjetas) t.deuda.id: t};
    for (final deuda in analisis.deudas) {
      final tarjeta = tarjetaPorId[deuda.id];
      hoja.appendRow([
        TextCellValue(deuda.nombre),
        TextCellValue(deuda.tipo),
        DoubleCellValue(deuda.saldoActual / 100),
        // Un límite/disponible/utilización sin capturar se exporta como
        // guion, nunca como 0: "no sabemos" no es "no hay".
        tarjeta?.limite == null ? TextCellValue('—') : DoubleCellValue(tarjeta!.limite! / 100),
        tarjeta?.disponible == null ? TextCellValue('—') : DoubleCellValue(tarjeta!.disponible! / 100),
        tarjeta?.utilizacion == null
            ? TextCellValue('—')
            : DoubleCellValue(double.parse((tarjeta!.utilizacion! * 100).toStringAsFixed(1))),
        TextCellValue(tarjeta?.proximoCorte == null ? '—' : formatearFechaCortaXlsx(tarjeta!.proximoCorte!)),
        TextCellValue(
          tarjeta?.proximaFechaLimite == null ? '—' : formatearFechaCortaXlsx(tarjeta!.proximaFechaLimite!),
        ),
      ]);
    }

    final movimientos = excel['Movimientos'];
    movimientos.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Deuda'),
      TextCellValue('Tipo'),
      TextCellValue('Origen'),
      TextCellValue('Importe'),
      TextCellValue('Efecto en saldo'),
      TextCellValue('Saldo posterior'),
    ]);
    for (final m in analisis.movimientos) {
      movimientos.appendRow([
        TextCellValue(formatearFechaCortaXlsx(m.fecha)),
        TextCellValue(m.deudaNombre),
        TextCellValue(_tipoMovimientoLabel[m.tipo.name] ?? m.tipo.name),
        TextCellValue(_origenMovimientoLabel[m.origen] ?? m.origen.name),
        DoubleCellValue(m.movimiento.importe / 100),
        DoubleCellValue(m.efectoEnSaldo / 100),
        DoubleCellValue(m.movimiento.saldoPosterior / 100),
      ]);
    }

    return excel.encode()!;
  }
}
