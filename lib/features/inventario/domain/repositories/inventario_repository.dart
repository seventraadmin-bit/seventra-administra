import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/existencia_articulo.dart';

/// Una unidad a crear dentro de una regularización (Etapa 9D, ajuste
/// posterior) — [codigo] ya viene generado por quien llama (mismo
/// criterio que `registrarEntradaUnidad`, que también recibe el
/// código ya resuelto).
class DatosUnidadRegularizada {
  const DatosUnidadRegularizada({
    required this.codigo,
    required this.numeroSerie,
    this.marca,
    this.modelo,
    this.imei,
    this.imei2,
  });

  final String codigo;
  final String numeroSerie;
  final String? marca;
  final String? modelo;
  final String? imei;
  final String? imei2;
}

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

  /// Exactamente la unidad cuyo `numeroSerie` sea igual a [numeroSerie]
  /// — usado por `CorregirIdentidadUnidadUseCase` (y, en el futuro,
  /// cualquier flujo de captura) para validar duplicados *antes* de
  /// escribir, en vez de dejar que la restricción `UNIQUE` de la base
  /// de datos lance una excepción genérica (mismo criterio ya usado
  /// por `listarTelefonosPorImei` para IMEI).
  Future<ArticuloUnidadData?> obtenerUnidadPorNumeroSerie(String numeroSerie);

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

  Future<MovimientoInventarioData?> obtenerMovimientoPorId(String movimientoInventarioId);

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

  /// Regularización de existencia legacy (Etapa 9D, ajuste posterior) —
  /// divide un `MovimientoInventario` `entrada` histórico por cantidad
  /// (`unidadId == null`, `varianteId == null`) en tantas
  /// `ArticuloUnidad` nuevas como [unidades] traiga (validado 1 a 1
  /// contra `cantidad` por el caso de uso, no aquí), cada una con su
  /// propio movimiento `entrada` (cantidad=1, mismos
  /// fecha/costoUnitario/observaciones/actorUsuarioId que el original),
  /// y borra el movimiento original. La existencia total/disponible no
  /// cambia. Si el movimiento original tenía una fila
  /// `CompraPartidaMovimiento` (Compras), la re-liga a los movimientos
  /// nuevos aquí mismo — no en un paso aparte de Compras: esa tabla
  /// referencia `MovimientoInventario` con `ON DELETE RESTRICT`, así
  /// que borrar el original sin re-ligarla primero violaría la FK; la
  /// atomicidad entre ambas escrituras no es opcional. Todo ocurre en
  /// una sola transacción.
  Future<List<ArticuloUnidadData>> regularizarUnidadesDesdeMovimiento({
    required String articuloId,
    required String movimientoInventarioId,
    required List<DatosUnidadRegularizada> unidades,
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

  /// "Configurar equipo" (Etapa 9D, Telefonía) — upsert de IMEI 1/IMEI 2
  /// para una `ArticuloUnidad` serializada ya existente (venga de
  /// Compras o de alta manual). Nunca crea una `ArticuloUnidad` nueva,
  /// nunca toca `numeroTelefonico` (deprecado como fuente de verdad
  /// desde 9D — el número se deriva de la `LineaTelefonica` vinculada).
  Future<ArticuloUnidadTelefonoData> actualizarTelefono({
    required String unidadId,
    String? imei,
    String? imei2,
  });

  /// Toda fila de `ArticuloUnidadTelefono` cuyo `imei` o `imei2` sea
  /// exactamente [imei] — usado por
  /// `ConfigurarEquipoTelefonicoUseCase` (Etapa 9D) para validar
  /// unicidad de IMEI a nivel de aplicación (nunca un `UNIQUE` de base
  /// de datos: "único cuando corresponda" admite excepciones reales de
  /// dispositivos de segunda mano/gris).
  Future<List<ArticuloUnidadTelefonoData>> listarTelefonosPorImei(String imei);

  /// Corrección de identidad de una unidad ya existente — número de
  /// serie/marca/modelo (`ArticuloUnidad`) e IMEI 1/IMEI 2
  /// (`ArticuloUnidadTelefono`, solo si viene alguno de los dos, upsert
  /// igual que `actualizarTelefono`) capturados mal al darla de alta.
  /// `null` en cada parámetro significa "no tocar ese campo"; para
  /// limpiar marca/modelo/IMEI usa los flags `limpiarX` (mismo convenio
  /// `limpiarX` del resto del proyecto). Nunca cambia `codigo`,
  /// `articuloId`, `estatus`, ni crea `MovimientoInventario` — misma
  /// fila, mismo `id`, solo unos campos de identidad corregidos.
  ///
  /// Un `ArticuloUnidadEvento` por cada campo que realmente cambió
  /// (comparado contra el valor previo, dentro de la misma
  /// transacción), con [motivo]/[actorUsuarioId] — la validación de
  /// duplicados (numeroSerie vía [obtenerUnidadPorNumeroSerie], IMEI
  /// vía [listarTelefonosPorImei]) vive en el caso de uso, no aquí.
  Future<ArticuloUnidadData> corregirIdentidadUnidad({
    required String unidadId,
    required String motivo,
    String? numeroSerie,
    String? marca,
    bool limpiarMarca = false,
    String? modelo,
    bool limpiarModelo = false,
    String? imei,
    bool limpiarImei = false,
    String? imei2,
    bool limpiarImei2 = false,
    String? actorUsuarioId,
  });

  /// Historial de correcciones de identidad de una unidad — más
  /// reciente primero.
  Future<List<ArticuloUnidadEventoData>> listarEventosUnidad(String unidadId);
}
