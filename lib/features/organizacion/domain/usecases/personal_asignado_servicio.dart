import 'package:riseg_one/core/database/app_database.dart';

/// Un Empleado resuelto junto con su `AsignacionServicio` a este
/// Servicio (Etapa 5D) — ensamblado únicamente para la vista de
/// Servicio; nunca se guarda nombre/puesto/teléfono en
/// `AsignacionServicio`, siempre se consulta desde Empleado (Resolución
/// explícita de Marlon).
class PersonalAsignadoServicio {
  const PersonalAsignadoServicio({required this.empleado, required this.asignacion});

  final EmpleadoData empleado;
  final AsignacionServicioData asignacion;

  bool get vigente => asignacion.fechaTermino == null;
}
