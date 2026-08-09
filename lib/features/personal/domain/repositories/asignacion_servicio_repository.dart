import 'package:riseg_one/core/database/app_database.dart';

/// Relación administrativa Empleado↔Servicio (Etapa 5D) — ver el doc
/// comment de `AsignacionServicio` para el criterio de diseño completo.
abstract interface class AsignacionServicioRepository {
  Future<AsignacionServicioData?> obtenerActivaPorEmpleado(String empleadoId);

  /// Historial completo (vigente + cerradas) de este Empleado, orden
  /// descendente por `fechaInicio`.
  Future<List<AsignacionServicioData>> listarPorEmpleado(String empleadoId);

  Future<List<AsignacionServicioData>> listarActivasPorServicio(String servicioId);

  /// Historial completo (vigente + cerradas) de este Servicio, orden
  /// descendente por `fechaInicio`.
  Future<List<AsignacionServicioData>> listarPorServicio(String servicioId);

  /// Escritura cruda — sin validaciones de negocio (existencia/estatus
  /// del Empleado o Servicio, unicidad de asignación vigente); esas
  /// viven en `AsignarEmpleadoServicioUseCase` y en el índice único
  /// parcial de la tabla. Este método existe para que otros
  /// repositorios (`EmpleadoRepositoryImpl.crear`) puedan componerlo
  /// dentro de su propia transacción.
  Future<AsignacionServicioData> asignar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    String? turnoId,
    String? observaciones,
    String? actor,
  });

  /// Cierra la asignación vigente del Empleado (motivo `cambioServicio`)
  /// y crea la nueva — transacción única. Sin validaciones de negocio,
  /// mismo criterio que `asignar`.
  Future<AsignacionServicioData> cambiarServicio({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    String? turnoId,
    String? observaciones,
    String? actor,
  });

  /// Cierra la asignación vigente del Empleado con un motivo
  /// seleccionado manualmente. Sin validaciones de negocio.
  Future<AsignacionServicioData> retirar({
    required String empleadoId,
    required DateTime fechaTermino,
    required String motivo,
    String? observaciones,
    String? actor,
  });

  /// Cierra la asignación vigente del Empleado (si existe) con motivo
  /// `bajaEmpleado` — compuesto desde `EmpleadoRepositoryImpl.
  /// registrarBajaLaboral`, dentro de la misma transacción. No-op si no
  /// hay asignación vigente.
  Future<void> cerrarPorBajaEmpleado({required String empleadoId, required DateTime fecha});

  /// Cierra **todas** las asignaciones vigentes de un Servicio (puede
  /// haber varios Empleados) con motivo `servicioTerminado` — compuesto
  /// desde `ServicioRepositoryImpl.cambiarEstatus`, dentro de la misma
  /// transacción. No-op si no hay ninguna.
  Future<void> cerrarTodasPorServicioTerminado({required String servicioId, required DateTime fecha});
}
