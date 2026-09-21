import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart'
    show TipoPeriodoNomina;
import 'package:riseg_one/features/nomina/domain/usecases/calcular_periodo_nomina.dart';

/// Sugiere la fecha del primer descuento a partir de [fechaSolicitud] —
/// **deriva del modelo real de periodos de Nómina**
/// (`calcularPeriodoNomina`), nunca compara solo números de día de
/// forma frágil, para que un cambio futuro en las fechas de pago (hoy
/// día 20/día 5) siga siendo correcto sin tocar esta función.
///
/// Regla operativa de RISEG (solo una SUGERENCIA — el Maestro puede
/// cambiar la fecha libremente antes de confirmar):
/// - día 6 al 20 del mes → paga la Nómina cuyo pago es el día 20 de
///   ESE MISMO mes (primera quincena).
/// - día 21 al fin de mes, o día 1 al 5 del mes siguiente → paga la
///   Nómina cuyo pago es el día 5 (segunda quincena del mes al que
///   pertenece ese pago).
DateTime sugerirPrimeraFechaDescuento(DateTime fechaSolicitud) {
  final dia = fechaSolicitud.day;

  if (dia >= 6 && dia <= 20) {
    return calcularPeriodoNomina(
      anio: fechaSolicitud.year,
      mes: fechaSolicitud.month,
      tipo: TipoPeriodoNomina.primera,
    ).fechaPago;
  }

  if (dia >= 21) {
    return calcularPeriodoNomina(
      anio: fechaSolicitud.year,
      mes: fechaSolicitud.month,
      tipo: TipoPeriodoNomina.segunda,
    ).fechaPago;
  }

  // día 1 al 5: pertenece a la segunda quincena del MES ANTERIOR (la
  // que paga el día 5 de este mes).
  final mesAnterior = fechaSolicitud.month == 1 ? 12 : fechaSolicitud.month - 1;
  final anioMesAnterior =
      fechaSolicitud.month == 1 ? fechaSolicitud.year - 1 : fechaSolicitud.year;
  return calcularPeriodoNomina(
    anio: anioMesAnterior,
    mes: mesAnterior,
    tipo: TipoPeriodoNomina.segunda,
  ).fechaPago;
}
