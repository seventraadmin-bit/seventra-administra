import 'package:riseg_one/core/database/app_database.dart';

/// La Configuración de cobro de un Servicio ya resuelta contra la fecha
/// de hoy — mismo modelo de `LineaComercialConVigencia` (Etapa 4G.1),
/// aplicado aquí porque solo existe **una** Configuración de cobro por
/// Servicio (1:1), no una lista: `vigenciaActual`/`vigenciasProgramadas`
/// en vez de una tabla de varias filas.
///
/// `vigenciasProgramadas` siempre vacía en la Etapa 4H.1 (todavía no
/// existe una forma de registrar una nueva vigencia) — se mantiene en
/// la forma del composite desde ahora para que la Etapa 4H.2 no tenga
/// que cambiar esta clase, mismo criterio ya aplicado en 4G.1.
class ConfiguracionCobroConVigencia {
  const ConfiguracionCobroConVigencia({
    required this.configuracion,
    required this.vigenciaActual,
    required this.vigenciasProgramadas,
    required this.correos,
    this.entidadFiscalRazonSocial,
    this.frecuenciaNombre,
  });

  final ConfiguracionCobroData configuracion;
  final ConfiguracionCobroVigenciaData? vigenciaActual;
  final List<ConfiguracionCobroVigenciaData> vigenciasProgramadas;
  final List<String> correos;
  final String? entidadFiscalRazonSocial;
  final String? frecuenciaNombre;

  /// Derivado, nunca almacenado (Etapa 4H.1, Resolución C). En 4H.1 solo
  /// verifica que exista una vigencia actual — las reglas temporales de
  /// emisión/procesamiento/pago esperado de la Etapa 4H.2 harán esta
  /// condición más rica sin cambiar el contrato de este getter.
  bool get estaCompleta => vigenciaActual != null;
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
