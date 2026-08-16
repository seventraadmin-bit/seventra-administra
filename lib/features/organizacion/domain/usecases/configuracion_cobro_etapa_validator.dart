import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';

import 'configuracion_cobro_etapa_errors.dart';

/// Una etapa tal como llega del formulario — sin validar. `id` es
/// estable dentro del lote (generado en el cliente, uuid) para que
/// [etapaReferenciaId] pueda apuntar a una etapa hermana del mismo
/// lote antes de que exista ninguna fila en la base de datos.
/// `tipoRegla == null` significa "etapa activa, regla todavía no
/// capturada" (Etapa 15) — nunca un error: una Configuración de cobro
/// puede guardarse con etapas incompletas, igual que antes.
class EtapaCobroBorrador {
  const EtapaCobroBorrador({
    required this.id,
    this.tipoSistema,
    this.nombre,
    required this.orden,
    this.tipoRegla,
    this.mesRelativo,
    this.diaDelMes,
    this.ordinalSemana,
    this.diaSemana,
    this.offsetDias,
    this.etapaReferenciaId,
    this.referenciaCierrePeriodo = false,
  });

  final String id;

  /// `null` = etapa personalizada.
  final TipoEventoCobro? tipoSistema;

  /// Requerido si [tipoSistema] es `null`.
  final String? nombre;

  final int orden;
  final TipoReglaEvento? tipoRegla;
  final MesRelativoCobro? mesRelativo;
  final int? diaDelMes;
  final OrdinalSemanaCobro? ordinalSemana;
  final DiaSemanaCobro? diaSemana;
  final int? offsetDias;
  final String? etapaReferenciaId;
  final bool referenciaCierrePeriodo;

  bool get estaCapturada => tipoRegla != null;
}

/// Una etapa ya validada — persistida tal cual, capturada o no (una
/// etapa activa sin regla todavía sigue siendo una fila real, a
/// diferencia del modelo anterior donde la ausencia de fila era la
/// única señal de "no capturada").
class EtapaCobroValidada {
  const EtapaCobroValidada({
    required this.id,
    this.tipoSistema,
    this.nombre,
    required this.orden,
    this.tipoRegla,
    this.mesRelativo,
    this.diaDelMes,
    this.ordinalSemana,
    this.diaSemana,
    this.offsetDias,
    this.etapaReferenciaId,
    this.referenciaCierrePeriodo = false,
  });

  final String id;
  final TipoEventoCobro? tipoSistema;
  final String? nombre;
  final int orden;
  final TipoReglaEvento? tipoRegla;
  final MesRelativoCobro? mesRelativo;
  final int? diaDelMes;
  final OrdinalSemanaCobro? ordinalSemana;
  final DiaSemanaCobro? diaSemana;
  final int? offsetDias;
  final String? etapaReferenciaId;
  final bool referenciaCierrePeriodo;
}

/// Valida todas las etapas de una misma vigencia a la vez — la
/// coherencia de referencias (existe, sin auto-referencia, sin
/// ciclos, nunca ambigua entre otra etapa y Cierre de periodo) y de
/// `tipoSistema` (a lo más una vez) solo tiene sentido evaluada en
/// conjunto, nunca una etapa aislada de las demás. A diferencia del
/// validador anterior (Etapa 4H.2), el grafo de referencias permitidas
/// ya no está hardcodeado a pares fijos: cualquier etapa puede
/// depender de cualquier otra etapa capturada en el lote, o del origen
/// virtual Cierre de periodo — Emisión incluida (Etapa 15).
class ConfiguracionCobroEtapaValidator {
  const ConfiguracionCobroEtapaValidator();

  ({List<EtapaCobroValidada> resultado, List<ErrorEtapaCobro> errores}) validar(List<EtapaCobroBorrador> etapas) {
    final errores = <ErrorEtapaCobro>[];

    for (final e in etapas) {
      if (e.tipoSistema == null && (e.nombre == null || e.nombre!.trim().isEmpty)) {
        errores.add(ErrorEtapaCobro(etapaId: e.id, campo: CampoEtapaCobro.nombre, codigo: CodigoErrorEtapaCobro.requerido));
      }
    }

    final tiposSistemaVistos = <TipoEventoCobro>{};
    for (final e in etapas) {
      if (e.tipoSistema != null && !tiposSistemaVistos.add(e.tipoSistema!)) {
        errores.add(ErrorEtapaCobro(etapaId: e.id, campo: null, codigo: CodigoErrorEtapaCobro.tipoSistemaDuplicado));
      }
    }

    final capturadas = etapas.where((e) => e.estaCapturada).toList();
    for (final e in capturadas) {
      errores.addAll(_validarRegla(e, etapas));
    }

    // Ciclos: solo se evalúa sobre referencias ya confirmadas coherentes
    // — reportar "ciclo" sobre datos que ya fallan por otra razón solo
    // añadiría ruido.
    if (errores.isEmpty) {
      final referencias = {for (final e in etapas) e.id: e.etapaReferenciaId};
      for (final e in etapas) {
        if (e.etapaReferenciaId != null && _tieneCiclo(e.id, referencias)) {
          errores.add(
            ErrorEtapaCobro(etapaId: e.id, campo: CampoEtapaCobro.etapaReferenciaId, codigo: CodigoErrorEtapaCobro.cicloDetectado),
          );
        }
      }
    }

    if (errores.isNotEmpty) {
      return (resultado: const <EtapaCobroValidada>[], errores: errores);
    }

    return (
      resultado: [
        for (final e in etapas)
          EtapaCobroValidada(
            id: e.id,
            tipoSistema: e.tipoSistema,
            nombre: e.nombre,
            orden: e.orden,
            tipoRegla: e.tipoRegla,
            mesRelativo: e.mesRelativo,
            diaDelMes: e.diaDelMes,
            ordinalSemana: e.ordinalSemana,
            diaSemana: e.diaSemana,
            offsetDias: e.offsetDias,
            etapaReferenciaId: e.etapaReferenciaId,
            referenciaCierrePeriodo: e.referenciaCierrePeriodo,
          ),
      ],
      errores: const <ErrorEtapaCobro>[],
    );
  }

  List<ErrorEtapaCobro> _validarRegla(EtapaCobroBorrador e, List<EtapaCobroBorrador> todas) {
    final errores = <ErrorEtapaCobro>[];

    switch (e.tipoRegla!) {
      case TipoReglaEvento.diaFijoDelMes:
        if (e.mesRelativo == null) errores.add(_requerido(e, CampoEtapaCobro.mesRelativo));
        if (e.diaDelMes == null) errores.add(_requerido(e, CampoEtapaCobro.diaDelMes));
      case TipoReglaEvento.nEsimoDiaSemanaDelMes:
        if (e.mesRelativo == null) errores.add(_requerido(e, CampoEtapaCobro.mesRelativo));
        if (e.diaSemana == null) errores.add(_requerido(e, CampoEtapaCobro.diaSemana));
        if (e.ordinalSemana == null) errores.add(_requerido(e, CampoEtapaCobro.ordinalSemana));
      case TipoReglaEvento.diasHabilesDespuesDe:
      case TipoReglaEvento.diasCalendarioDespuesDe:
        if (e.offsetDias == null) errores.add(_requerido(e, CampoEtapaCobro.offsetDias));
        errores.addAll(_validarReferencia(e, todas));
      case TipoReglaEvento.mismoDiaSemanaSiguienteA:
        if (e.diaSemana == null) errores.add(_requerido(e, CampoEtapaCobro.diaSemana));
        errores.addAll(_validarReferencia(e, todas));
    }

    return errores;
  }

  List<ErrorEtapaCobro> _validarReferencia(EtapaCobroBorrador e, List<EtapaCobroBorrador> todas) {
    if (e.referenciaCierrePeriodo) {
      if (e.etapaReferenciaId != null) {
        return [
          ErrorEtapaCobro(etapaId: e.id, campo: CampoEtapaCobro.etapaReferenciaId, codigo: CodigoErrorEtapaCobro.referenciaAmbigua),
        ];
      }
      return const [];
    }

    final ref = e.etapaReferenciaId;
    if (ref == null) {
      return [_requerido(e, CampoEtapaCobro.etapaReferenciaId)];
    }
    if (ref == e.id) {
      return [ErrorEtapaCobro(etapaId: e.id, campo: CampoEtapaCobro.etapaReferenciaId, codigo: CodigoErrorEtapaCobro.autoReferencia)];
    }
    if (!todas.any((x) => x.id == ref)) {
      return [
        ErrorEtapaCobro(etapaId: e.id, campo: CampoEtapaCobro.etapaReferenciaId, codigo: CodigoErrorEtapaCobro.referenciaNoExiste),
      ];
    }
    return const [];
  }

  ErrorEtapaCobro _requerido(EtapaCobroBorrador e, CampoEtapaCobro campo) =>
      ErrorEtapaCobro(etapaId: e.id, campo: campo, codigo: CodigoErrorEtapaCobro.requerido);

  bool _tieneCiclo(String inicio, Map<String, String?> referencias) {
    final visitados = <String>{};
    String? actual = inicio;
    while (actual != null) {
      if (!visitados.add(actual)) return true;
      actual = referencias[actual];
    }
    return false;
  }
}
