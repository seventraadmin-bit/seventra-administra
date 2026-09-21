import 'package:riseg_one/core/database/app_database.dart';

/// Resumen del periodo visible en la Agenda (Etapa 16, centro de
/// trabajo) — agregado en memoria sobre `AgendaState.documentos`, la
/// misma lista ya cargada/filtrada por el controlador; nunca una
/// consulta nueva.
class AgendaResumenPeriodo {
  const AgendaResumenPeriodo({
    required this.porEmitir,
    required this.porVencerHoy,
    required this.enviados,
    required this.procesados,
    required this.importeEsperado,
  });

  /// Documentos aún accionables (`pendiente`/`enPreparacion`) — el
  /// trabajo administrativo que falta por hacer en el periodo.
  final int porEmitir;

  /// Subconjunto de [porEmitir] cuya `fechaEmisionProgramada` ya es hoy
  /// o anterior — misma condición de estatus que
  /// `documentoPorEmitirRequiereAccion` (el mismo ícono de atraso de la
  /// tabla), extendida para incluir "hoy" y no solo "ya vencido".
  final int porVencerHoy;

  final int enviados;
  final int procesados;

  /// Suma de `importeFinalEsperado` de los documentos que todavía
  /// representan una expectativa real de cobro — excluye
  /// `cancelado`/`noRequerido` (nunca se van a cobrar), nunca inventa un
  /// ajuste adicional.
  final int importeEsperado;
}

const _estatusAccionable = {'pendiente', 'enPreparacion'};
const _estatusSinExpectativaDeCobro = {'cancelado', 'noRequerido'};

AgendaResumenPeriodo calcularResumenPeriodoAgenda(List<DocumentoPorEmitirData> documentos, DateTime hoy) {
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

  var porEmitir = 0;
  var porVencerHoy = 0;
  var enviados = 0;
  var procesados = 0;
  var importeEsperado = 0;

  for (final d in documentos) {
    if (_estatusAccionable.contains(d.estatus)) {
      porEmitir++;
      final fecha = d.fechaEmisionProgramada;
      if (fecha != null) {
        final fechaSinHora = DateTime(fecha.year, fecha.month, fecha.day);
        if (!fechaSinHora.isAfter(hoySinHora)) porVencerHoy++;
      }
    }
    if (d.estatus == 'enviado') enviados++;
    if (d.estatus == 'procesadoAceptado') procesados++;
    if (!_estatusSinExpectativaDeCobro.contains(d.estatus)) importeEsperado += d.importeFinalEsperado;
  }

  return AgendaResumenPeriodo(
    porEmitir: porEmitir,
    porVencerHoy: porVencerHoy,
    enviados: enviados,
    procesados: procesados,
    importeEsperado: importeEsperado,
  );
}
