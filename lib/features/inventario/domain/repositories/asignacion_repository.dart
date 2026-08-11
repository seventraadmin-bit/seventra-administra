import 'package:riseg_one/core/database/app_database.dart';

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

  Future<List<AsignacionData>> listarActivasPorEmpleado(String empleadoId);

  Future<List<AsignacionData>> listarActivasPorServicio(String servicioId);

  Future<List<AsignacionData>> listarHistorialPorEmpleado(String empleadoId);

  Future<List<AsignacionData>> listarHistorialPorServicio(String servicioId);

  /// Todas las Asignaciones de una unidad serializada, ordenadas por
  /// fecha de entrega descendente — "quién la tiene" (la activa, si
  /// existe) y "dónde estuvo antes" (las cerradas), desde el
  /// expediente del Artículo.
  Future<List<AsignacionData>> listarPorUnidad(String unidadId);

  /// La Asignación activa de una unidad serializada, si existe (Etapa
  /// 9B) — mismo criterio que `AsignacionVehiculoRepository
  /// .obtenerActivaPorVehiculo`. Usada por Telefonía (dominio ajeno) al
  /// componer la sincronización de custodia de un equipo asociado a una
  /// línea — nunca escribe aquí, solo lee para decidir si compone o no
  /// (ver el doc comment de `LineaTelefonicaEquipoRepositoryImpl`).
  Future<AsignacionData?> obtenerActivaPorUnidad(String unidadId);

  Future<DescuentoInventarioData?> obtenerDescuentoPorId(String id);

  Future<DescuentoInventarioData?> obtenerDescuentoPorAsignacion(String asignacionId);

  /// `DescuentoInventario` con `estatus = pendiente` de un Empleado —
  /// respuesta directa a "descuentos de Inventario todavía sin
  /// aplicarlos a Nómina" (Etapa 7C): solo lectura, Inventario nunca
  /// escribe hacia Nómina en esta etapa.
  Future<List<DescuentoInventarioData>> listarDescuentosPendientesPorEmpleado(String empleadoId);

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

  /// Cierra una `Asignacion` activa — `estatus` final se deriva de
  /// `motivo` (`dano`→`danada`, `perdida`→`perdida`, cualquier otro→
  /// `devuelta`). Escribe el `MovimientoInventario` correspondiente,
  /// actualiza `ArticuloUnidad.estatus` si aplica, y crea
  /// `DescuentoInventario` si `generaDescuento` — una transacción.
  Future<AsignacionData> cerrar({
    required String asignacionId,
    required String motivo,
    required DateTime fechaCierre,
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
