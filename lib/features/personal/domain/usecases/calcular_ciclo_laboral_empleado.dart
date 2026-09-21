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
    required this.antiguedadDiasResiduales,
    required this.diasLaborados,
    this.fechaProximoAniversario,
  });

  final int antiguedadAnios;
  final int antiguedadMeses;

  /// Días transcurridos desde el último mesiversario completo — el
  /// mismo criterio de "día de corte" que ya usa `antiguedadMeses`
  /// (`hasta.day < ingreso.day` pide prestado un mes), solo que medido
  /// en días en vez de en meses. Existe únicamente para presentación
  /// compacta ("6 meses 22 días") cuando `antiguedadAnios == 0`; nunca
  /// se usa para decidir ninguna regla de negocio.
  final int antiguedadDiasResiduales;

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
  return calcularCicloLaboralDesdeFechas(
    fechaIngreso: empleado.fechaIngreso,
    estatus: empleado.estatus,
    fechaBaja: empleado.fechaBaja,
    hoy: hoy,
  );
}

/// Misma lógica que [calcularCicloLaboralEmpleado], sin depender de
/// `EmpleadoData` completo — Etapa 12B (Reportes): permite calcularlo
/// sobre `EmpleadoReporteRow` (proyección segura, sin campos sensibles)
/// sin tener que construir un `EmpleadoData` falso solo para satisfacer
/// esta firma.
CicloLaboralEmpleado calcularCicloLaboralDesdeFechas({
  required DateTime fechaIngreso,
  required String estatus,
  DateTime? fechaBaja,
  DateTime? hoy,
}) {
  final referencia = hoy ?? DateTime.now();
  final activo = EstatusEmpleado.values.byName(estatus) == EstatusEmpleado.activo;
  final hasta = activo ? referencia : (fechaBaja ?? referencia);
  final ingreso = fechaIngreso;

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

  // Mismo criterio de corte que arriba (`hasta.day < ingreso.day` pide
  // prestado un mes): el mesiversario más reciente cae en el mes de
  // `hasta` si `hasta.day >= ingreso.day`, o en el mes anterior si no.
  final mesUltimoMesiversario = hasta.day >= ingreso.day ? hasta.month : hasta.month - 1;
  final ultimoMesiversario = DateTime(hasta.year, mesUltimoMesiversario, ingreso.day);
  final diasResiduales = hasta.difference(ultimoMesiversario).inDays;

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
    antiguedadDiasResiduales: diasResiduales < 0 ? 0 : diasResiduales,
    diasLaborados: diasLaborados < 0 ? 0 : diasLaborados,
    fechaProximoAniversario: proximoAniversario,
  );
}
