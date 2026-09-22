import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dashboard/presentation/dashboard_controller.dart';
import '../../../notificaciones/presentation/notificaciones_controller.dart';

/// **La única lista de consumidores de "documentos que requieren acción"**.
///
/// La regla de qué documento requiere acción ya está centralizada
/// (`documentoPorEmitirRequiereAccion`) y la consumen tres pantallas: la
/// Agenda, la alerta "Documentos por emitir pendientes" del Dashboard y el
/// Centro de notificaciones. La Agenda se recargaba sola tras cada mutación,
/// pero las otras dos no se enteraban: el Dashboard sólo se invalidaba al
/// pasar a `procesadoAceptado` —y por la Cuenta por cobrar, no por la
/// alerta— y Notificaciones no se invalidaba nunca desde aquí. Emitir un
/// documento pendiente lo quitaba de la Agenda y lo dejaba contado en el
/// Dashboard hasta que algo ajeno reconstruyera el provider.
///
/// Se invalida **después** de que la mutación ya está persistida, nunca
/// antes: un provider reconstruido a mitad de la escritura leería el estado
/// intermedio.
extension InvalidacionDocumentosPorEmitir on Ref {
  /// Sólo para mutaciones que cambian el CONJUNTO de documentos accionables
  /// (`pendiente`/`enPreparacion`): crearlos, emitirlos, cancelarlos,
  /// marcarlos no requeridos o eliminarlos.
  ///
  /// Deliberadamente NO se llama desde corregir un ajuste, corregir datos de
  /// emisión o registrar un envío: esas cambian el contenido de un documento
  /// pero no si requiere acción, y recargar el Dashboard entero por ellas
  /// sería gasto sin razón.
  void invalidarConsumidoresDeDocumentosPorEmitir() {
    invalidate(dashboardControllerProvider);
    invalidate(notificacionesControllerProvider);
  }
}
