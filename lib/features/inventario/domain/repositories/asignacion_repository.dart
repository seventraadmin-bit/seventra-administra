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

  Future<DescuentoInventarioData?> obtenerDescuentoPorId(String id);

  Future<DescuentoInventarioData?> obtenerDescuentoPorAsignacion(String asignacionId);

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
    String? actor,
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
    String? actor,
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
    String? actor,
  });

  Future<DescuentoInventarioData> cancelarDescuento({
    required String descuentoId,
    String? observaciones,
    String? actor,
  });
}
