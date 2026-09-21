import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/articulo_unidad_table.dart';

/// Un renglón a crear dentro de una Entrega múltiple ("Entregar
/// equipo") — la forma que recibe `AsignacionRepository.crearVarias`,
/// nunca la tabla `Asignacion` en sí. Mismo criterio que
/// `PartidaCompraInput` en Compras: [condicionEntrega]/[observaciones]
/// llegan ya resueltas por el llamador (heredadas del valor general de
/// la Entrega si el caso de uso así lo decide), esta clase no sabe
/// nada de "herencia" de un encabezado.
class AsignacionLineaInput {
  const AsignacionLineaInput({
    required this.articuloId,
    this.varianteId,
    this.unidadId,
    required this.cantidad,
    this.condicionEntrega,
    this.observaciones,
  });

  final String articuloId;
  final String? varianteId;
  final String? unidadId;
  final int cantidad;
  final String? condicionEntrega;
  final String? observaciones;
}

/// Resultado de `AsignacionRepository.crearEntrega` — la `Entrega`
/// recién creada más TODAS las `Asignacion` que generó, en el mismo
/// orden que las líneas recibidas.
typedef EntregaCreada = ({EntregaData entrega, List<AsignacionData> asignaciones});

/// La relación Inventario↔Empleado/Servicio (Etapa 7B) — "quién tiene
/// qué". Escritura intra-dominio directa (Asignación y
/// MovimientoInventario son ambos de Inventario): no necesita el
/// patrón "repositorio compone repositorio" que sí usan
/// `PagoRepositoryImpl`/`PagoNominaRepositoryImpl` al cruzar a un
/// dominio ajeno (Finanzas). Ninguna validación de negocio vive aquí
/// (exactamente uno de empleado/servicio, unidad disponible, cantidad
/// ≤ disponible, etc.) — vive en los casos de uso, como en todo el
/// proyecto.
abstract interface class AsignacionRepository {
  Future<AsignacionData?> obtenerPorId(String id);

  /// Varias Asignaciones por id, en una sola consulta (Etapa 18) —
  /// para resolver el Artículo/destino de un lote de
  /// `DescuentoInventario` sin `obtenerPorId` dentro de un loop.
  Future<List<AsignacionData>> listarPorIds(List<String> ids);

  Future<List<AsignacionData>> listarActivasPorEmpleado(String empleadoId);

  /// Marca como PENDIENTES DE RECUPERACIÓN todas las asignaciones
  /// vigentes de un Empleado (schemaVersion 82) — llamado desde
  /// `EmpleadoRepositoryImpl.registrarBajaLaboral`, en la MISMA
  /// transacción que la baja laboral.
  ///
  /// **NO cierra nada y NO registra ninguna devolución**: no emite
  /// `MovimientoInventario`, no toca `ArticuloUnidad.estatus` y no
  /// cambia el stock disponible. Dar de baja a una persona no es
  /// recuperar un bien — mientras nadie registre la devolución real, el
  /// radio sigue con ella.
  ///
  /// Resuelve por FK (`empleado_id`), nunca por nombre ni número de
  /// empleado. No-op si no hay ninguna vigente.
  Future<void> marcarPendientesPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  });

  /// Marca UNA asignación como pendiente de recuperación
  /// (schemaVersion 83) — la usa la conciliación de baja cuando el
  /// usuario DECLARA que ese bien sigue con la persona.
  ///
  /// Distinta de [marcarPendientesPorBajaEmpleado], que marca todo de
  /// golpe: aquel era el comportamiento automático de la v82, éste es
  /// una decisión documentada bien por bien.
  Future<void> marcarPendienteRecuperacion({
    required String asignacionId,
    required DateTime fecha,
    String? actorUsuarioId,
  });

  /// Asignaciones vigentes marcadas como pendientes de recuperación —
  /// el expediente las muestra separadas de las asignaciones normales
  /// (§9: "no mezcles actualmente asignado con pendiente de recuperar").
  Future<List<AsignacionData>> listarPendientesRecuperacionPorEmpleado(String empleadoId);

  Future<List<AsignacionData>> listarActivasPorServicio(String servicioId);

  /// Asignaciones activas de un Artículo puntual (Etapa 18) — desde su
  /// propio expediente, "a quién se le entregó" sin tener que pasar
  /// por Empleado/Servicio. Incluye variantes/unidades del mismo
  /// Artículo, nunca solo la existencia sin variante.
  Future<List<AsignacionData>> listarActivasPorArticulo(String articuloId);

  Future<List<AsignacionData>> listarHistorialPorEmpleado(String empleadoId);

  Future<List<AsignacionData>> listarHistorialPorServicio(String servicioId);

  /// Todas las Asignaciones de una unidad serializada, ordenadas por
  /// fecha de entrega descendente — "quién la tiene" (la activa, si
  /// existe) y "dónde estuvo antes" (las cerradas), desde el
  /// expediente del Artículo.
  Future<List<AsignacionData>> listarPorUnidad(String unidadId);

  /// La Asignación activa de una unidad serializada, si existe (Etapa
  /// 9B) — mismo criterio que `AsignacionVehiculoRepository
  /// .obtenerActivaPorVehiculo`. Telefonía la LEE para saber bajo qué
  /// custodia está el aparato que trae una línea; nunca escribe aquí.
  Future<AsignacionData?> obtenerActivaPorUnidad(String unidadId);

  /// Las Asignaciones activas de varias unidades serializadas, en UNA
  /// consulta — para listados que necesitan la custodia de N unidades
  /// sin caer en N+1.
  Future<List<AsignacionData>> listarActivasPorUnidades(List<String> unidadIds);

  Future<DescuentoInventarioData?> obtenerDescuentoPorId(String id);

  Future<DescuentoInventarioData?> obtenerDescuentoPorAsignacion(String asignacionId);

  /// `DescuentoInventario` con `estatus = pendiente` de un Empleado —
  /// respuesta directa a "descuentos de Inventario todavía sin
  /// aplicarlos a Nómina" (Etapa 7C): solo lectura, Inventario nunca
  /// escribe hacia Nómina en esta etapa.
  Future<List<DescuentoInventarioData>> listarDescuentosPendientesPorEmpleado(String empleadoId);

  /// Todos los `DescuentoInventario` de un Empleado, sin importar
  /// `estatus` — a diferencia de [listarDescuentosPendientesPorEmpleado],
  /// para el expediente auditable (Etapa 15): pendiente con
  /// monto/origen, aplicado con monto/folio de Nómina/fecha, cancelado
  /// también visible.
  Future<List<DescuentoInventarioData>> listarDescuentosPorEmpleado(String empleadoId);

  /// Los `DescuentoInventario` aplicados a un renglón de Nómina
  /// puntual (Etapa 15) — el desglose identificable ("Daño/Pérdida de
  /// equipo — nombre del artículo") que muestra el detalle del renglón.
  Future<List<DescuentoInventarioData>> listarDescuentosPorNominaEmpleado(String nominaEmpleadoId);

  /// Todas las `Asignacion` activas, sin importar Empleado/Servicio —
  /// la versión global de `listarActivasPorEmpleado`/
  /// `listarActivasPorServicio` (Etapa 7D, reporte "pendientes de
  /// devolución"). Ninguna tabla de resumen: la misma fuente de verdad
  /// de siempre, sin acotar.
  Future<List<AsignacionData>> listarTodasActivas();

  /// Todas las `Asignacion` con `estatus` `danada`/`perdida` — reporte
  /// global de daños/pérdidas (Etapa 7D).
  Future<List<AsignacionData>> listarDanadasPerdidas();

  /// Todos los `DescuentoInventario` con `estatus = pendiente`, sin
  /// acotar por Empleado — versión global de
  /// `listarDescuentosPendientesPorEmpleado` (Etapa 7D).
  Future<List<DescuentoInventarioData>> listarTodosDescuentosPendientes();

  /// La `Asignacion` que [asignacionId] reemplazó, si la hay —
  /// `asignacionReemplazoId` vive en la fila VIEJA apuntando hacia la
  /// nueva (ver el doc comment de `Asignacion`), así que encontrar el
  /// predecesor de una fila requiere buscar en la dirección inversa.
  /// Usado por `GenerarDocumentoResguardoUseCase` (Etapa 7C) para la
  /// línea "Sustituye a" del PDF.
  Future<AsignacionData?> obtenerAsignacionReemplazada(String asignacionId);

  /// Crea la `Asignacion` + su `MovimientoInventario` tipo
  /// `salidaAsignacion` + (si `unidadId` viene poblado) actualiza
  /// `ArticuloUnidad.estatus` a `asignado` — una transacción.
  Future<AsignacionData> crear({
    required String articuloId,
    String? varianteId,
    String? unidadId,
    required int cantidad,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaEntrega,
    String? condicionEntrega,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Todas las `Asignacion` de una Entrega ("Entregar equipo") —
  /// resuelve el lote completo para generar/adjuntar el resguardo
  /// único, sin que `GenerarDocumentoResguardoUseCase`/
  /// `adjuntarResguardo` necesiten saber nada de `Entrega`.
  Future<List<AsignacionData>> listarPorEntrega(String entregaId);

  /// Crea una `Entrega` completa ("Entregar equipo") en una sola
  /// transacción: la fila `Entrega` (con [folio] ya generado por el
  /// llamador, mismo criterio que `CompraRepository.crear` recibe
  /// `folioCompra` ya generado) y, por cada línea, exactamente lo mismo
  /// que [crear] haría individualmente (un `MovimientoInventario`, y si
  /// aplica, `ArticuloUnidad.estatus → asignado`) — todas con el mismo
  /// `entregaId`. Si cualquier línea falla a mitad de camino (p. ej.
  /// una unidad serializada que dejó de estar disponible entre la
  /// validación y la escritura), TODA la transacción se revierte —
  /// Entrega incluida — nunca quedan algunas líneas creadas y otras no.
  /// Ninguna validación de negocio (existencia disponible, duplicados
  /// dentro del lote, etc.) vive aquí — vive en `EntregarEquipoUseCase`,
  /// antes de llamar.
  Future<EntregaCreada> crearEntrega({
    required String folio,
    required List<AsignacionLineaInput> lineas,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaEntrega,
    String? actorUsuarioId,
  });

  /// Cierra una `Asignacion` activa — `estatus` final se deriva de
  /// `motivo` (`dano`→`danada`, `perdida`→`perdida`, cualquier otro→
  /// `devuelta`). Escribe el `MovimientoInventario` correspondiente,
  /// actualiza `ArticuloUnidad.estatus` si aplica, y crea
  /// `DescuentoInventario` si `generaDescuento` — una transacción.
  Future<AsignacionData> cerrar({
    required String asignacionId,
    required String motivo,
    required DateTime fechaCierre,
    /// Ubicación física de la unidad al cerrar — lavandería, reparación
    /// o pendiente de desecho. `null` deja el comportamiento de
    /// siempre (disponible / dañado / perdido según el motivo).
    ///
    /// Existe porque un bien recuperado puede estar en manos de RISEG
    /// sin estar disponible, y el modelo no sabía decirlo.
    EstatusArticuloUnidad? ubicacionUnidad,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    String? actorUsuarioId,
  });

  /// Cierra [asignacionId] y crea de inmediato una Asignación nueva
  /// contra el artículo/variante/unidad de reemplazo — una
  /// transacción, liga `asignacionReemplazoId` en la fila vieja.
  Future<AsignacionData> reemplazar({
    required String asignacionId,
    required String motivo,
    required DateTime fechaCierre,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    required String articuloIdReemplazo,
    String? varianteIdReemplazo,
    String? unidadIdReemplazo,
    required int cantidadReemplazo,
    String? condicionEntregaReemplazo,
    String? observacionesReemplazo,
    String? actorUsuarioId,
  });

  Future<DescuentoInventarioData> cancelarDescuento({
    required String descuentoId,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Marca [descuentoIds] como `aplicado`, vinculados a
  /// [nominaEmpleadoId] (Etapa 15) — llamado exclusivamente por
  /// `NominaRepositoryImpl.generar`, dentro de la misma transacción que
  /// crea ese renglón: si la Nómina falla, la marca también se revierte
  /// (nunca queda un descuento "aplicado" sin una Nómina real detrás).
  /// Cada id en la lista debe seguir `pendiente` — nunca se vuelve a
  /// aplicar uno ya `aplicado`/`cancelado` (el llamador ya filtró por
  /// `estatus == pendiente` al construir la lista).
  Future<void> aplicarDescuentos({
    required List<String> descuentoIds,
    required String nominaEmpleadoId,
    required DateTime fechaAplicacion,
  });

  /// Revierte a `pendiente` cualquier `DescuentoInventario` `aplicado`
  /// vinculado a alguno de [nominaEmpleadoIds] (Etapa 15) — usado
  /// exclusivamente por `NominaRepositoryImpl.eliminarFisicamente` al
  /// eliminar un Borrador: la deuda del Empleado nunca debe desaparecer
  /// solo porque se borró el intento de Nómina que la había consumido.
  Future<void> revertirDescuentosAplicados(List<String> nominaEmpleadoIds);

  /// Cambia quién es responsable del MISMO bien (Etapa 9D) — distinto de
  /// [reemplazar] (que cambia el bien físico) y de [cerrar]+[crear] (que
  /// generan devolución/salida reales). Cierra la fila vigente con
  /// `estatus = reasignada` y abre una nueva con el mismo
  /// `articuloId`/`varianteId`/`unidadId`/`cantidad`, una sola fecha
  /// efectiva para ambos lados — **sin** `MovimientoInventario` (nunca
  /// entró ni salió nada de Inventario) y **sin** tocar
  /// `ArticuloUnidad.estatus` (la unidad serializada permanece
  /// `asignado` en todo momento, nunca pasa por `disponible`). Nunca
  /// liga `asignacionReemplazoId` — no es un reemplazo.
  Future<AsignacionData> cambiarResponsable({
    required String asignacionId,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Adjunta el resguardo firmado (Etapa 7C) — inserta un único
  /// `Attachment` + una fila de `AsignacionAttachment` por cada
  /// `asignacionId` en [asignacionIds] (llave compuesta, ver el doc
  /// comment de esa tabla), una transacción.
  Future<AttachmentData> adjuntarResguardo({
    required List<String> asignacionIds,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });
}
