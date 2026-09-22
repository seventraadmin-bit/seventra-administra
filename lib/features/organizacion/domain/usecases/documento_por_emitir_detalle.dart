import 'package:riseg_one/core/database/app_database.dart';

import 'calcular_totales_esperados_usecase.dart';
import 'resumen_iva_documento_por_emitir.dart';

/// El expediente completo de un `DocumentoPorEmitir` — la fila principal
/// más sus tablas hijas, listas para mostrar en el detalle de la
/// Agenda. `resumenIva`/`diferenciaEmision` son derivados (nunca
/// almacenados): el primero desde la Etapa 4I.1 (Resolución C), el
/// segundo desde la 4I.2.1 (`importeEmitido - importeFinalEsperado`).
class DocumentoPorEmitirDetalle {
  const DocumentoPorEmitirDetalle({
    required this.documento,
    required this.servicioIds,
    required this.configuraciones,
    required this.lineas,
    required this.correos,
    required this.correosEnvio,
    required this.eventos,
    this.hitos = const [],
  });

  final DocumentoPorEmitirData documento;
  final List<String> servicioIds;
  final List<DocumentoPorEmitirConfiguracionData> configuraciones;
  final List<DocumentoPorEmitirLineaData> lineas;
  final List<String> correos;

  /// Hitos planeados del documento (Etapa 15, ampliación "flujo
  /// posterior a la emisión") — solo las etapas que sí resolvieron una
  /// fecha al generarse; nunca se recalculan después (snapshot). La
  /// Agenda muestra únicamente los hitos aquí presentes, ordenados por
  /// `orden`.
  final List<DocumentoPorEmitirHitoData> hitos;

  /// Correos realmente utilizados al registrar el envío (Etapa 4I.2.1)
  /// — distinto de `correos` (snapshot de la Configuración de cobro al
  /// generar). Vacío mientras no se haya registrado un envío.
  final List<String> correosEnvio;

  /// Historial administrativo completo, en orden cronológico (Etapa
  /// 4I.2.1) — nunca se edita ni se elimina una fila existente.
  final List<DocumentoPorEmitirEventoData> eventos;

  ResumenIvaDocumento get resumenIva => calcularResumenIva([for (final l in lineas) l.tratamientoIva]);

  /// Base/IVA/Total esperados — delega en `totalesEsperadosDeDocumento`,
  /// la misma decisión fiscal que usan el renglón y el KPI de la Agenda.
  /// Que la ficha y la lista no puedan mostrar cifras distintas del mismo
  /// documento es el motivo de que esto no se calcule aquí.
  TotalesDeDocumento get _totales => totalesEsperadosDeDocumento(
        importeBaseEsperado: documento.importeBaseEsperado,
        ajusteManual: documento.ajusteManual,
        lineas: [
          for (final l in lineas) (subtotalCentavos: l.subtotalProporcional, tratamientoIva: l.tratamientoIva),
        ],
      );

  TotalesEsperados? get totalesEsperados => _totales.totales;

  /// Por qué no hay totales comparables, para que la pantalla lo diga con
  /// palabras en vez de dejar un hueco sin explicación.
  bool get totalesNoDisponiblesPorAjusteEnMixto => _totales.noDisponiblePorAjusteEnMixto;

  /// `null` mientras no se haya registrado el importe emitido, y
  /// también cuando no existe un total esperado comparable (mixto con
  /// ajuste) — nunca se muestra "sin diferencia" cuando en realidad no
  /// hay dato.
  ///
  /// Se compara siempre contra el TOTAL esperado (incluyendo IVA cuando
  /// aplica), nunca contra la base antes de impuestos: comparar contra
  /// la base producía una "diferencia" que en realidad era el IVA mismo
  /// (Etapa 15, hallazgo real con el CFDI de MILUYOLE). Antes, para los
  /// documentos mixtos se caía a `importeFinalEsperado` — es decir, se
  /// reintroducía ese mismo error justo donde el modelo menos podía
  /// justificarlo.
  int? get diferenciaEmision {
    final importeEmitido = documento.importeEmitido;
    if (importeEmitido == null) return null;
    final totalEsperado = totalesEsperados?.totalEsperado;
    if (totalEsperado == null) return null;
    return importeEmitido - totalEsperado;
  }

  /// `true` si la fecha de emisión programada ya pasó y el documento
  /// sigue en un estado no terminal (Pendiente/EnPreparacion) — usado
  /// por la Agenda para marcar atrasados.
  bool estaAtrasado(DateTime hoy) {
    final fecha = documento.fechaEmisionProgramada;
    if (fecha == null) return false;
    if (documento.estatus != 'pendiente' && documento.estatus != 'enPreparacion') return false;
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
    final fechaSinHora = DateTime(fecha.year, fecha.month, fecha.day);
    return fechaSinHora.isBefore(hoySinHora);
  }
}
