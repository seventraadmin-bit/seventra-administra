import 'package:riseg_one/core/database/app_database.dart';

import 'resumen_iva_documento_por_emitir.dart';

/// El expediente completo de un `DocumentoPorEmitir` — la fila principal
/// más sus 4 tablas hijas, listas para mostrar en el detalle de la
/// Agenda. `resumenIva` es derivado (Resolución C, Etapa 4I.1), nunca
/// almacenado.
class DocumentoPorEmitirDetalle {
  const DocumentoPorEmitirDetalle({
    required this.documento,
    required this.servicioIds,
    required this.configuraciones,
    required this.lineas,
    required this.correos,
  });

  final DocumentoPorEmitirData documento;
  final List<String> servicioIds;
  final List<DocumentoPorEmitirConfiguracionData> configuraciones;
  final List<DocumentoPorEmitirLineaData> lineas;
  final List<String> correos;

  ResumenIvaDocumento get resumenIva => calcularResumenIva([for (final l in lineas) l.tratamientoIva]);

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
