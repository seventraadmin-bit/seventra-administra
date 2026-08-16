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

/// Invariante de dominio (Etapa 15): Disponible nunca puede quedar
/// negativo, ni a nivel total del Artículo ni por Talla/Variante —
/// `InventarioRepositoryImpl.registrarBaja`/`registrarAjuste` (salida)
/// la lanzan justo antes de insertar el movimiento que la violaría,
/// sin importar el llamador (baja manual, ajuste, o la reversa
/// interna de `CompraRepositoryImpl.cancelar`). Los casos de uso que
/// exponen UI (`RegistrarBajaUseCase`/`RegistrarAjusteUseCase`) ya
/// validan antes y devuelven un resultado sellado específico — esta
/// excepción es la red de seguridad real a nivel de dominio para
/// cualquier otro llamador.
class ExistenciaInsuficienteException implements Exception {
  const ExistenciaInsuficienteException({required this.disponible, required this.solicitado});

  final int disponible;
  final int solicitado;

  @override
  String toString() =>
      'ExistenciaInsuficienteException: se solicitaron $solicitado, solo hay $disponible disponible(s).';
}

/// Invariante de dominio (Etapa 15): un `MovimientoInventario` por
/// cantidad de un Artículo con `manejaVariante == true` SIEMPRE debe
/// traer `varianteId` — nunca `null` — o el saldo de esa Compra/entrada
/// queda contabilizado en el Total general pero invisible en el
/// desglose por talla (hallazgo real: un movimiento así habría hecho
/// que "Total 1" no coincidiera con ninguna fila de "Existencia por
/// talla"). Y a la inversa, un Artículo sin variante nunca debe recibir
/// un `varianteId`. Los casos de uso de UI (`RegistrarEntradaUseCase`/
/// `RegistrarBajaUseCase`/`RegistrarAjusteUseCase`/`RegistrarCompraUseCase`)
/// ya validan esto y devuelven un resultado sellado específico — esta
/// excepción es la red de seguridad real a nivel de dominio, para
/// cualquier otro llamador (incluida la composición interna
/// Compra→Inventario, que nunca pasa por esos casos de uso).
class VarianteInvalidaException implements Exception {
  const VarianteInvalidaException({required this.articuloId, required this.manejaVariante});

  final String articuloId;

  /// `true`: el Artículo maneja variante y el movimiento llegó sin
  /// `varianteId`. `false`: el Artículo no maneja variante y el
  /// movimiento llegó con una.
  final bool manejaVariante;

  @override
  String toString() => manejaVariante
      ? 'VarianteInvalidaException: el artículo $articuloId maneja variante — el movimiento requiere varianteId.'
      : 'VarianteInvalidaException: el artículo $articuloId no maneja variante — el movimiento no debe traer varianteId.';
}
