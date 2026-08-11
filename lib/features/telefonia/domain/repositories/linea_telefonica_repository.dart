import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_linea_telefonica_fisicamente_usecase.dart';

/// El expediente de una línea telefónica (Etapa 9A) — "qué línea es" y
/// su condición operativa. Plan/costo, asignación y equipo asociado
/// viven en repositorios propios (9A/9B), mismo criterio de separación
/// que `Vehiculo`.
abstract interface class LineaTelefonicaRepository {
  Future<LineaTelefonicaData?> obtenerPorId(String id);

  /// Para validar duplicados antes de insertar/corregir — nunca se
  /// depende de capturar la violación del índice único parcial
  /// (`idx_linea_telefonica_numero_unico`), mismo criterio de "validar
  /// antes de escribir" que el resto del proyecto.
  Future<LineaTelefonicaData?> obtenerPorNumero(String numero);

  /// Solo `cicloVidaRegistro == activo` salvo que se pida lo contrario
  /// — no confundir con `estatus`, que es la condición operativa (ver
  /// el doc comment de `LineaTelefonica`).
  Future<List<LineaTelefonicaData>> listar({bool soloActivos = true});

  Future<LineaTelefonicaData> crear({
    required String codigo,
    String? numero,
    required String operador,
    String? operadorOtroNombre,
    required String modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
  });

  Future<LineaTelefonicaData> corregir({
    required String lineaTelefonicaId,
    String? numero,
    String? operador,
    String? operadorOtroNombre,
    String? modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
    bool limpiarNumero = false,
    bool limpiarOperadorOtroNombre = false,
    bool limpiarIccid = false,
    bool limpiarFechaActivacion = false,
    bool limpiarObservaciones = false,
  });

  /// Cambia manualmente el estatus entre `activa`/`suspendida` — nunca a
  /// `baja` (usa [darDeBaja]).
  Future<LineaTelefonicaData> cambiarEstatus({required String lineaTelefonicaId, required String estatus});

  /// Baja terminal — estatus, fecha y motivo en una sola transacción.
  /// En 9A no cierra ninguna asignación/equipo todavía (esas tablas no
  /// existen hasta 9B); esa composición se agrega ahí.
  Future<LineaTelefonicaData> darDeBaja({
    required String lineaTelefonicaId,
    required DateTime fechaBaja,
    required String motivoBaja,
    String? observacionesBaja,
  });

  /// Eliminación física extraordinaria (Etapa 11D) — ver el doc comment
  /// de la implementación para las condiciones exactas.
  Future<EliminarLineaTelefonicaFisicamenteResultado> eliminarFisicamente({
    required String lineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  });
}
