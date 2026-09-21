/// Rango de fechas seleccionado en la cabecera del Dashboard (Parte B
/// del rediseño gerencial) — única fuente de verdad: todo lo que el
/// periodo afecta (ingresos, egresos, resultado, gráfica financiera,
/// cobranza, altas/bajas, actividad reciente) lee este mismo valor,
/// nunca un rango calculado por separado en cada bloque.
///
/// Deliberadamente **no** afecta cobertura/vacantes actuales (Parte B:
/// "El periodo NO debe falsear la cobertura actual") — esos bloques
/// siempre usan `DateTime.now()` sin importar el periodo elegido aquí.
enum TipoPeriodoDashboard { hoy, semana, mes, personalizado }

class PeriodoDashboard {
  const PeriodoDashboard({required this.tipo, required this.inicio, required this.fin});

  final TipoPeriodoDashboard tipo;

  /// Inclusive, sin hora (00:00 del día).
  final DateTime inicio;

  /// Inclusive, sin hora (00:00 del día) — el rango cubre hasta el
  /// final de este día en las consultas que lo usan como límite
  /// superior de fecha/hora.
  final DateTime fin;

  static DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  factory PeriodoDashboard.hoy(DateTime ahora) {
    final hoy = _soloFecha(ahora);
    return PeriodoDashboard(tipo: TipoPeriodoDashboard.hoy, inicio: hoy, fin: hoy);
  }

  /// Semana de calendario en curso, lunes a hoy (nunca hasta el
  /// domingo si hoy es, por ejemplo, miércoles — un periodo nunca se
  /// adelanta al futuro).
  factory PeriodoDashboard.semana(DateTime ahora) {
    final hoy = _soloFecha(ahora);
    final inicio = hoy.subtract(Duration(days: hoy.weekday - 1));
    return PeriodoDashboard(tipo: TipoPeriodoDashboard.semana, inicio: inicio, fin: hoy);
  }

  /// Mes de calendario en curso, día 1 a hoy.
  factory PeriodoDashboard.mes(DateTime ahora) {
    final hoy = _soloFecha(ahora);
    final inicio = DateTime(ahora.year, ahora.month, 1);
    return PeriodoDashboard(tipo: TipoPeriodoDashboard.mes, inicio: inicio, fin: hoy);
  }

  factory PeriodoDashboard.personalizado({required DateTime inicio, required DateTime fin}) {
    return PeriodoDashboard(tipo: TipoPeriodoDashboard.personalizado, inicio: _soloFecha(inicio), fin: _soloFecha(fin));
  }

  /// Límite superior real para consultas por `DateTime` con hora
  /// (`fin` + el resto del día) — evita excluir movimientos capturados
  /// después de medianoche del mismo día `fin`.
  DateTime get finConHora => DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999);
}
