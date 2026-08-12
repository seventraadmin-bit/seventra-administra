import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';

/// "Vencida" nunca se almacena (Etapa 4J.1, Resolución D de Marlon,
/// explícita: "no quiero procesos automáticos diarios solamente para
/// cambiar estados") — se deriva aquí, con `hoy` recibido siempre
/// desde afuera (mismo criterio ya establecido por
/// `CalcularFechasCobroUseCase`: nunca `DateTime.now()` dentro de una
/// función de dominio pura).
bool estaVencida(CuentaPorCobrarData cuenta, DateTime hoy) {
  final vencimiento = cuenta.fechaVencimiento;
  if (vencimiento == null) return false;
  if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.pagada) return false;

  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
  final vencimientoSinHora = DateTime(vencimiento.year, vencimiento.month, vencimiento.day);
  return vencimientoSinHora.isBefore(hoySinHora);
}

/// Rangos estándar de antigüedad de saldos — solo para el reporte de
/// antigüedad (§13 del plan); nunca una columna de la tabla.
enum RangoAntiguedadCuentaPorCobrar { alCorriente, dias0a30, dias31a60, dias61a90, dias90Mas }

RangoAntiguedadCuentaPorCobrar calcularRangoAntiguedad(CuentaPorCobrarData cuenta, DateTime hoy) {
  if (!estaVencida(cuenta, hoy)) return RangoAntiguedadCuentaPorCobrar.alCorriente;

  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
  final vencimientoSinHora = DateTime(
    cuenta.fechaVencimiento!.year,
    cuenta.fechaVencimiento!.month,
    cuenta.fechaVencimiento!.day,
  );
  final dias = hoySinHora.difference(vencimientoSinHora).inDays;

  return switch (dias) {
    <= 30 => RangoAntiguedadCuentaPorCobrar.dias0a30,
    <= 60 => RangoAntiguedadCuentaPorCobrar.dias31a60,
    <= 90 => RangoAntiguedadCuentaPorCobrar.dias61a90,
    _ => RangoAntiguedadCuentaPorCobrar.dias90Mas,
  };
}

/// Días que faltan para el vencimiento (Etapa 14B) — hacia adelante,
/// a diferencia de `estaVencida`/`calcularRangoAntiguedad` (ambas
/// retrospectivas). `null` si la cuenta no tiene fecha de vencimiento
/// o ya está `pagada` — ninguna de las dos aplica a "próxima a
/// vencer". `hoy` siempre se recibe desde afuera, mismo criterio que
/// el resto de este archivo.
int? diasParaVencerCxc(CuentaPorCobrarData cuenta, DateTime hoy) {
  final vencimiento = cuenta.fechaVencimiento;
  if (vencimiento == null) return null;
  if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.pagada) return null;

  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
  final vencimientoSinHora = DateTime(vencimiento.year, vencimiento.month, vencimiento.day);
  return vencimientoSinHora.difference(hoySinHora).inDays;
}
