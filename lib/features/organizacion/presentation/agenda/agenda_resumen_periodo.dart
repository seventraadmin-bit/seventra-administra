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
    required this.documentosSinTotalCalculable,
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

  /// Suma de los **totales esperados** (con el IVA que corresponda) de los
  /// documentos que todavía representan una expectativa real de cobro —
  /// excluye `cancelado`/`noRequerido`, que nunca se van a cobrar.
  ///
  /// Antes sumaba `importeFinalEsperado`, que significa cosas distintas
  /// según el tratamiento fiscal de cada documento (antes de IVA en
  /// `masIva`, con el IVA dentro en `ivaIncluido`, sin IVA en `noAplica`):
  /// el agregado mezclaba magnitudes y no era comparable consigo mismo.
  final int importeEsperado;

  /// Cuántos documentos quedaron FUERA de [importeEsperado] por no tener
  /// un total fiscalmente comparable. Se expone para que la pantalla lo
  /// diga: una suma incompleta presentada como total sería peor que no
  /// tener el dato.
  final int documentosSinTotalCalculable;
}

const _estatusAccionable = {'pendiente', 'enPreparacion'};
const _estatusSinExpectativaDeCobro = {'cancelado', 'noRequerido'};

AgendaResumenPeriodo calcularResumenPeriodoAgenda(
  List<DocumentoPorEmitirData> documentos,
  DateTime hoy, {
  /// Totales ya calculados por el controlador con la decisión fiscal
  /// única. La clave ausente significa "no calculable".
  Map<String, int> totalEsperadoPorDocumento = const {},
}) {
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

  var porEmitir = 0;
  var porVencerHoy = 0;
  var enviados = 0;
  var procesados = 0;
  var importeEsperado = 0;
  var sinTotalCalculable = 0;

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
    if (!_estatusSinExpectativaDeCobro.contains(d.estatus)) {
      final total = totalEsperadoPorDocumento[d.id];
      if (total == null) {
        sinTotalCalculable++;
      } else {
        importeEsperado += total;
      }
    }
  }

  return AgendaResumenPeriodo(
    porEmitir: porEmitir,
    porVencerHoy: porVencerHoy,
    enviados: enviados,
    procesados: procesados,
    importeEsperado: importeEsperado,
    documentosSinTotalCalculable: sinTotalCalculable,
  );
}
/// Resumen del modo "Pendientes de emisión".
///
/// Deliberadamente NO reutiliza `AgendaResumenPeriodo`: "Enviados" y
/// "Procesados" serían siempre cero por construcción (el conjunto sólo
/// contiene documentos accionables), y una tarjeta que siempre marca cero
/// no informa, sólo ocupa. Estas tres sirven para resolver pendientes:
/// cuántos quedan, desde cuándo, y cuánto dinero representan.
class AgendaResumenPendientes {
  const AgendaResumenPendientes({
    required this.total,
    required this.masAntiguo,
    required this.totalEsperado,
    required this.documentosSinTotalCalculable,
  });

  final int total;

  /// Fecha de emisión programada del más atrasado — `null` sólo si no hay
  /// pendientes.
  final DateTime? masAntiguo;

  /// Misma semántica fiscal que la vista mensual: suma de totales
  /// esperados comparables, nunca de `importeFinalEsperado`.
  final int totalEsperado;

  final int documentosSinTotalCalculable;
}

AgendaResumenPendientes calcularResumenPendientes(
  List<DocumentoPorEmitirData> documentos, {
  Map<String, int> totalEsperadoPorDocumento = const {},
}) {
  var totalEsperado = 0;
  var sinTotal = 0;
  DateTime? masAntiguo;

  for (final d in documentos) {
    final total = totalEsperadoPorDocumento[d.id];
    if (total == null) {
      sinTotal++;
    } else {
      totalEsperado += total;
    }

    final fecha = d.fechaEmisionProgramada;
    if (fecha != null && (masAntiguo == null || fecha.isBefore(masAntiguo))) masAntiguo = fecha;
  }

  return AgendaResumenPendientes(
    total: documentos.length,
    masAntiguo: masAntiguo,
    totalEsperado: totalEsperado,
    documentosSinTotalCalculable: sinTotal,
  );
}
