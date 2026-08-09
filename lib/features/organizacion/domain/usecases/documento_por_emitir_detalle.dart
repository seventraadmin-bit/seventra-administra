import 'package:riseg_one/core/database/app_database.dart';

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
  });

  final DocumentoPorEmitirData documento;
  final List<String> servicioIds;
  final List<DocumentoPorEmitirConfiguracionData> configuraciones;
  final List<DocumentoPorEmitirLineaData> lineas;
  final List<String> correos;

  /// Correos realmente utilizados al registrar el envío (Etapa 4I.2.1)
  /// — distinto de `correos` (snapshot de la Configuración de cobro al
  /// generar). Vacío mientras no se haya registrado un envío.
  final List<String> correosEnvio;

  /// Historial administrativo completo, en orden cronológico (Etapa
  /// 4I.2.1) — nunca se edita ni se elimina una fila existente.
  final List<DocumentoPorEmitirEventoData> eventos;

  ResumenIvaDocumento get resumenIva => calcularResumenIva([for (final l in lineas) l.tratamientoIva]);

  /// `null` mientras no se haya registrado el importe emitido — nunca
  /// se muestra "sin diferencia" cuando en realidad no hay dato.
  int? get diferenciaEmision {
    final importeEmitido = documento.importeEmitido;
    if (importeEmitido == null) return null;
    return importeEmitido - documento.importeFinalEsperado;
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
