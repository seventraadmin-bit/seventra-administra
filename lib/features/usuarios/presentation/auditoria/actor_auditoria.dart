import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Cómo se nombra al autor de un evento auditado. **Tres estados, nunca
/// dos**, porque mezclarlos fue exactamente el defecto que ocultó durante
/// meses que Comercial no estaba guardando el actor.
enum ClaseActorAuditoria {
  /// Se resolvió una persona. Se muestra su nombre, incluso si hoy está
  /// inactiva: la auditoría cuenta lo que pasó, no el estado presente de
  /// la cuenta.
  humano,

  /// Proceso autónomo sin persona que lo iniciara.
  ///
  /// **Hoy ningún evento llega aquí, y es a propósito.** Clasificar algo
  /// como "Sistema" exige una marca estructural en el propio evento; no
  /// basta con que el actor sea nulo. Mientras esa marca no exista, un
  /// nulo significa que no sabemos quién fue, no que no hubiera nadie.
  sistema,

  /// No se puede demostrar quién lo hizo: eventos anteriores a que su
  /// módulo empezara a guardar el actor. No se inventa un responsable ni
  /// se reescribe la historia.
  noRegistrado,
}

/// La única función que decide cómo se nombra a un actor en toda la
/// aplicación.
///
/// [nombreResuelto] llega ya buscado por el llamador (con un mapa en lote,
/// nunca una consulta por fila) y debe incluir a los usuarios inactivos: un
/// evento de JAVIER sigue siendo de JAVIER aunque su cuenta esté apagada.
String etiquetaActorAuditoria(
  AppLocalizations l10n, {
  required String? nombreResuelto,
  ClaseActorAuditoria clase = ClaseActorAuditoria.noRegistrado,
}) {
  if (nombreResuelto != null) return nombreResuelto;
  return switch (clase) {
    ClaseActorAuditoria.humano || ClaseActorAuditoria.noRegistrado => l10n.auditoriaActorNoRegistrado,
    ClaseActorAuditoria.sistema => l10n.auditoriaActorSistema,
  };
}
