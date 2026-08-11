import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

/// Advertencia de recontratación (Etapa 5C) — nunca bloquea el
/// Reingreso, solo informa. `motivos` ya viene filtrada a los que
/// generan advertencia (`MotivoBajaEmpleado.generaAdvertenciaRecontratacion`
/// — ver el doc comment del enum sobre por qué esa propiedad vive en
/// cada valor y no en una lista aparte).
class AlertaRecontratacionEmpleado {
  const AlertaRecontratacionEmpleado({required this.motivos});

  final List<MotivoBajaEmpleado> motivos;

  bool get tieneAdvertencia => motivos.isNotEmpty;
}

/// Revisa el motivo de baja del periodo vigente (si el Empleado está de
/// baja ahora mismo) más todos los periodos archivados en
/// `EmpleadoPeriodoLaboral` — nunca decide aquí qué motivos son
/// "negativos"; solo lee `motivoBajaGeneraAdvertenciaRecontratacion` de
/// cada uno.
AlertaRecontratacionEmpleado calcularAlertaRecontratacion(
  EmpleadoData empleado,
  List<EmpleadoPeriodoLaboralData> periodosArchivados,
) {
  return calcularAlertaRecontratacionDesdeMotivo(empleado.motivoBaja, periodosArchivados);
}

/// Misma lógica que [calcularAlertaRecontratacion], sin depender de
/// `EmpleadoData` completo — Etapa 12B (Reportes): permite calcularla
/// sobre `EmpleadoReporteRow` (proyección segura) sin construir un
/// `EmpleadoData` falso solo para satisfacer esa firma.
AlertaRecontratacionEmpleado calcularAlertaRecontratacionDesdeMotivo(
  String? motivoBajaVigente,
  List<EmpleadoPeriodoLaboralData> periodosArchivados,
) {
  final vistos = <MotivoBajaEmpleado>{};
  if (motivoBajaVigente != null) {
    vistos.add(MotivoBajaEmpleado.values.byName(motivoBajaVigente));
  }
  for (final periodo in periodosArchivados) {
    vistos.add(MotivoBajaEmpleado.values.byName(periodo.motivoBaja));
  }

  final conAdvertencia = vistos.where((motivo) => motivo.generaAdvertenciaRecontratacion).toList();
  return AlertaRecontratacionEmpleado(motivos: conAdvertencia);
}
