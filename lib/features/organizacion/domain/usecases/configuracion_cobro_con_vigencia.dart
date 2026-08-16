import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';

import 'configuracion_cobro_etapa_validator.dart';

/// La Configuración de cobro de un Servicio ya resuelta contra la fecha
/// de hoy — mismo modelo de `LineaComercialConVigencia` (Etapa 4G.1),
/// aplicado aquí porque solo existe **una** Configuración de cobro por
/// Servicio (1:1), no una lista: `vigenciaActual`/`vigenciasProgramadas`
/// en vez de una tabla de varias filas.
class ConfiguracionCobroConVigencia {
  const ConfiguracionCobroConVigencia({
    required this.configuracion,
    required this.vigenciaActual,
    required this.vigenciasProgramadas,
    required this.correos,
    required this.etapas,
    required this.esCorregible,
    this.entidadFiscalRazonSocial,
    this.frecuenciaNombre,
    this.clientePortalNombre,
  });

  final ConfiguracionCobroData configuracion;
  final ConfiguracionCobroVigenciaData? vigenciaActual;
  final List<ConfiguracionCobroVigenciaData> vigenciasProgramadas;
  final List<String> correos;

  /// `true` si la configuración todavía es una simple captura sin
  /// historia real (Etapa 15) — su única vigencia, nunca pasó por
  /// "Nueva vigencia" ni generó un `DocumentoPorEmitirConfiguracion`.
  /// Habilita "Corregir" (in-place) en vez de forzar "Nueva vigencia"
  /// para arreglar un simple error de captura.
  final bool esCorregible;

  /// Etapas del flujo de cobro de la vigencia mostrada (vigente, o la
  /// programada más próxima si no hay ninguna vigente), en orden de
  /// `orden` — Etapa 15, reemplaza el trío fijo de la Etapa 4H.2.
  final List<ConfiguracionCobroEtapaData> etapas;
  final String? entidadFiscalRazonSocial;
  final String? frecuenciaNombre;

  /// Nombre del `ClientePortal` referenciado por `vigenciaActual`, para
  /// mostrar en la vista de consulta sin que el llamador tenga que
  /// resolver la referencia por su cuenta — mismo criterio que
  /// `entidadFiscalRazonSocial`. Nunca incluye la contraseña.
  final String? clientePortalNombre;

  /// Derivado, nunca almacenado (Etapa 4H.1, Resolución C; enriquecido
  /// en la Etapa 4H.2, generalizado en la Etapa 15). Una Configuración
  /// de cobro puede guardarse incompleta — esto solo describe el
  /// estado, nunca bloquea el guardado: Pago esperado siempre se
  /// requiere **capturado** (no solo activo); Emisión solo cuando el
  /// documento es CFDI (los dos casos reales de recibo confirmados,
  /// Toluca 32 y Tikal, nunca capturan una regla de Emisión y no por
  /// eso deben quedar "incompletos" para siempre); cualquier otra etapa
  /// de sistema o personalizada nunca se exige, se use o no; además se
  /// reconfirman aquí Entidad fiscal (CFDI), método/complemento
  /// coherentes y que las referencias entre etapas sigan siendo válidas
  /// — todo esto ya se exigió al guardar, así que en la práctica esta
  /// reevaluación siempre debería pasar; es una defensa adicional,
  /// nunca una segunda fuente de verdad.
  bool get estaCompleta {
    final v = vigenciaActual;
    if (v == null) return false;

    final etapasPorSistema = {
      for (final e in etapas)
        if (e.tipoSistema != null) TipoEventoCobro.values.byName(e.tipoSistema!): e,
    };
    if (etapasPorSistema[TipoEventoCobro.pagoEsperado]?.tipoRegla == null) return false;

    final tipoDocumento = TipoDocumentoCobro.values.byName(v.tipoDocumento);
    if (tipoDocumento == TipoDocumentoCobro.cfdi) {
      if (etapasPorSistema[TipoEventoCobro.emision]?.tipoRegla == null) return false;
      if (v.entidadFiscalId == null) return false;
    }

    final metodo = MetodoPagoCobro.values.byName(v.metodo);
    if (metodo == MetodoPagoCobro.ppd && !v.requiereComplemento) return false;

    final borradores = [
      for (final e in etapas)
        EtapaCobroBorrador(
          id: e.id,
          tipoSistema: e.tipoSistema == null ? null : TipoEventoCobro.values.byName(e.tipoSistema!),
          nombre: e.nombre,
          orden: e.orden,
          tipoRegla: e.tipoRegla == null ? null : TipoReglaEvento.values.byName(e.tipoRegla!),
          mesRelativo: e.mesRelativo == null ? null : MesRelativoCobro.values.byName(e.mesRelativo!),
          diaDelMes: e.diaDelMes,
          ordinalSemana: e.ordinalSemana == null ? null : OrdinalSemanaCobro.values.byName(e.ordinalSemana!),
          diaSemana: e.diaSemana == null ? null : DiaSemanaCobro.values.byName(e.diaSemana!),
          offsetDias: e.offsetDias,
          etapaReferenciaId: e.etapaReferenciaId,
          referenciaCierrePeriodo: e.referenciaCierrePeriodo,
        ),
    ];
    final validacion = const ConfiguracionCobroEtapaValidator().validar(borradores);
    return validacion.errores.isEmpty;
  }
}

/// Mismo criterio de fecha que `soloFecha` en `linea_comercial_con_vigencia.dart`
/// — comparar solo año/mes/día. Deliberadamente no compartida con ese
/// archivo (ver nota de riesgo en el plan de la Etapa 4H: dos módulos
/// más pequeños duplicados son más seguros de mantener por separado que
/// una extracción prematura que toque código de 4G.1/4G.2 ya enviado).
DateTime soloFechaCobro(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Clasifica las vigencias `activo` de una Configuración de cobro contra
/// la fecha de hoy — misma lógica exacta que `clasificarVigencias` para
/// líneas comerciales, aplicada aquí a `ConfiguracionCobroVigenciaData`.
({ConfiguracionCobroVigenciaData? vigente, List<ConfiguracionCobroVigenciaData> programadas})
    clasificarVigenciasCobro(List<ConfiguracionCobroVigenciaData> vigenciasActivas, DateTime hoy) {
  final hoySinHora = soloFechaCobro(hoy);

  ConfiguracionCobroVigenciaData? vigente;
  final programadas = <ConfiguracionCobroVigenciaData>[];

  for (final v in vigenciasActivas) {
    final inicio = soloFechaCobro(v.fechaInicioVigencia);
    final fin = v.fechaFinVigencia == null ? null : soloFechaCobro(v.fechaFinVigencia!);

    if (inicio.isAfter(hoySinHora)) {
      programadas.add(v);
      continue;
    }
    if (fin != null && fin.isBefore(hoySinHora)) {
      continue;
    }
    if (vigente == null || inicio.isAfter(soloFechaCobro(vigente.fechaInicioVigencia))) {
      vigente = v;
    }
  }

  programadas.sort((a, b) => a.fechaInicioVigencia.compareTo(b.fechaInicioVigencia));
  return (vigente: vigente, programadas: programadas);
}

/// Los 4 estados que puede mostrar el historial de una Configuración de
/// cobro (Etapa 4H.2) — mismo criterio exacto que `EstadoVigencia` para
/// líneas comerciales (Etapa 4G.2), duplicado deliberadamente (ver nota
/// de riesgo del plan de la Etapa 4H sobre no tocar código de 4G.2 ya
/// enviado).
enum EstadoVigenciaCobro { vigente, programada, historica, cancelada }

EstadoVigenciaCobro clasificarParaHistorialCobro(ConfiguracionCobroVigenciaData vigencia, DateTime hoy) {
  if (vigencia.cicloVidaRegistro == CicloVidaRegistro.archivado.name) {
    return EstadoVigenciaCobro.cancelada;
  }

  final hoySinHora = soloFechaCobro(hoy);
  final inicio = soloFechaCobro(vigencia.fechaInicioVigencia);
  final fin = vigencia.fechaFinVigencia == null ? null : soloFechaCobro(vigencia.fechaFinVigencia!);

  if (inicio.isAfter(hoySinHora)) return EstadoVigenciaCobro.programada;
  if (fin != null && fin.isBefore(hoySinHora)) return EstadoVigenciaCobro.historica;
  return EstadoVigenciaCobro.vigente;
}
