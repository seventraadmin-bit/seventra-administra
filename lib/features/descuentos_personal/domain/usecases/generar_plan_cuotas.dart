import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart'
    show TipoPeriodoNomina;
import 'package:riseg_one/features/nomina/domain/usecases/calcular_periodo_nomina.dart';

import 'dividir_en_cuotas.dart';

/// La fecha de pago de Nómina (día 20 o día 5) estrictamente posterior
/// a [fecha] — deriva del modelo real de periodos
/// (`calcularPeriodoNomina`), nunca suma días fijos (`+15`), que se
/// desalinea con meses de 28/30/31 días. Usada para espaciar las
/// cuotas 2..N de un plan de recuperación una quincena real después de
/// la anterior.
DateTime siguienteFechaPagoNomina(DateTime fecha) {
  final candidatoMismoMes =
      calcularPeriodoNomina(
        anio: fecha.year,
        mes: fecha.month,
        tipo: TipoPeriodoNomina.primera,
      ).fechaPago;
  if (candidatoMismoMes.isAfter(fecha)) return candidatoMismoMes;
  return calcularPeriodoNomina(
    anio: fecha.year,
    mes: fecha.month,
    tipo: TipoPeriodoNomina.segunda,
  ).fechaPago;
}

/// Un renglón ya resuelto del plan de recuperación — importe (nunca
/// pierde un centavo, ver `dividirEnCuotas`) + fecha programada.
typedef CuotaPlan = ({int numeroCuota, DateTime fechaProgramada, int importe});

/// Genera el plan de recuperación completo — ÚNICA fuente de verdad,
/// reutilizada por `RegistrarDescuentoProgramadoUseCase`,
/// `ReprogramarCuotasPendientesUseCase` y la previsualización en vivo
/// del diálogo "Registrar descuento" (nunca un cálculo paralelo). La
/// primera cuota cae exactamente en [fechaPrimera] (el Maestro puede
/// elegir cualquier fecha, no forzosamente una quincena real); cada
/// cuota siguiente cae en la siguiente fecha de pago de Nómina real
/// después de la anterior.
List<CuotaPlan> generarPlanCuotas({
  required int importeOriginal,
  required int numeroCuotas,
  required DateTime fechaPrimera,
}) {
  final importes = dividirEnCuotas(
    importeOriginal: importeOriginal,
    numeroCuotas: numeroCuotas,
  );

  final plan = <CuotaPlan>[];
  var fecha = fechaPrimera;
  for (final c in importes) {
    plan.add((
      numeroCuota: c.numeroCuota,
      fechaProgramada: fecha,
      importe: c.importe,
    ));
    fecha = siguienteFechaPagoNomina(fecha);
  }
  return plan;
}
