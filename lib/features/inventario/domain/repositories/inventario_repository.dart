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
    String? actor,
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
    String? actor,
  });

  /// Baja definitiva de cantidad — saca del Total real (nunca de un
  /// Artículo/variante que no tenga suficiente Disponible).
  Future<MovimientoInventarioData> registrarBaja({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required String observaciones,
    String? actor,
  });

  /// Baja definitiva de una unidad serializada — marca su `estatus`
  /// en `baja` y registra el movimiento correspondiente.
  Future<ArticuloUnidadData> registrarBajaUnidad({
    required String unidadId,
    required String observaciones,
    String? actor,
  });

  /// Corrección de conteo/merma — `esEntrada` decide
  /// `ajusteEntrada`/`ajusteSalida` (ver el doc comment del enum).
  Future<MovimientoInventarioData> registrarAjuste({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required bool esEntrada,
    required String observaciones,
    String? actor,
  });

  /// Existencia derivada de un Artículo por cantidad (con o sin
  /// variante) — agrega `MovimientoInventario`, nunca lee un total
  /// guardado.
  Future<ExistenciaArticulo> calcularExistencia({required String articuloId, String? varianteId});

  /// Existencia derivada de un Artículo serializado — cuenta
  /// `ArticuloUnidad.estatus`.
  Future<ExistenciaArticulo> calcularExistenciaUnidades(String articuloId);

  Future<AttachmentData> adjuntarComprobante({
    required String movimientoInventarioId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
  });
}
