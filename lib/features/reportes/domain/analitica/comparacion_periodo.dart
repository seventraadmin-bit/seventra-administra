/// Comparación de una métrica contra el periodo inmediatamente
/// anterior (§5 del rediseño de Reportes).
///
/// Es **pura**: no consulta nada, no conoce repositorios y no formatea
/// moneda. Recibe dos números ya calculados por la misma fuente de
/// verdad y decide qué se puede decir honestamente sobre el cambio.
library;

/// Para qué lado es bueno que se mueva una métrica.
///
/// No existe una regla universal: que suban los Ingresos es bueno, que
/// suba el gasto es malo, que suba la cartera vencida es malo, que
/// suban las bajas de personal es malo. Cada KPI declara la suya — el
/// componente nunca la adivina por el signo.
enum SentidoFavorable {
  /// Más es mejor: Ingresos, resultado operativo, plantilla activa.
  masEsMejor,

  /// Menos es mejor: gasto operativo, cartera vencida, bajas.
  menosEsMejor,

  /// Ni bueno ni malo por sí mismo — se muestra el cambio sin color de
  /// juicio (ej. número de compras del periodo).
  neutro,
}

/// Cómo se debe pintar la variación. Deliberadamente separado de
/// [SentidoFavorable]: el sentido es una propiedad del indicador, el
/// tono es el resultado de aplicarlo a un delta concreto.
enum TonoVariacion { favorable, desfavorable, neutro }

/// Variación de una métrica entre dos periodos de la misma longitud.
class VariacionPeriodo {
  const VariacionPeriodo({required this.actual, required this.anterior, required this.sentido});

  final num actual;
  final num anterior;
  final SentidoFavorable sentido;

  num get delta => actual - anterior;

  /// Cambio relativo como fracción (0.15 == +15 %).
  ///
  /// `null` cuando [anterior] es cero: dividir entre cero daría
  /// infinito y "+∞ %" no le dice nada a nadie. La UI muestra
  /// "Sin base comparable" en ese caso (§5) — nunca un porcentaje
  /// inventado, y nunca "+100 %", que afirmaría una base que no
  /// existió.
  double? get porcentaje {
    if (anterior == 0) return null;
    return delta / anterior.abs();
  }

  /// `true` cuando no hay con qué comparar. Incluye el caso
  /// `anterior == 0 && actual == 0`: tampoco ahí hay una historia que
  /// contar.
  bool get sinBaseComparable => anterior == 0;

  bool get sinCambio => delta == 0;

  TonoVariacion get tono {
    if (delta == 0 || sentido == SentidoFavorable.neutro) return TonoVariacion.neutro;
    final subio = delta > 0;
    final bueno = sentido == SentidoFavorable.masEsMejor ? subio : !subio;
    return bueno ? TonoVariacion.favorable : TonoVariacion.desfavorable;
  }
}

/// Rango de fechas cerrado por ambos extremos.
class RangoPeriodo {
  const RangoPeriodo({required this.inicio, required this.fin});

  final DateTime inicio;
  final DateTime fin;

  /// Días que abarca, contando ambos extremos (un rango de un solo día
  /// mide 1, no 0).
  int get dias => fin.difference(inicio).inDays + 1;

  /// El PRIMER instante del rango: [inicio] a medianoche.
  ///
  /// ## Por qué existe, y es un defecto medido
  ///
  /// Un `RangoPeriodo` es un rango **de días**, pero sus extremos son
  /// `DateTime`, así que al pasarlos a una consulta hay que decidir qué
  /// instante del día significan. Esa decisión estaba escrita **dentro de un
  /// solo llamador** —`ObtenerAnalisisOperativoUseCase`, que extendía el
  /// final al último instante del día— y los demás pasaban `inicio` y `fin`
  /// crudos.
  ///
  /// El resultado, descubierto el 6-nov-2026: **todo lo registrado HOY salía
  /// en el KPI y faltaba en su propio desglose.** El KPI de «Salidas de
  /// efectivo» decía $12,500 y la tabla de «Egresos por categoría» sumaba
  /// $4,500, porque el pago de hoy caía después de `fin` a medianoche. Lo
  /// mismo en el detalle que se abre en Excel, y lo mismo en los cuatro
  /// cálculos de la pestaña de Operación.
  ///
  /// Con los extremos en el TIPO no hay forma de que dos capas interpreten
  /// el mismo rango de dos maneras: no es que haya que acordarse de extender
  /// el final, es que no hay otro final que pasar.
  DateTime get desde => DateTime(inicio.year, inicio.month, inicio.day);

  /// El ÚLTIMO instante del rango: [fin] a las 23:59:59.999.
  ///
  /// **No es `fin` a secas, y ésa es toda la cuestión.** Si el llamador pasa
  /// la fecha a medianoche —que es lo que hacen los presets—, un movimiento
  /// registrado esa misma tarde queda fuera del reporte sin que nadie lo
  /// note: el día en curso aparece vacío y nada falla. Ver [desde].
  DateTime get hasta => DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999);

  /// El periodo inmediatamente anterior, de la MISMA longitud en días y
  /// terminando justo el día antes de [inicio].
  ///
  /// Deliberadamente por días y no por mes calendario: comparar "del 1
  /// al 15 de septiembre" contra "todo agosto" produciría una caída
  /// falsa del 50 %. Si el usuario elige un mes completo, la longitud
  /// en días ya hace que el anterior sea el mes anterior completo (o
  /// casi, en febrero — y esa diferencia es real, no un artefacto).
  RangoPeriodo get anterior {
    final finAnterior = inicio.subtract(const Duration(days: 1));
    return RangoPeriodo(inicio: finAnterior.subtract(Duration(days: dias - 1)), fin: finAnterior);
  }
}
