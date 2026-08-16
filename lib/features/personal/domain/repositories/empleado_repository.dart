import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../usecases/eliminar_empleado_fisicamente_usecase.dart';

/// Proyección segura de `Empleado` para Reportes (Etapa 12B) — allow-list
/// explícito, poblado siempre vía `selectOnly` (nunca cargando
/// `EmpleadoData` completo y filtrando después). Deliberadamente **sin**
/// datos bancarios (`bancoId`/`numeroCuentaTarjeta`/`clabe`), sueldo
/// administrativo, CURP/RFC/NSS, ni ninguno de los campos de perfil
/// psicológico/estudio socioeconómico/antidoping — esos campos existen
/// en `Empleado` pero nunca deben salir de la capa de datos hacia
/// código de Reportes, ni siquiera cargados en memoria sin mostrarse
/// (mismo criterio ya usado por `ficha_tecnica_data.dart`).
class EmpleadoReporteRow {
  const EmpleadoReporteRow({
    required this.id,
    required this.numeroEmpleado,
    required this.nombres,
    required this.apellidoPaterno,
    this.apellidoMaterno,
    required this.estatus,
    required this.fechaIngreso,
    this.fechaBaja,
    this.motivoBaja,
    this.puestoId,
    this.sucursalId,
  });

  final String id;
  final int numeroEmpleado;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String estatus;
  final DateTime fechaIngreso;
  final DateTime? fechaBaja;
  final String? motivoBaja;
  final String? puestoId;
  final String? sucursalId;

  String get nombreCompleto => [nombres, apellidoPaterno, apellidoMaterno].whereType<String>().join(' ');
}

/// Expediente del empleado (Etapa 5A) — la base de Personal.
abstract interface class EmpleadoRepository {
  Future<EmpleadoData?> obtenerPorId(String id);

  Future<List<EmpleadoData>> listar({
    String? estatus,
    String? puestoId,
    String? empresaId,
    String? sucursalId,
  });

  /// Igual que [listar], pero proyectada a [EmpleadoReporteRow] — la
  /// única forma en que Reportes (Etapa 12B) debe leer Personal, nunca
  /// `listar`/`obtenerPorId` directo.
  Future<List<EmpleadoReporteRow>> listarParaReporte({String? estatus});

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
    String? lineaComercialIdAsignacion,
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

  /// Versión en lote de [listarPeriodosLaboralesArchivados] — una sola
  /// consulta `WHERE empleado_id IN (...)` para varios empleados a la
  /// vez (Etapa 12B, Reportes): evita N+1 al calcular alertas de
  /// recontratación o altas-vs-reingresos sobre una lista completa de
  /// empleados. Mismo criterio ya usado por
  /// `CompraRepository.calcularTotalesPorCompra`.
  Future<Map<String, List<EmpleadoPeriodoLaboralData>>> listarPeriodosLaboralesArchivadosPorEmpleados(
    List<String> empleadoIds,
  );

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

  /// Resumen de elegibilidad para eliminación física (Etapa 15) — ver
  /// el doc comment de `ResumenEliminacionEmpleado`.
  Future<ResumenEliminacionEmpleado> obtenerResumenEliminacionFisica(String empleadoId);

  /// Eliminación física extraordinaria (Etapa 15) — Maestro-only. Ver
  /// el doc comment de `EliminarEmpleadoFisicamenteUseCase` y de
  /// `EmpleadoRepositoryImpl.eliminarFisicamente`.
  Future<EliminarEmpleadoFisicamenteResultado> eliminarFisicamente({
    required String empleadoId,
    required String motivo,
    String? actorUsuarioId,
  });
}
