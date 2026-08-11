import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/existencia_articulo.dart';

/// Movimientos, unidades serializadas y existencias derivadas de
/// Inventario (Etapa 7A). `MovimientoInventario` es la única fuente de
/// verdad de cuánto hay — ver el doc comment de esa tabla. Dar de alta
/// una `ArticuloUnidad` vive aquí (no en `ArticuloRepository`) porque
/// siempre implica también su movimiento `entrada`, compuesto en la
/// misma transacción — nunca se crea una unidad suelta sin su propio
/// historial. Ninguna validación de negocio vive aquí (que el
/// Artículo maneje variante/serie, sobregiro de baja, etc.) — vive en
/// los casos de uso, como en todo el proyecto.
abstract interface class InventarioRepository {
  Future<ArticuloUnidadData?> obtenerUnidadPorId(String id);

  Future<ArticuloUnidadTelefonoData?> obtenerTelefono(String unidadId);

  Future<List<ArticuloUnidadData>> listarUnidades(String articuloId, {String? estatus});

  /// Todas las unidades serializadas, sin acotar por Artículo — usado
  /// por la búsqueda contextual de Inventario (Etapa 7D) para resolver
  /// un código `UNI-######`/número de serie sin que el usuario tenga
  /// que saber primero a qué Artículo pertenece.
  Future<List<ArticuloUnidadData>> listarTodasUnidades();

  /// Todas las unidades que tienen una fila `ArticuloUnidadTelefono`
  /// (Etapa 9B) — la única señal real de "es un teléfono" que existe
  /// hoy en Inventario (no hay bandera de categoría). Usado por
  /// Telefonía (dominio ajeno) para el selector de equipo — nunca
  /// vuelve a capturar marca/modelo/IMEI, solo filtra sobre lo que ya
  /// existe aquí.
  Future<List<ArticuloUnidadData>> listarUnidadesTelefono({String? estatus});

  Future<List<MovimientoInventarioData>> listarMovimientos({String? articuloId, String? varianteId, String? unidadId});

  /// Entrada de un Artículo por cantidad (con o sin variante) — crea
  /// el `MovimientoInventario` tipo `entrada`.
  Future<MovimientoInventarioData> registrarEntrada({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Entrada de una unidad serializada — crea la `ArticuloUnidad` y su
  /// `MovimientoInventario` tipo `entrada` en la misma transacción.
  /// [imei]/[numeroTelefonico] componen también `ArticuloUnidadTelefono`
  /// si alguno viene poblado.
  Future<ArticuloUnidadData> registrarEntradaUnidad({
    required String articuloId,
    required String codigo,
    required String numeroSerie,
    String? marca,
    String? modelo,
    String? imei,
    String? numeroTelefonico,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Baja definitiva de cantidad — saca del Total real (nunca de un
  /// Artículo/variante que no tenga suficiente Disponible).
  Future<MovimientoInventarioData> registrarBaja({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required String observaciones,
    String? actorUsuarioId,
  });

  /// Baja definitiva de una unidad serializada — marca su `estatus`
  /// en `baja` y registra el movimiento correspondiente.
  Future<ArticuloUnidadData> registrarBajaUnidad({
    required String unidadId,
    required String observaciones,
    String? actorUsuarioId,
  });

  /// Corrección de conteo/merma — `esEntrada` decide
  /// `ajusteEntrada`/`ajusteSalida` (ver el doc comment del enum).
  Future<MovimientoInventarioData> registrarAjuste({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required bool esEntrada,
    required String observaciones,
    String? actorUsuarioId,
  });

  /// Existencia derivada de un Artículo por cantidad (con o sin
  /// variante) — agrega `MovimientoInventario`, nunca lee un total
  /// guardado.
  Future<ExistenciaArticulo> calcularExistencia({required String articuloId, String? varianteId});

  /// Existencia derivada de un Artículo serializado — cuenta
  /// `ArticuloUnidad.estatus`.
  Future<ExistenciaArticulo> calcularExistenciaUnidades(String articuloId);

  /// Costo promedio ponderado (centavos), derivado únicamente de
  /// movimientos `entrada` con `costoUnitario` capturado — nunca
  /// FIFO/LIFO, nunca guardado (Etapa 7D, mismo criterio ya
  /// documentado desde el plan original de Inventario). `null` cuando
  /// no hay ninguna entrada con costo capturado todavía — nunca se
  /// inventa un valor ("solo cuando puedan derivarse de forma
  /// consistente", instrucción explícita de Marlon).
  Future<int?> calcularCostoPromedio({required String articuloId, String? varianteId});

  Future<AttachmentData> adjuntarComprobante({
    required String movimientoInventarioId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });
}
