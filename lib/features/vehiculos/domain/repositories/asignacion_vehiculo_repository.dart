import 'package:riseg_one/core/database/app_database.dart';

/// Relación administrativa Vehículo↔Empleado/Servicio (Etapa 8B) — ver
/// el doc comment de `AsignacionVehiculo` para el criterio de diseño
/// completo.
abstract interface class AsignacionVehiculoRepository {
  Future<AsignacionVehiculoData?> obtenerPorId(String asignacionVehiculoId);

  Future<AsignacionVehiculoData?> obtenerActivaPorVehiculo(String vehiculoId);

  Future<AsignacionVehiculoData?> obtenerActivaPorEmpleado(String empleadoId);

  Future<AsignacionVehiculoData?> obtenerActivaPorServicio(String servicioId);

  /// Historial completo (vigente + cerradas) de este Vehículo, orden
  /// descendente por `fechaInicio`.
  Future<List<AsignacionVehiculoData>> listarPorVehiculo(String vehiculoId);

  /// Escritura cruda — sin validaciones de negocio (existencia/estatus
  /// del Vehículo, unicidad de asignación vigente, ni la de
  /// no-decremento del kilometraje); esas viven en
  /// `AsignarVehiculoUseCase` y en el índice único parcial de la tabla.
  /// Compone, en la misma transacción: inserta la fila, actualiza
  /// `Vehiculo.estatus = asignado` — mismo criterio que
  /// `AsignacionRepositoryImpl` (Inventario) escribiendo directo
  /// `ArticuloUnidad.estatus` al crear una `Asignacion` (misma tabla de
  /// dominio, sin inyectar un repositorio aparte para eso) — y, si
  /// [kilometrajeEntrega] no es nulo, inserta una lectura en
  /// `VehiculoKilometraje` con `origen = entrega` (punto 10 de Marlon:
  /// "al entregar/asignar, permitir capturar opcionalmente kilometraje
  /// de entrega").
  Future<AsignacionVehiculoData> crear({
    required String vehiculoId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    int? kilometrajeEntrega,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente del Vehículo con un motivo
  /// seleccionado manualmente (`liberacion`/`otro`). Compone, en la
  /// misma transacción: cierra la fila, actualiza `Vehiculo.estatus =
  /// disponible` — **solo si** el estatus actual sigue siendo
  /// `asignado` (si mientras tanto se marcó `enMantenimiento`/
  /// `fueraDeServicio`/`baja`, ese estatus se conserva — "vuelve a
  /// disponible salvo que esté en mantenimiento/fuera de servicio/baja",
  /// instrucción explícita de Marlon) — y, si [kilometrajeDevolucion]
  /// no es nulo, inserta una lectura con `origen = devolucion`.
  Future<AsignacionVehiculoData> cerrar({
    required String asignacionVehiculoId,
    required DateTime fechaTermino,
    required String motivoTermino,
    String? observacionesTermino,
    int? kilometrajeDevolucion,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente del Vehículo (motivo
  /// `cambioResponsable`, automático) y crea la nueva — transacción
  /// única, mismo criterio que `AsignacionServicioRepository.
  /// cambiarServicio`. El estatus se mantiene `asignado` durante todo
  /// el proceso (nunca pasa visiblemente por `disponible`).
  Future<AsignacionVehiculoData> cambiarResponsable({
    required String asignacionVehiculoActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente del Vehículo (si existe) con motivo
  /// `bajaVehiculo` — llamado desde `VehiculoRepositoryImpl.darDeBaja`
  /// (repositorio compone repositorio, mismo criterio que
  /// `AsignacionServicioRepository.cerrarPorBajaEmpleado` desde
  /// `EmpleadoRepositoryImpl.registrarBajaLaboral`, Etapa 5D). No-op si
  /// no hay asignación vigente. **No** toca `Vehiculo.estatus` — quien
  /// llama (`VehiculoRepositoryImpl.darDeBaja`) ya lo deja en `baja` en
  /// la misma transacción.
  Future<void> cerrarPorBajaVehiculo({required String vehiculoId, required DateTime fecha});

  /// Marca como PENDIENTES DE RECUPERACIÓN las asignaciones vigentes de
  /// un Empleado (schemaVersion 82) — misma transacción que su baja
  /// laboral, mismo criterio que `AsignacionRepository` en Inventario.
  ///
  /// **NO cierra la asignación**, y por lo tanto **no** deja el
  /// `Vehiculo` en `disponible` ni finge una entrega: mientras nadie
  /// registre la devolución real, la NP300 sigue con la persona. Es
  /// justo lo que `cerrar` sí haría, y por eso no se usa aquí.
  Future<void> marcarPendientesPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  });

  /// Asignaciones VIGENTES de un Empleado — la conciliación de baja las
  /// carga por FK para que el usuario no tenga que recordar qué trae.
  /// Asignaciones de vehículo por id, en una sola consulta — mismo
  /// criterio de lote que AsignacionRepository.listarPorIds.
  Future<Map<String, AsignacionVehiculoData>> listarPorIds(Iterable<String> ids);

  Future<List<AsignacionVehiculoData>> listarActivasPorEmpleado(String empleadoId);

  /// Asignaciones vigentes marcadas como pendientes de recuperación.
  Future<List<AsignacionVehiculoData>> listarPendientesRecuperacionPorEmpleado(String empleadoId);
}
