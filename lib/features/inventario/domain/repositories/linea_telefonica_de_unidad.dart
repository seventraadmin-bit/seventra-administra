/// Lo único que Inventario necesita de Telefonía para no dejar una
/// línea contradictoria cuando la custodia de un teléfono se mueve.
///
/// **Por qué existe y por qué apunta en esta dirección.** Hasta la
/// Etapa 9B la sincronización iba al revés: Telefonía creaba y cerraba
/// `Asignacion` de Inventario por su cuenta. Eso le daba a Telefonía
/// autoridad sobre la custodia física —que no le corresponde— y
/// además escribía saltándose `CrearAsignacionUseCase` /
/// `CerrarAsignacionUseCase` (sin sus validaciones ni sus permisos).
/// Se retiró.
///
/// Ahora manda Inventario: **cuando la custodia de una unidad cambia,
/// la asignación de la línea que esa unidad trae la sigue**, dentro de
/// la MISMA transacción. Telefonía nunca decide custodia; Inventario
/// nunca consulta a Telefonía para decidir la suya.
///
/// El puerto lo declara Inventario y lo implementa Telefonía
/// (inversión de dependencia): así no hay
/// `Inventario → Telefonía → Inventario`, porque el adaptador de
/// Telefonía sólo necesita la base y su propio repositorio de
/// asignaciones de línea — nada de Inventario.
abstract interface class LineaTelefonicaDeUnidad {
  /// La unidad pasó a estar bajo custodia de [empleadoId] | [servicioId]
  /// (alta de asignación o cambio de responsable). Si trae una línea
  /// vigente, su asignación se mueve al mismo destino.
  ///
  /// No hace nada si la unidad no trae línea, o si la línea ya apunta
  /// exactamente a ese destino.
  ///
  /// [origenAsignacionInventarioId] es la `Asignacion` de Inventario
  /// que causó el movimiento — identificador REAL, para que la bitácora
  /// pueda apuntar a la operación de origen sin adivinar por fecha.
  Future<void> alinearAlNuevoDestino({
    required String unidadId,
    String? empleadoId,
    String? servicioId,
    required DateTime fecha,
    String? origenAsignacionInventarioId,
    String? actorUsuarioId,
  });

  /// La unidad dejó de estar bajo custodia de alguien (devolución,
  /// daño, pérdida, desecho). Si trae una línea vigente con asignación,
  /// esa asignación se cierra: ya no existe destino físico al que la
  /// línea deba acompañar.
  ///
  /// **No** retira la asociación Línea↔Equipo: que el teléfono vuelva al
  /// anaquel no borra que trajo esa SIM.
  Future<void> cerrarPorFinDeCustodia({
    required String unidadId,
    required DateTime fecha,
    String? origenAsignacionInventarioId,
    String? actorUsuarioId,
  });

  /// ¿Esta unidad trae una línea telefónica vigente? Sólo lectura — la
  /// usa la baja definitiva de la unidad para no dejar una asociación
  /// activa apuntando a un aparato que ya no existe (§18).
  Future<bool> traeLineaVigente(String unidadId);
}
