/// Existencia derivada de un `Articulo`/`ArticuloVariante` — nunca se
/// guarda, se calcula agregando `MovimientoInventario` (para
/// artículos por cantidad) o contando `ArticuloUnidad.estatus` (para
/// artículos serializados). Desde la Etapa 7B, `asignado`/`danado`/
/// `perdido` se pueblan en ambos casos vía los movimientos de
/// `Asignacion` (`salidaAsignacion`/`entradaDevolucion`/`salidaDano`/
/// `salidaPerdida`).
///
/// ## Tres conceptos que NO son el mismo
///
/// Confundirlos fue un error real de este modelo, corregido en la
/// mini-etapa "Corrección semántica de existencia":
///
///  1. **Existencia real / propiedad** ([total]). Lo que sigue siendo de
///     RISEG, esté donde esté. Una camisa en la tintorería sigue siendo
///     de la empresa.
///  2. **Disponibilidad** ([disponible]). Lo que se puede entregar hoy a
///     alguien. Es un subconjunto estricto de la existencia.
///  3. **Baja real**. La ÚNICA operación que reduce la existencia —
///     `RegistrarBajaUnidadUseCase` para unidades serializadas,
///     `RegistrarBajaUseCase` (movimiento `baja`) para cantidades.
///     `pendienteDesecho` es una decisión previa, no la baja.
class ExistenciaArticulo {
  const ExistenciaArticulo({
    required this.disponible,
    this.asignado = 0,
    this.danado = 0,
    this.perdido = 0,
    this.enProceso = 0,
  });

  /// Lo que se puede entregar hoy. Ninguna otra cubeta es asignable.
  final int disponible;

  /// En custodia de un empleado.
  final int asignado;

  final int danado;
  final int perdido;

  /// Unidades recuperadas que todavía no pueden asignarse: lavandería,
  /// reparación o pendientes de desecho. Se cuentan aparte de
  /// [disponible] a propósito — sumarlas ahí sería mentir sobre lo que
  /// hay para entregar, y meterlas en [danado] confundiría la condición
  /// del bien con dónde está.
  ///
  /// Pero **sí forman parte de [total]**: siguen siendo propiedad de
  /// RISEG. Solo aplica a artículos serializados; un artículo por
  /// cantidad no tiene estados intermedios y aquí siempre trae 0.
  final int enProceso;

  /// Existencia real: todo lo que sigue siendo propiedad de RISEG.
  ///
  /// Incluye [enProceso] desde la mini-etapa de corrección semántica.
  /// Antes no lo hacía, y eso producía un efecto absurdo: mandar una
  /// prenda a la tintorería la borraba del inventario —y de su valor—
  /// hasta que volviera, como si la empresa hubiera dejado de ser su
  /// dueña por estar en lavado. El doc de este getter ya afirmaba que
  /// "una baja es la única operación que reduce el total real"; el
  /// código no lo cumplía.
  ///
  /// [danado] y [perdido] siguen contando, igual que antes: un bien
  /// dañado sigue siendo de la empresa, y uno perdido permanece como
  /// pérdida abierta hasta que alguien ejecute su baja.
  int get total => disponible + asignado + danado + perdido + enProceso;
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

/// Invariante de dominio (Etapa 0 — corrección de bug real, auditoría
/// de consistencia transversal): una `ArticuloUnidad` `asignada` (en
/// custodia activa de un Empleado) nunca puede darse de baja
/// directamente — eso saltaría por completo el flujo de cierre de
/// Asignación (`CerrarAsignacionUseCase`), dejando una `Asignacion`
/// activa apuntando a una unidad que ya no existe operativamente.
/// Antes de esta corrección, `InventarioRepositoryImpl.registrarBajaUnidad`
/// no verificaba el estatus de la unidad en absoluto — mismo criterio
/// de "red de seguridad, sin importar el llamador" que
/// [ExistenciaInsuficienteException]/[VarianteInvalidaException].
class UnidadAsignadaException implements Exception {
  const UnidadAsignadaException({required this.unidadId});

  final String unidadId;

  @override
  String toString() =>
      'UnidadAsignadaException: la unidad $unidadId está asignada — cierre la Asignación antes de darla de baja.';
}
