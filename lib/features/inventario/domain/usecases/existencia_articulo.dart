/// Existencia derivada de un `Articulo`/`ArticuloVariante` (Etapa 7A)
/// — nunca se guarda, se calcula agregando `MovimientoInventario`
/// (para artículos por cantidad) o contando `ArticuloUnidad.estatus`
/// (para artículos serializados). `asignado`/`danado`/`perdido`
/// siempre valen `0` en esta etapa (esos buckets solo se pueblan
/// cuando exista `Asignacion`, Etapa 7B) — el campo ya existe para que
/// la UI/reportes no cambien de forma cuando esa etapa llegue.
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
