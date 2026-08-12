import 'package:riseg_one/core/database/app_database.dart';

/// Un `DocumentoPorEmitir` "requiere acción" cuando su fecha de
/// emisión programada ya pasó y sigue en un estatus accionable
/// (`pendiente`/`enPreparacion`) — extraída de
/// `AgendaListScreen._estaAtrasado` (Etapa 4I.1) para que la Agenda y
/// el Centro de notificaciones (Etapa 14B) compartan exactamente la
/// misma regla, nunca duplicada. `hoy` siempre se recibe desde afuera
/// (mismo criterio que `estaVencida`/`calcularRangoAntiguedad`).
bool documentoPorEmitirRequiereAccion(DocumentoPorEmitirData documento, DateTime hoy) {
  final fecha = documento.fechaEmisionProgramada;
  if (fecha == null) return false;
  if (documento.estatus != 'pendiente' && documento.estatus != 'enPreparacion') return false;

  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
  final fechaSinHora = DateTime(fecha.year, fecha.month, fecha.day);
  return fechaSinHora.isBefore(hoySinHora);
}
