import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

/// Ciclo laboral del periodo **vigente** de un Empleado (Etapa 5C) —
/// antigüedad nunca acumula periodos anteriores (Resolución explícita
/// de Marlon: "un reingreso inicia una nueva antigüedad desde cero").
/// Nunca se almacena, mismo criterio que `calcularEdad`/`estaVencida`.
class CicloLaboralEmpleado {
  const CicloLaboralEmpleado({
    required this.antiguedadAnios,
    required this.antiguedadMeses,
    required this.diasLaborados,
    this.fechaProximoAniversario,
  });

  final int antiguedadAnios;
  final int antiguedadMeses;
  final int diasLaborados;

  /// `null` si el Empleado está de baja — un aniversario solo tiene
  /// sentido operativo mientras el periodo sigue vigente.
  final DateTime? fechaProximoAniversario;
}

/// Deriva antigüedad/días laborados/próximo aniversario a partir del
/// periodo laboral vigente de `empleado` (`fechaIngreso`/`estatus`/
/// `fechaBaja`) — nunca de `EmpleadoPeriodoLaboral` (eso es historial
/// administrativo, fuera de este cálculo). `hoy` siempre se recibe
/// desde afuera, nunca `DateTime.now()` interno (mismo criterio que
/// `CalcularFechasCobroUseCase`/`estaVencida`).
CicloLaboralEmpleado calcularCicloLaboralEmpleado(EmpleadoData empleado, {DateTime? hoy}) {
  final referencia = hoy ?? DateTime.now();
  final activo = EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.activo;
  final hasta = activo ? referencia : (empleado.fechaBaja ?? referencia);
  final ingreso = empleado.fechaIngreso;

  var anios = hasta.year - ingreso.year;
  var meses = hasta.month - ingreso.month;
  if (hasta.day < ingreso.day) meses--;
  if (meses < 0) {
    anios--;
    meses += 12;
  }
  if (anios < 0) {
    anios = 0;
    meses = 0;
  }

  final diasLaborados = hasta.difference(ingreso).inDays;

  DateTime? proximoAniversario;
  if (activo) {
    var candidato = DateTime(referencia.year, ingreso.month, ingreso.day);
    if (!candidato.isAfter(referencia)) {
      candidato = DateTime(referencia.year + 1, ingreso.month, ingreso.day);
    }
    proximoAniversario = candidato;
  }

  return CicloLaboralEmpleado(
    antiguedadAnios: anios,
    antiguedadMeses: meses,
    diasLaborados: diasLaborados < 0 ? 0 : diasLaborados,
    fechaProximoAniversario: proximoAniversario,
  );
}
