/// Traducción código→texto y código→color de la capa analítica.
///
/// Todo junto en un archivo porque es exactamente la misma clase de
/// decisión repetida cuatro veces: el dominio entrega claves estables y
/// la UI decide cómo se ven. Que un `OrigenEgreso` tenga el mismo color
/// en la gráfica de General y en la de Finanzas no puede depender de
/// que alguien recuerde copiar el `switch`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';

import '../../domain/analitica/comparacion_periodo.dart';
import '../../domain/analitica/granularidad_serie.dart';
import '../../domain/usecases/clasificar_egresos_por_origen_usecase.dart';

// Eje de gráfica: `d/MM` es el formato que ya usa la única otra gráfica
// del proyecto (`GraficaFinanciera`), y es el único que cabe en el ancho
// de una columna.
final _formatoEjeDia = DateFormat('d/MM');
// Nombre de mes en español, con el mismo locale que el resto del
// proyecto (`planeacion_financiera`, `agenda`).
final _formatoEjeMes = DateFormat('MMM', 'es_MX');
// Fecha suelta en texto corrido: `dd/MM/yyyy`, la convención del
// proyecto (60+ usos) — no un formato propio de Reportes.
final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Etiqueta corta de una cubeta en el eje de la gráfica.
String etiquetaCubeta(DateTime cubeta, GranularidadSerie granularidad) => switch (granularidad) {
      GranularidadSerie.dia => _formatoEjeDia.format(cubeta),
      // La semana se nombra por su lunes: es la convención que ya usa
      // `GranularidadSerie.cubetaDe`, y un rango "7-13/09" no cabe en
      // el ancho de una columna.
      GranularidadSerie.semana => _formatoEjeDia.format(cubeta),
      GranularidadSerie.mes => _formatoEjeMes.format(cubeta),
    };

String etiquetaFechaCorta(DateTime fecha) => _formatoFecha.format(fecha);

String etiquetaGranularidad(AppLocalizations l10n, GranularidadSerie granularidad) => switch (granularidad) {
      GranularidadSerie.dia => l10n.reportesGranularidadDia,
      GranularidadSerie.semana => l10n.reportesGranularidadSemana,
      GranularidadSerie.mes => l10n.reportesGranularidadMes,
    };

String etiquetaOrigenEgreso(AppLocalizations l10n, OrigenEgreso origen) => switch (origen) {
      OrigenEgreso.compra => l10n.reportesFinanzasOrigenCompra,
      OrigenEgreso.nomina => l10n.reportesFinanzasOrigenNomina,
      OrigenEgreso.tiempoExtra => l10n.reportesFinanzasOrigenTiempoExtra,
      OrigenEgreso.deuda => l10n.reportesFinanzasOrigenDeuda,
      OrigenEgreso.descuentoProgramado => l10n.reportesFinanzasOrigenDescuentoProgramado,
      OrigenEgreso.vehiculo => l10n.reportesFinanzasOrigenVehiculo,
      OrigenEgreso.telefonia => l10n.recargaOrigenEtiquetaTelefonia,
      OrigenEgreso.servicioEventual => l10n.egresosOrigenServicioEventual,
      OrigenEgreso.manual => l10n.reportesFinanzasOrigenManual,
    };

/// Color estable por origen de gasto, tomado de la paleta categórica.
///
/// Cada origen tiene un índice FIJO: que Nómina sea siempre del mismo
/// azul no puede depender del orden en que quedó la composición de este
/// periodo. Antes cuatro de los siete orígenes caían en variantes del
/// mismo azul (`accent`, `info` y dos mezclas de ambos) y la barra
/// apilada era ilegible.
///
/// Ninguno usa rojo: el gasto operativo no es un riesgo por sí mismo.
Color colorOrigenEgreso(BuildContext context, OrigenEgreso origen) => context.colorCategorico(switch (origen) {
      OrigenEgreso.nomina => 0, // azul corporativo — casi siempre el mayor
      OrigenEgreso.compra => 1, // ámbar
      OrigenEgreso.tiempoExtra => 2, // teal
      OrigenEgreso.manual => 3, // gris cálido
      OrigenEgreso.telefonia => 7, // el último libre de la paleta
      OrigenEgreso.descuentoProgramado => 4, // ciruela
      OrigenEgreso.vehiculo => 5, // verde
      OrigenEgreso.servicioEventual => 8, // oliva — 9a categoría
      // Nunca aparece en la composición del gasto (pagar una deuda no es
      // gasto), pero la función tiene que ser total.
      OrigenEgreso.deuda => 6,
    });

/// Color por estado físico de una unidad de Inventario.
///
/// Mezcla deliberada de semántica y paleta: `disponible` y `asignado`
/// SÍ significan algo (se puede entregar / está en manos de alguien) y
/// usan su token semántico; los estados intermedios no significan
/// bueno ni malo y usan la paleta. El rojo se reserva para `perdido`,
/// la única pérdida real — antes tres estados distintos compartían el
/// mismo rojo y dos más el mismo ámbar.
Color colorEstatusUnidad(BuildContext context, String estatus) {
  final colors = context.colors;
  return switch (EstatusArticuloUnidad.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusArticuloUnidad.disponible => colors.success,
    EstatusArticuloUnidad.asignado => context.colorCategorico(0),
    EstatusArticuloUnidad.enLavanderia => context.colorCategorico(2),
    EstatusArticuloUnidad.enReparacion => context.colorCategorico(1),
    EstatusArticuloUnidad.pendienteDesecho => context.colorCategorico(4),
    EstatusArticuloUnidad.danado => context.colorCategorico(6),
    EstatusArticuloUnidad.perdido => colors.error,
    EstatusArticuloUnidad.baja => context.colorCategorico(3),
    null => colors.neutralText,
  };
}

String etiquetaCubetaAntiguedad(AppLocalizations l10n, RangoAntiguedadCuentaPorCobrar cubeta) => switch (cubeta) {
      RangoAntiguedadCuentaPorCobrar.alCorriente => l10n.reportesFinanzasAntiguedadAlCorriente,
      RangoAntiguedadCuentaPorCobrar.dias0a30 => l10n.reportesFinanzasAntiguedad0a30,
      RangoAntiguedadCuentaPorCobrar.dias31a60 => l10n.reportesFinanzasAntiguedad31a60,
      RangoAntiguedadCuentaPorCobrar.dias61a90 => l10n.reportesFinanzasAntiguedad61a90,
      RangoAntiguedadCuentaPorCobrar.dias90Mas => l10n.reportesFinanzasAntiguedad90Mas,
    };

/// Gravedad creciente conforme la deuda envejece — no es decorativo: es
/// la lectura del reporte.
RisegStatusTone tonoCubetaAntiguedad(RangoAntiguedadCuentaPorCobrar cubeta) => switch (cubeta) {
      RangoAntiguedadCuentaPorCobrar.alCorriente => RisegStatusTone.success,
      RangoAntiguedadCuentaPorCobrar.dias0a30 => RisegStatusTone.info,
      RangoAntiguedadCuentaPorCobrar.dias31a60 => RisegStatusTone.warning,
      RangoAntiguedadCuentaPorCobrar.dias61a90 => RisegStatusTone.warning,
      RangoAntiguedadCuentaPorCobrar.dias90Mas => RisegStatusTone.error,
    };

/// Cómo se escribe y se tiñe una variación en una `RisegStatCard`.
///
/// Aquí se cumple la regla de no mentir con la comparación: sin base
/// comparable se dice justamente eso, y el color lo decide el sentido
/// declarado por el indicador, no el signo del número.
({String texto, RisegStatusTone tono}) deltaDeVariacion(AppLocalizations l10n, VariacionPeriodo variacion) {
  if (variacion.sinBaseComparable) {
    return (texto: l10n.reportesComparacionSinBase, tono: RisegStatusTone.neutral);
  }
  if (variacion.sinCambio) {
    return (texto: l10n.reportesComparacionSinCambio, tono: RisegStatusTone.neutral);
  }
  final porcentaje = variacion.porcentaje! * 100;
  // Se usa el guion normal y no el signo menos tipográfico: el mismo
  // texto puede terminar en una exportación, y en Helvetica los guiones
  // largos/tipográficos no existen (gotcha ya documentado del proyecto).
  final signo = porcentaje > 0 ? '+' : '-';
  final magnitud = porcentaje.abs();
  final texto = '$signo${magnitud < 10 ? magnitud.toStringAsFixed(1) : magnitud.toStringAsFixed(0)} %';
  return (
    texto: l10n.reportesComparacionVariacion(texto),
    tono: switch (variacion.tono) {
      TonoVariacion.favorable => RisegStatusTone.success,
      TonoVariacion.desfavorable => RisegStatusTone.error,
      TonoVariacion.neutro => RisegStatusTone.neutral,
    },
  );
}

/// Solo la magnitud con signo ("+18 %"), para intercalarla en una frase.
String textoVariacionCorta(VariacionPeriodo variacion) {
  if (variacion.porcentaje == null) return '';
  final porcentaje = variacion.porcentaje! * 100;
  final signo = porcentaje > 0 ? '+' : '-';
  final magnitud = porcentaje.abs();
  return '$signo${magnitud < 10 ? magnitud.toStringAsFixed(1) : magnitud.toStringAsFixed(0)} %';
}

/// Importe compacto para ejes de gráfica ("$12 k", "$1.4 M").
///
/// Los ejes tienen un ancho de pocas decenas de píxeles: escribir
/// "$1,432,500.00" ahí obligaría a comerse la mitad del área de dibujo.
/// El importe exacto siempre está en el tooltip y en el KPI, así que
/// aquí la precisión se cambia por legibilidad a conciencia.
String formatoCentavosCompacto(int centavos) {
  final pesos = centavos / 100;
  final signo = pesos < 0 ? '-' : '';
  final abs = pesos.abs();
  if (abs >= 1000000) return '$signo\$${(abs / 1000000).toStringAsFixed(1)} M';
  if (abs >= 1000) return '$signo\$${(abs / 1000).toStringAsFixed(0)} k';
  return '$signo\$${abs.toStringAsFixed(0)}';
}

/// Cantidad simple (personas, unidades, documentos) para ejes y
/// leyendas — el mismo hueco que `formatoCentavosCompacto` llena para
/// dinero.
String formatoCantidad(int valor) => '$valor';
