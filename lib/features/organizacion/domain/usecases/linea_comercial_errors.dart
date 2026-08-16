/// Campo de [LineaComercialBorrador] que puede fallar la validación.
enum CampoLineaComercial {
  puesto,
  modalidadTurno,
  cantidadElementos,
  precioUnitario,
  tratamientoIva,
  fechaInicioVigencia,
  fechaFinVigencia,
  sueldoMensualReferenciaPersonal,
  bonoMensualReferenciaPersonal,

  /// Horario personalizado (Etapa 15) — un error con este campo siempre
  /// trae `diaSemana` en [ErrorLineaComercial].
  horario,
}

enum CodigoErrorLineaComercial {
  requerido,
  noExiste,
  inactivo,
  fechaAnteriorInicioServicio,

  /// Etapa 15 — capturado pero fuera de rango (sueldo debe ser `> 0`,
  /// bono `>= 0`), mismo criterio que el resto de las fuentes de sueldo
  /// del proyecto.
  invalido,

  /// Etapa 4G.2 — ya existe una vigencia de esta línea con exactamente
  /// esa fecha de inicio.
  fechaDuplicada,

  /// Etapa 4G.2 — la fecha de fin capturada a mano se solaparía con una
  /// vigencia posterior ya registrada (nunca se trunca en silencio un
  /// valor que el usuario escribió explícitamente).
  solapamiento,

  /// Etapa 4H.1 — el tratamiento de IVA capturado es incompatible con
  /// la Configuración de cobro vigente del Servicio (CFDI nunca admite
  /// `noAplica`; recibo exige `noAplica` en todas las líneas).
  ivaIncompatibleConfiguracionCobro,

  /// Etapa 15, horario personalizado — un día marcado "trabaja" no
  /// capturó hora de entrada.
  horarioHoraInicioRequerida,

  /// Etapa 15, horario personalizado — un día marcado "trabaja" no
  /// capturó hora de salida.
  horarioHoraFinRequerida,

  /// Etapa 15, horario personalizado — hora de entrada y salida
  /// idénticas (un turno de 0 horas no tiene sentido).
  horarioHorasIguales,
}

class ErrorLineaComercial {
  const ErrorLineaComercial({required this.campo, required this.codigo, this.diaSemana});

  final CampoLineaComercial campo;
  final CodigoErrorLineaComercial codigo;

  /// Solo presente cuando `campo == CampoLineaComercial.horario` — 0 =
  /// lunes ... 6 = domingo, mismo índice que `DiaSemana`.
  final int? diaSemana;
}

/// Busca el error (si existe) asociado a un campo específico — mismo
/// patrón que `errorParaCampoServicio`.
ErrorLineaComercial? errorParaCampoLineaComercial(List<ErrorLineaComercial> errores, CampoLineaComercial campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
