import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';

/// Campo de una regla de evento que puede fallar la validación —
/// siempre acompañado de a qué [TipoEventoCobro] pertenece (una misma
/// vigencia valida hasta 3 reglas a la vez).
enum CampoReglaEvento {
  tipoRegla,
  mesRelativo,
  diaDelMes,
  ordinalSemana,
  diaSemana,
  offsetDiasHabiles,
  eventoReferencia,
}

enum CodigoErrorReglaEvento {
  /// Un campo que ese `tipoRegla` necesita no fue capturado.
  requerido,

  /// `eventoReferencia` apunta a un evento que no fue capturado en esta
  /// misma vigencia.
  eventoReferenciaNoExiste,

  /// `eventoReferencia` apunta a un evento no permitido para el tipo de
  /// evento que se está definiendo (Emisión nunca depende de otro;
  /// Procesamiento solo puede depender de Emisión; Pago esperado solo
  /// de Emisión o Procesamiento).
  eventoReferenciaNoPermitido,

  /// Un evento se referencia a sí mismo.
  autoReferencia,

  /// La cadena de referencias entre los 3 eventos forma un ciclo.
  cicloDetectado,
}

class ErrorReglaEvento {
  const ErrorReglaEvento({required this.tipoEvento, required this.campo, required this.codigo});

  final TipoEventoCobro tipoEvento;
  final CampoReglaEvento? campo;
  final CodigoErrorReglaEvento codigo;
}
