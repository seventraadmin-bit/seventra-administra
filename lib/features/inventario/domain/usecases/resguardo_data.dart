/// Un renglón del documento de resguardo — un artículo/variante/unidad
/// entregado, ya resuelto a texto (nunca IDs). `sustituyeA` solo se
/// puebla cuando la Asignación que origina el renglón viene de un
/// reemplazo (Etapa 7B, `asignacionReemplazoId`) — responde "reemplazos
/// documentados" sin campo nuevo en el modelo.
class ResguardoItem {
  const ResguardoItem({
    required this.articuloNombre,
    this.varianteLabel,
    this.unidadLabel,
    required this.cantidad,
    this.condicionEntrega,
    this.sustituyeA,
  });

  final String articuloNombre;
  final String? varianteLabel;
  final String? unidadLabel;
  final int cantidad;
  final String? condicionEntrega;
  final String? sustituyeA;
}

/// Contenido íntegro del documento de resguardo (Etapa 7C) — igual que
/// `FichaTecnicaData`, el subconjunto ya curado que se imprime, nunca
/// datos crudos de BD. Exactamente uno de `empleadoNombre`/
/// `servicioNombre` viene poblado (mismo XOR que `Asignacion`).
class ResguardoData {
  const ResguardoData({
    this.empleadoNombre,
    this.servicioNombre,
    this.servicioActualNombre,
    this.folio,
    required this.fechaGeneracion,
    required this.items,
  });

  final String? empleadoNombre;
  final String? servicioNombre;

  /// Servicio vigente del Empleado destino (Etapa "Entrega múltiple de
  /// Inventario"), no el destino del resguardo — solo se puebla cuando
  /// el destino es un Empleado y tiene una `AsignacionServicio` activa.
  /// `null` cuando el destino ya es un Servicio (sería redundante) o el
  /// Empleado no tiene asignación vigente.
  final String? servicioActualNombre;

  /// Folio de la `Entrega` (Etapa "Entrega múltiple de Inventario") si
  /// TODAS las Asignaciones del resguardo vienen del mismo acto de
  /// entrega — `null` para resguardos de Asignaciones legacy o mixtas,
  /// que nunca tuvieron folio propio.
  final String? folio;

  final DateTime fechaGeneracion;
  final List<ResguardoItem> items;
}
