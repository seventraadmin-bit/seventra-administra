import 'package:riseg_one/core/database/app_database.dart';

/// Relación administrativa Empleado↔Servicio (Etapa 5D) — ver el doc
/// comment de `AsignacionServicio` para el criterio de diseño completo.
abstract interface class AsignacionServicioRepository {
  Future<AsignacionServicioData?> obtenerActivaPorEmpleado(String empleadoId);

  Future<AsignacionServicioData?> obtenerPorId(String asignacionServicioId);

  /// Historial completo (vigente + cerradas) de este Empleado, orden
  /// descendente por `fechaInicio`.
  Future<List<AsignacionServicioData>> listarPorEmpleado(String empleadoId);

  /// Mismo historial que [listarPorEmpleado] pero para varios empleados
  /// en UNA consulta, agrupado por `empleadoId`. Existe para que un
  /// reporte pueda resolver la adscripción histórica de muchas bajas sin
  /// caer en N+1. Sólo lectura.
  Future<Map<String, List<AsignacionServicioData>>> listarPorEmpleados(Iterable<String> empleadoIds);

  Future<List<AsignacionServicioData>> listarActivasPorServicio(String servicioId);

  /// Todas las asignaciones vigentes (`fechaTermino IS NULL`) de
  /// cualquier Empleado/Servicio, en una sola consulta — Etapa 12B
  /// (Reportes): "administrativo vs. operativo" y "personal por
  /// Servicio" se derivan de este conjunto completo, nunca de una
  /// bandera nueva ni de N+1 por Servicio.
  Future<List<AsignacionServicioData>> listarTodasActivas();

  /// TODAS las asignaciones, vigentes y cerradas, de cualquier
  /// Empleado/Servicio — Etapa "Plantilla operativa vs. administrativa".
  ///
  /// Es la única forma de reconstruir "¿este empleado era operativo el
  /// día X?" para un periodo pasado: `fechaInicio`/`fechaTermino` dan
  /// el rango real de cada adscripción. `listarTodasActivas` no sirve
  /// para eso — solo conoce el presente, y usarlo atribuiría la
  /// estructura de hoy a meses anteriores.
  Future<List<AsignacionServicioData>> listarTodas();

  /// Historial completo (vigente + cerradas) de este Servicio, orden
  /// descendente por `fechaInicio`.
  Future<List<AsignacionServicioData>> listarPorServicio(String servicioId);

  /// Escritura cruda — sin validaciones de negocio (existencia/estatus
  /// del Empleado o Servicio, unicidad de asignación vigente, ni de
  /// `sueldoMensual`/`bonoMensual`); esas viven en
  /// `AsignarEmpleadoServicioUseCase` y en el índice único parcial de la
  /// tabla. Este método existe para que otros repositorios
  /// (`EmpleadoRepositoryImpl.crear`) puedan componerlo dentro de su
  /// propia transacción.
  ///
  /// `sueldoMensual`/`bonoMensual` (Etapa 6B) crean, en la misma
  /// transacción, la primera `AsignacionServicioSueldoVigencia` de la
  /// asignación — ya resueltos por el llamador (precarga desde
  /// `Servicio.sueldoMensualReferenciaPersonal`/
  /// `bonoMensualReferenciaPersonal`, o la excepción individual
  /// capturada). Ninguna asignación existe sin al menos una vigencia de
  /// sueldo.
  Future<AsignacionServicioData> asignar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    required int sueldoMensual,
    required int bonoMensual,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente del Empleado (motivo `cambioServicio`)
  /// y crea la nueva — transacción única. Sin validaciones de negocio,
  /// mismo criterio que `asignar`. `sueldoMensual`/`bonoMensual` son de
  /// la asignación *nueva* — la anterior conserva su propio historial de
  /// vigencias sin tocarse.
  Future<AsignacionServicioData> cambiarServicio({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    required int sueldoMensual,
    required int bonoMensual,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente del Empleado con un motivo
  /// seleccionado manualmente. Sin validaciones de negocio.
  Future<AsignacionServicioData> retirar({
    required String empleadoId,
    required DateTime fechaTermino,
    required String motivo,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Cierra la asignación vigente del Empleado (si existe) con motivo
  /// `bajaEmpleado` — compuesto desde `EmpleadoRepositoryImpl.
  /// registrarBajaLaboral`, dentro de la misma transacción. No-op si no
  /// hay asignación vigente.
  /// [actorUsuarioId] es quien dio la baja: el cierre es automático en su
  /// mecánica, pero no es anónimo — lo desencadenó una persona, y el
  /// historial del Empleado debe poder decir quién.
  Future<void> cerrarPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  });

  /// Cierra **todas** las asignaciones vigentes de un Servicio (puede
  /// haber varios Empleados) con motivo `servicioTerminado` — compuesto
  /// desde `ServicioRepositoryImpl.cambiarEstatus`, dentro de la misma
  /// transacción. No-op si no hay ninguna.
  /// [actorUsuarioId] es quien terminó el Servicio, por el mismo motivo.
  Future<void> cerrarTodasPorServicioTerminado({
    required String servicioId,
    required DateTime fecha,
    String? actorUsuarioId,
  });

  /// Registra una nueva vigencia de sueldo/bono sobre una asignación ya
  /// existente (Etapa 6B) — reemplaza la vigente actual (si la fecha
  /// efectiva es hoy) o queda programada (si es futura); nunca actualiza
  /// in place. Escritura cruda — sin validaciones de negocio (ver
  /// `CambiarVigenciaSueldoAsignacionUseCase`), mismo criterio que
  /// `asignar`/`cambiarServicio`.
  Future<AsignacionServicioSueldoVigenciaData> registrarVigenciaSueldo({
    required String asignacionServicioId,
    required int sueldoMensual,
    required int bonoMensual,
    required DateTime fechaInicioVigencia,
    String? observaciones,
  });

  /// Todas las vigencias de sueldo `activo` (vigente + programadas) de
  /// una asignación — nunca incluye canceladas. Orden ascendente por
  /// `fechaInicioVigencia`.
  Future<List<AsignacionServicioSueldoVigenciaData>> listarVigenciasSueldoActivas(String asignacionServicioId);

  /// Regulariza el perfil de una `AsignacionServicio` histórica —
  /// completa `lineaComercialId` (hasta ahora `NULL`) sin crear una
  /// asignación nueva ni tocar fecha/sueldo/historial (corrección de
  /// compatibilidad histórica, Etapa 15). Escritura cruda — sin
  /// validaciones de negocio (existencia, vigencia, pertenencia al
  /// mismo Servicio); esas viven en
  /// `RegularizarPerfilAsignacionServicioUseCase`. Reconcilia
  /// `VacanteOperativa` de la línea recién asignada en la misma
  /// transacción.
  Future<AsignacionServicioData> regularizarPerfil({
    required String asignacionServicioId,
    required String lineaComercialId,
    String? actorUsuarioId,
  });

  /// Historial completo (incluye canceladas) de vigencias de sueldo de
  /// una asignación, orden ascendente por `fechaInicioVigencia`.
  Future<List<AsignacionServicioSueldoVigenciaData>> listarHistorialSueldo(String asignacionServicioId);
}
