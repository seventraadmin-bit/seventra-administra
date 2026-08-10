/// Existencia derivada de un `Articulo`/`ArticuloVariante` — nunca se
/// guarda, se calcula agregando `MovimientoInventario` (para
/// artículos por cantidad) o contando `ArticuloUnidad.estatus` (para
/// artículos serializados). Desde la Etapa 7B, `asignado`/`danado`/
/// `perdido` se pueblan en ambos casos vía los movimientos de
/// `Asignacion` (`salidaAsignacion`/`entradaDevolucion`/`salidaDano`/
/// `salidaPerdida`).
class ExistenciaArticulo {
  const ExistenciaArticulo({required this.disponible, this.asignado = 0, this.danado = 0, this.perdido = 0});

  final int disponible;
  final int asignado;
  final int danado;
  final int perdido;

  /// Todo lo que sigue "en el sistema" — una `baja` es la única
  /// operación que reduce el total real (nunca aparece aquí).
  int get total => disponible + asignado + danado + perdido;
}
