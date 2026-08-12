/// Una notificación accionable del Centro de notificaciones (Etapa
/// 14B) — misma forma para las 6 categorías. `urgente` distingue
/// "vencido/pendiente" (rojo) de "próximo" (ámbar); la pantalla decide
/// el tono visual, este DTO nunca importa el Design System.
class ResultadoNotificacion {
  const ResultadoNotificacion({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.ruta,
    required this.urgente,
  });

  final String id;
  final String titulo;
  final String subtitulo;
  final String ruta;
  final bool urgente;
}
