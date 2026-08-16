/// Campo de una etapa que puede fallar la validación — siempre
/// acompañado del `etapaId` al que pertenece (`ErrorEtapaCobro.etapaId`),
/// salvo los errores generales que no pueden ligarse a una sola etapa.
enum CampoEtapaCobro {
  nombre,
  tipoRegla,
  mesRelativo,
  diaDelMes,
  ordinalSemana,
  diaSemana,
  offsetDias,
  etapaReferenciaId,
}

enum CodigoErrorEtapaCobro {
  /// Un campo que ese `tipoRegla` necesita no fue capturado, o `nombre`
  /// falta en una etapa personalizada.
  requerido,

  /// `etapaReferenciaId` apunta a una etapa que no está en esta misma
  /// vigencia.
  referenciaNoExiste,

  /// Una etapa se referencia a sí misma.
  autoReferencia,

  /// La cadena de referencias entre etapas forma un ciclo.
  cicloDetectado,

  /// `etapaReferenciaId` y `referenciaCierrePeriodo` capturados a la
  /// vez — son mutuamente excluyentes, el origen es uno solo.
  referenciaAmbigua,

  /// Dos etapas de la misma vigencia comparten el mismo `tipoSistema`
  /// — a lo más una etapa de sistema por tipo (la restricción real vive
  /// en la base de datos; este error da el mensaje comprensible antes
  /// de llegar ahí).
  tipoSistemaDuplicado,
}

class ErrorEtapaCobro {
  const ErrorEtapaCobro({required this.etapaId, required this.campo, required this.codigo});

  /// `null` para errores generales, no ligados a una etapa específica
  /// (ej. `tipoSistemaDuplicado` reporta contra la segunda etapa
  /// encontrada, así que en la práctica esto casi siempre trae un id —
  /// se deja nulable para cualquier chequeo verdaderamente global
  /// futuro).
  final String? etapaId;
  final CampoEtapaCobro? campo;
  final CodigoErrorEtapaCobro codigo;
}
