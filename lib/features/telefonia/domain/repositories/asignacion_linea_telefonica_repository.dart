import 'package:riseg_one/core/database/app_database.dart';

/// Relación administrativa LineaTelefonica↔Empleado/Servicio (Etapa
/// 9B) — ver el doc comment de `AsignacionLineaTelefonica` para el
/// criterio de diseño completo. A diferencia de `AsignacionVehiculo`,
/// esta tabla **no** compone ningún cambio de `LineaTelefonica.estatus`
/// — asignación y estatus son ejes independientes aquí (ver el doc
/// comment de `EstatusLineaTelefonica`).
abstract interface class AsignacionLineaTelefonicaRepository {
  Future<AsignacionLineaTelefonicaData?> obtenerPorId(String asignacionLineaTelefonicaId);

  Future<AsignacionLineaTelefonicaData?> obtenerActivaPorLinea(String lineaTelefonicaId);

  Future<AsignacionLineaTelefonicaData?> obtenerActivaPorEmpleado(String empleadoId);

  Future<AsignacionLineaTelefonicaData?> obtenerActivaPorServicio(String servicioId);

  /// Historial completo (vigente + cerradas) de esta línea, orden
  /// descendente por `fechaInicio`.
  Future<List<AsignacionLineaTelefonicaData>> listarPorLinea(String lineaTelefonicaId);

  /// Escritura cruda — sin validaciones de negocio (existencia/estatus
  /// de la línea, unicidad de asignación vigente); esas viven en
  /// `AsignarLineaTelefonicaUseCase` y en el índice único parcial de la
  /// tabla.
  Future<AsignacionLineaTelefonicaData> crear({
    required String lineaTelefonicaId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    String? actor,
  });

  /// Cierra la asignación vigente de la línea con un motivo
  /// seleccionado manualmente (`liberacion`/`otro`).
  Future<AsignacionLineaTelefonicaData> cerrar({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    required String motivoTermino,
    String? observacionesTermino,
    String? actor,
  });

  /// Cierra la asignación vigente de la línea (motivo
  /// `cambioResponsable`, automático) y crea la nueva — transacción
  /// única.
  Future<AsignacionLineaTelefonicaData> cambiarResponsable({
    required String asignacionLineaTelefonicaActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actor,
  });

  /// Cierra la asignación vigente de la línea (si existe) con motivo
  /// `bajaLinea` — llamado desde `LineaTelefonicaRepositoryImpl
  /// .darDeBaja` (repositorio compone repositorio, mismo criterio que
  /// `AsignacionVehiculoRepository.cerrarPorBajaVehiculo`). No-op si no
  /// hay asignación vigente.
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha});
}
