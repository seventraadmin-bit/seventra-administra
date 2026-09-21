import 'configuracion_cobro_con_vigencia.dart' show soloFechaCobro;

/// Un rango de fechas cerrado por ambos extremos, ya normalizado a día
/// (sin hora).
typedef RangoFechas = ({DateTime inicio, DateTime fin});

/// La intersección de dos rangos, o `null` si no se tocan.
///
/// `null` en un extremo significa "abierto": un Servicio sin
/// `fechaTermino` sigue vigente, una vigencia sin `fechaFinVigencia` no
/// caduca. Ambos extremos son **inclusivos**: un Servicio que termina
/// el 30/07 prestó servicio ese día.
RangoFechas? intersectarRangos({
  required DateTime aInicio,
  DateTime? aFin,
  required DateTime bInicio,
  DateTime? bFin,
}) {
  final inicioA = soloFechaCobro(aInicio);
  final inicioB = soloFechaCobro(bInicio);
  final finA = aFin == null ? null : soloFechaCobro(aFin);
  final finB = bFin == null ? null : soloFechaCobro(bFin);

  final inicio = inicioA.isAfter(inicioB) ? inicioA : inicioB;
  final DateTime? fin = switch ((finA, finB)) {
    (null, null) => null,
    (final a?, null) => a,
    (null, final b?) => b,
    (final a?, final b?) => a.isBefore(b) ? a : b,
  };

  if (fin != null && fin.isBefore(inicio)) return null;
  return (inicio: inicio, fin: fin ?? inicio);
}

/// El tramo de un periodo comercial que el Servicio **realmente
/// prestó**: la intersección entre el periodo nominal programado y la
/// vida del Servicio (`fechaInicio` → `fechaTermino`).
///
/// `null` cuando no hay intersección — el periodo entero cae fuera de
/// la vida del Servicio y ningún documento debe existir por él. Es la
/// regla que faltaba en el caso real de SPORTIUM DESIERTO: el servicio
/// cerró el 30/07/2026 y la Agenda seguía pidiendo el periodo
/// 21/08–20/09, íntegramente posterior al cierre.
///
/// Decidir contra el **periodo facturable** —y no contra
/// `Servicio.estatus`— es lo que permite que un Servicio terminado el
/// 30/07 conserve su documento legítimo del tramo 21/07–30/07, que se
/// emite el 21/08 con el Servicio ya cerrado.
RangoFechas? calcularPeriodoFacturable({
  required DateTime periodoInicio,
  required DateTime periodoFin,
  required DateTime servicioInicio,
  DateTime? servicioTermino,
}) {
  return intersectarRangos(
    aInicio: periodoInicio,
    aFin: periodoFin,
    bInicio: servicioInicio,
    bFin: servicioTermino,
  );
}
