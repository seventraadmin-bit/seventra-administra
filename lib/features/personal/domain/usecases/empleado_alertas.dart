import 'package:riseg_one/core/database/app_database.dart';

/// Alertas administrativas simples del expediente de un Empleado
/// (Etapa 5B) — "pendiente" significa únicamente que la evaluación
/// correspondiente nunca se capturó (`fecha == null`). Un Antidoping
/// ya capturado con las 5 sustancias en `noAplica` **no** está
/// pendiente: fue evaluado, solo que ese panel no incluyó ninguna de
/// esas sustancias. Deliberadamente sin vencimientos/vigencias — fuera
/// de alcance explícito de esta etapa (Resolución de Marlon: "no
/// quiero vencimientos complejos todavía").
class EmpleadoAlertas {
  const EmpleadoAlertas({
    required this.perfilPsicologicoPendiente,
    required this.estudioSocioeconomicoPendiente,
    required this.antidopingPendiente,
  });

  final bool perfilPsicologicoPendiente;
  final bool estudioSocioeconomicoPendiente;
  final bool antidopingPendiente;

  bool get tieneAlertas => perfilPsicologicoPendiente || estudioSocioeconomicoPendiente || antidopingPendiente;
}

EmpleadoAlertas calcularAlertasEmpleado(EmpleadoData empleado) {
  return EmpleadoAlertas(
    perfilPsicologicoPendiente: empleado.fechaEvaluacionPsicologica == null,
    estudioSocioeconomicoPendiente: empleado.fechaEstudioSocioeconomico == null,
    antidopingPendiente: empleado.fechaAntidoping == null,
  );
}
