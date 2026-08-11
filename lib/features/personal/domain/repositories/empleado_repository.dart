import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

/// Expediente del empleado (Etapa 5A) — la base de Personal.
abstract interface class EmpleadoRepository {
  Future<EmpleadoData?> obtenerPorId(String id);

  Future<List<EmpleadoData>> listar({
    String? estatus,
    String? puestoId,
    String? empresaId,
    String? sucursalId,
  });

  Future<List<EmpleadoEventoData>> listarEventos(String empleadoId);

  /// El llamador ya generó `codigoEmpleado` (mismo criterio que
  /// `PagoRepository.crear`). `servicioIdAsignacion` (Etapa 5D) crea,
  /// dentro de la misma transacción, la `AsignacionServicio` inicial —
  /// `CrearEmpleadoUseCase` ya validó que el Servicio exista y esté
  /// activo antes de llegar aquí. `Empleado` nunca gana una columna
  /// `servicioId`.
  Future<EmpleadoData> crear(
    EmpleadoCompanion datos, {
    String? servicioIdAsignacion,
    String? turnoIdAsignacion,
    int? sueldoMensualAsignacion,
    int? bonoMensualAsignacion,
  });

  /// `cambios` nunca debe incluir `codigoEmpleado` — inmutable después
  /// de creado (responsabilidad de `CorregirEmpleadoUseCase`, mismo
  /// criterio que `ActualizarServicioUseCase` con `clienteId`).
  Future<EmpleadoData> corregir({
    required String empleadoId,
    required EmpleadoCompanion cambios,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cierra el periodo laboral vigente (Etapa 5C) — deja `estatus` en
  /// `baja` y completa `fechaBaja`/`motivoBaja`/`observacionesBaja` en
  /// la misma fila de `Empleado`. Nunca toca `EmpleadoPeriodoLaboral`
  /// (ese periodo cerrado se archiva solo hasta que haya un Reingreso).
  Future<EmpleadoData> registrarBajaLaboral({
    required String empleadoId,
    required DateTime fechaBaja,
    required String motivo,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Archiva el periodo cerrado actual en `EmpleadoPeriodoLaboral` y
  /// resetea el periodo vigente en `Empleado` (Etapa 5C) — nunca crea
  /// un Empleado nuevo. `puestoId`/`empresaId`/`sucursalId` son
  /// `Value.absent()` cuando no se proporcionan (se conserva la
  /// asignación anterior), mismo criterio que `corregir`.
  Future<EmpleadoData> registrarReingreso({
    required String empleadoId,
    required DateTime fechaIngreso,
    String? puestoId,
    bool limpiarPuesto = false,
    String? sucursalId,
    bool limpiarSucursal = false,
    String? actorUsuarioId,
  });

  /// Historial de periodos **cerrados** de este Empleado — nunca
  /// incluye el periodo vigente (ver el doc comment de
  /// `EmpleadoPeriodoLaboral`). Orden descendente por `fechaIngreso`
  /// (el periodo cerrado más reciente primero).
  Future<List<EmpleadoPeriodoLaboralData>> listarPeriodosLaboralesArchivados(String empleadoId);

  /// Actualiza el puntero `fotografiaAttachmentId` — el Attachment y su
  /// fila de unión en `EmpleadoAttachment` ya deben existir (los crea
  /// `ActualizarFotografiaEmpleadoUseCase` antes de llamar aquí).
  Future<EmpleadoData> actualizarFotografia({
    required String empleadoId,
    required String attachmentId,
    String? actorUsuarioId,
  });

  Future<DireccionData?> obtenerDomicilio(String empleadoId);

  /// Upsert — mismo criterio que
  /// `EntidadFiscalRepository.guardarDomicilioFiscal`: busca la fila
  /// existente sin importar `cicloVidaRegistro` (a lo más una,
  /// garantizado por el `UNIQUE` real de `empleadoId`), reactiva y
  /// actualiza si existe, inserta solo si nunca existió. `input ==
  /// null` archiva la existente (si había alguna) sin borrarla
  /// físicamente.
  Future<DireccionData?> guardarDomicilio(String empleadoId, DireccionInput? input, {String? actorUsuarioId});

  Future<AttachmentData> adjuntarDocumento({
    required String empleadoId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Registra/actualiza el Perfil psicológico vigente (Etapa 5B) — solo
  /// el valor actual, nunca un historial (upsert implícito: siempre
  /// sobreescribe). `motivo` es opcional a propósito — a diferencia de
  /// `corregir`, esta es la captura normal de la evaluación, no una
  /// corrección administrativa de un dato ya correcto.
  Future<EmpleadoData> actualizarPerfilPsicologico({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? actorUsuarioId,
  });

  Future<EmpleadoData> actualizarEstudioSocioeconomico({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Un resultado por sustancia — `null` deja esa sustancia sin tocar
  /// (mismo valor que ya tenía); el caso de uso siempre manda las 5
  /// explícitas, así que en la práctica nunca llega `null` aquí salvo
  /// que el llamador lo decida a propósito.
  Future<EmpleadoData> actualizarAntidoping({
    required String empleadoId,
    required DateTime fecha,
    required ResultadoSustanciaAntidoping amp,
    required ResultadoSustanciaAntidoping bzd,
    required ResultadoSustanciaAntidoping coc,
    required ResultadoSustanciaAntidoping met,
    required ResultadoSustanciaAntidoping opi,
    String? observaciones,
    String? actorUsuarioId,
  });
}
