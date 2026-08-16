import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;

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

  /// Base/IVA/Total esperados para control comercial/cobranza (Etapa
  /// 15, corrección estructural CFDI real) — `null` solo cuando el
  /// documento es `mixto` (líneas con tratamientos de IVA distintos):
  /// `calcularTotalesEsperados` recibe un único `TratamientoIva`, y
  /// aplicar una sola tasa a un documento mixto sería incorrecto. Fuera
  /// de ese caso, se calcula siempre sobre `importeBaseEsperado` +
  /// `ajusteManual` — la misma base ajustada que ya usa
  /// `importeFinalEsperado`, nunca duplicando ni ignorando el ajuste.
  TotalesEsperados? get totalesEsperados {
    final tratamiento = switch (resumenIva) {
      ResumenIvaDocumento.masIva => TratamientoIva.masIva,
      ResumenIvaDocumento.ivaIncluido => TratamientoIva.ivaIncluido,
      ResumenIvaDocumento.noAplica => TratamientoIva.noAplica,
      ResumenIvaDocumento.mixto => null,
    };
    if (tratamiento == null) return null;
    return calcularTotalesEsperados(
      importeBaseCentavos: documento.importeBaseEsperado,
      ajusteManualCentavos: documento.ajusteManual,
      tratamientoIva: tratamiento,
    );
  }

  /// `null` mientras no se haya registrado el importe emitido — nunca
  /// se muestra "sin diferencia" cuando en realidad no hay dato. Se
  /// compara siempre contra el TOTAL esperado (incluyendo IVA cuando
  /// aplica), nunca contra la base antes de impuestos — comparar contra
  /// la base producía una "diferencia" que en realidad era el IVA
  /// mismo (Etapa 15, hallazgo real con el CFDI de MILUYOLE). Para
  /// documentos `mixto` (`totalesEsperados == null`), se conserva el
  /// criterio anterior (`importeFinalEsperado`) como única base posible
  /// sin inventar un desglose que el modelo no soporta todavía.
  int? get diferenciaEmision {
    final importeEmitido = documento.importeEmitido;
    if (importeEmitido == null) return null;
    final totalEsperado = totalesEsperados?.totalEsperado ?? documento.importeFinalEsperado;
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
