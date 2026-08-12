/// Un resultado de Búsqueda global (Etapa 14A) — misma forma para las
/// 8 entidades, deliberadamente mínima: nunca lleva el registro
/// completo, solo lo necesario para mostrar la fila y navegar. Cada
/// `Buscar*UseCase` decide qué campos de su entidad entran aquí (nunca
/// datos sensibles — ver el doc comment de cada use case).
class ResultadoBusquedaEntidad {
  const ResultadoBusquedaEntidad({required this.id, required this.titulo, required this.subtitulo, required this.ruta});

  final String id;
  final String titulo;
  final String subtitulo;
  final String ruta;
}
