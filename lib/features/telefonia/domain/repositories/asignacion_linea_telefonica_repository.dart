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

  /// `lineaTelefonicaId` → su asignación activa, para todas las líneas
  /// que tienen una — Etapa 12C (Reportes): "líneas sin asignación" se
  /// deriva de las líneas cuyo id no aparece aquí, sin N+1.
  Future<Map<String, AsignacionLineaTelefonicaData>> obtenerActivasPorTodasLasLineas();

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
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente de la línea con un motivo
  /// seleccionado manualmente (`liberacion`/`otro`).
  Future<AsignacionLineaTelefonicaData> cerrar({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    required String motivoTermino,
    String? observacionesTermino,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente de la línea (motivo
  /// `cambioResponsable`, automático) y crea la nueva — transacción
  /// única.
  /// [motivoTermino] por defecto es `cambioResponsable` (alguien la
  /// cambió a mano); el coordinador de Inventario pasa el suyo para que
  /// la bitácora distinga la consecuencia sistémica.
  Future<AsignacionLineaTelefonicaData> cambiarResponsable({
    required String asignacionLineaTelefonicaActualId,
    required DateTime fecha,
    String? motivoTermino,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente de la línea (si existe) con motivo
  /// `bajaLinea` — llamado desde `LineaTelefonicaRepositoryImpl
  /// .darDeBaja` (repositorio compone repositorio, mismo criterio que
  /// `AsignacionVehiculoRepository.cerrarPorBajaVehiculo`). No-op si no
  /// hay asignación vigente.
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha});

  /// Cierra TODAS las asignaciones vigentes de un Empleado (motivo
  /// `bajaEmpleado`) — llamado desde
  /// `EmpleadoRepositoryImpl.registrarBajaLaboral`, en la MISMA
  /// transacción que la baja laboral. Mismo criterio exacto que
  /// `AsignacionServicioRepository.cerrarPorBajaEmpleado` (Etapa 5D).
  ///
  /// **Todas**, no "la" vigente: la regla de unicidad del proyecto es
  /// una asignación vigente por LÍNEA (índice único parcial), no por
  /// empleado — una persona puede traer dos líneas a la vez, y las dos
  /// deben cerrarse.
  ///
  /// NO toca `LineaTelefonica.estatus`: la línea queda disponible para
  /// reasignarse, nunca dada de baja. Quien se fue es la persona.
  ///
  /// La resolución es por FK (`empleado_id`), jamás por nombre, número
  /// telefónico ni número de empleado. No-op si no hay ninguna vigente.
  Future<void> cerrarPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  });
}
