import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';

import 'configuracion_cobro_regla_evento_errors.dart';

/// Una regla de evento tal como llega del formulario — sin validar.
/// `tipoRegla == null` significa "este evento todavía no se captura",
/// nunca un error (Corrección obligatoria de la Etapa 4H.2: una
/// Configuración de cobro puede guardarse sin reglas o con reglas
/// parciales).
class ReglaEventoBorrador {
  const ReglaEventoBorrador({
    required this.tipoEvento,
    this.tipoRegla,
    this.mesRelativo,
    this.diaDelMes,
    this.ordinalSemana,
    this.diaSemana,
    this.offsetDiasHabiles,
    this.eventoReferencia,
  });

  final TipoEventoCobro tipoEvento;
  final TipoReglaEvento? tipoRegla;
  final MesRelativoCobro? mesRelativo;
  final int? diaDelMes;
  final OrdinalSemanaCobro? ordinalSemana;
  final DiaSemanaCobro? diaSemana;
  final int? offsetDiasHabiles;
  final TipoEventoCobro? eventoReferencia;

  bool get estaCapturada => tipoRegla != null;
}

/// Una regla de evento ya validada — siempre corresponde a un evento
/// realmente capturado (`tipoRegla` nunca nulo aquí).
class ReglaEventoValidada {
  const ReglaEventoValidada({
    required this.tipoEvento,
    required this.tipoRegla,
    this.mesRelativo,
    this.diaDelMes,
    this.ordinalSemana,
    this.diaSemana,
    this.offsetDiasHabiles,
    this.eventoReferencia,
  });

  final TipoEventoCobro tipoEvento;
  final TipoReglaEvento tipoRegla;
  final MesRelativoCobro? mesRelativo;
  final int? diaDelMes;
  final OrdinalSemanaCobro? ordinalSemana;
  final DiaSemanaCobro? diaSemana;
  final int? offsetDiasHabiles;
  final TipoEventoCobro? eventoReferencia;
}

/// Valida hasta 3 reglas de evento de una misma vigencia a la vez — la
/// coherencia de referencias (existe, combinación permitida, sin
/// auto-referencia, sin ciclos) solo tiene sentido evaluada en conjunto,
/// nunca una regla aislada de las demás.
class ConfiguracionCobroReglaEventoValidator {
  const ConfiguracionCobroReglaEventoValidator();

  ({List<ReglaEventoValidada> resultado, List<ErrorReglaEvento> errores}) validar(
    List<ReglaEventoBorrador> borradores,
  ) {
    final capturadas = borradores.where((b) => b.estaCapturada).toList();
    final errores = <ErrorReglaEvento>[];

    for (final b in capturadas) {
      errores.addAll(_validarUno(b, capturadas));
    }

    // Ciclos: solo se evalúa sobre referencias ya confirmadas coherentes
    // — reportar "ciclo" sobre datos que ya fallan por otra razón solo
    // añadiría ruido.
    if (errores.isEmpty) {
      final referencias = {for (final b in capturadas) b.tipoEvento: b.eventoReferencia};
      for (final b in capturadas) {
        if (_tieneCiclo(b.tipoEvento, referencias)) {
          errores.add(
            ErrorReglaEvento(
              tipoEvento: b.tipoEvento,
              campo: CampoReglaEvento.eventoReferencia,
              codigo: CodigoErrorReglaEvento.cicloDetectado,
            ),
          );
        }
      }
    }

    if (errores.isNotEmpty) {
      return (resultado: const <ReglaEventoValidada>[], errores: errores);
    }

    return (
      resultado: [
        for (final b in capturadas)
          ReglaEventoValidada(
            tipoEvento: b.tipoEvento,
            tipoRegla: b.tipoRegla!,
            mesRelativo: b.mesRelativo,
            diaDelMes: b.diaDelMes,
            ordinalSemana: b.ordinalSemana,
            diaSemana: b.diaSemana,
            offsetDiasHabiles: b.offsetDiasHabiles,
            eventoReferencia: b.eventoReferencia,
          ),
      ],
      errores: const <ErrorReglaEvento>[],
    );
  }

  List<ErrorReglaEvento> _validarUno(ReglaEventoBorrador b, List<ReglaEventoBorrador> todas) {
    final errores = <ErrorReglaEvento>[];

    switch (b.tipoRegla!) {
      case TipoReglaEvento.diaFijoDelMes:
        if (b.mesRelativo == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.mesRelativo));
        if (b.diaDelMes == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.diaDelMes));
      case TipoReglaEvento.nEsimoDiaSemanaDelMes:
        if (b.mesRelativo == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.mesRelativo));
        if (b.diaSemana == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.diaSemana));
        if (b.ordinalSemana == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.ordinalSemana));
      case TipoReglaEvento.diasHabilesDespuesDe:
        if (b.offsetDiasHabiles == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.offsetDiasHabiles));
        errores.addAll(_validarEventoReferencia(b, todas));
      case TipoReglaEvento.mismoDiaSemanaSiguienteA:
        if (b.diaSemana == null) errores.add(_requerido(b.tipoEvento, CampoReglaEvento.diaSemana));
        errores.addAll(_validarEventoReferencia(b, todas));
    }

    // Defensivo: Emisión nunca depende de otro evento, sin importar qué
    // tipoRegla se haya elegido (las reglas que sí requieren
    // eventoReferencia ya fueron validadas arriba, pero esto cubre el
    // caso de un eventoReferencia capturado junto a una regla que no lo
    // necesitaba).
    if (b.tipoEvento == TipoEventoCobro.emision && b.eventoReferencia != null) {
      errores.add(
        ErrorReglaEvento(
          tipoEvento: b.tipoEvento,
          campo: CampoReglaEvento.eventoReferencia,
          codigo: CodigoErrorReglaEvento.eventoReferenciaNoPermitido,
        ),
      );
    }

    return errores;
  }

  List<ErrorReglaEvento> _validarEventoReferencia(ReglaEventoBorrador b, List<ReglaEventoBorrador> todas) {
    final ref = b.eventoReferencia;
    if (ref == null) {
      return [_requerido(b.tipoEvento, CampoReglaEvento.eventoReferencia)];
    }
    if (ref == b.tipoEvento) {
      return [
        ErrorReglaEvento(
          tipoEvento: b.tipoEvento,
          campo: CampoReglaEvento.eventoReferencia,
          codigo: CodigoErrorReglaEvento.autoReferencia,
        ),
      ];
    }

    // Combinaciones permitidas (Etapa 4H.2): Emisión nunca depende de
    // nada; Procesamiento solo de Emisión; Pago esperado de Emisión o
    // de Procesamiento.
    final permitido = switch (b.tipoEvento) {
      TipoEventoCobro.emision => false,
      TipoEventoCobro.procesamiento => ref == TipoEventoCobro.emision,
      TipoEventoCobro.pagoEsperado => ref == TipoEventoCobro.emision || ref == TipoEventoCobro.procesamiento,
    };
    if (!permitido) {
      return [
        ErrorReglaEvento(
          tipoEvento: b.tipoEvento,
          campo: CampoReglaEvento.eventoReferencia,
          codigo: CodigoErrorReglaEvento.eventoReferenciaNoPermitido,
        ),
      ];
    }

    if (!todas.any((x) => x.tipoEvento == ref)) {
      return [
        ErrorReglaEvento(
          tipoEvento: b.tipoEvento,
          campo: CampoReglaEvento.eventoReferencia,
          codigo: CodigoErrorReglaEvento.eventoReferenciaNoExiste,
        ),
      ];
    }

    return const [];
  }

  ErrorReglaEvento _requerido(TipoEventoCobro evento, CampoReglaEvento campo) =>
      ErrorReglaEvento(tipoEvento: evento, campo: campo, codigo: CodigoErrorReglaEvento.requerido);

  bool _tieneCiclo(TipoEventoCobro inicio, Map<TipoEventoCobro, TipoEventoCobro?> referencias) {
    final visitados = <TipoEventoCobro>{};
    TipoEventoCobro? actual = inicio;
    while (actual != null) {
      if (!visitados.add(actual)) return true;
      actual = referencias[actual];
    }
    return false;
  }
}
