import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/correccion_partida_compra.dart';
import '../usecases/eliminar_compra_fisicamente_usecase.dart';

/// Un renglón a registrar dentro de una `Compra` (Etapa 10) — la forma
/// que recibe `CompraRepository.crear`, no la tabla `CompraPartida` en
/// sí. Para `destino == inventario` sobre un Artículo serializado,
/// [numerosSerie] debe traer exactamente [cantidad] números, uno por
/// unidad a dar de alta — ver el doc comment de `CompraRepository.crear`.
class PartidaCompraInput {
  const PartidaCompraInput({
    required this.destino,
    this.articuloId,
    this.varianteId,
    this.concepto,
    required this.cantidad,
    required this.costoUnitario,
    this.numerosSerie,
    this.marca,
    this.modelo,
  });

  final String destino;
  final String? articuloId;
  final String? varianteId;
  final String? concepto;
  final int cantidad;
  final int costoUnitario;
  final List<String>? numerosSerie;
  final String? marca;
  final String? modelo;
}

/// A quién referencia una `Compra` — resuelto desde un
/// `movimientoInventarioId` real, para el "Origen: Compra COM-000001"
/// navegable desde Inventario (Etapa 10, punto 5 del pedido original).
typedef OrigenCompra = ({String compraId, String folioCompra});

/// Compras de contado ya realizadas y ya pagadas (Etapa 10) — ver el
/// doc comment de `Compra` para el criterio de diseño completo.
/// `crear`/`cancelar` componen automáticamente con `InventarioRepository`
/// (entradas reales, nunca duplicadas) y `EgresoRepository` (un solo
/// Egreso por Compra), nunca escribiendo directo sobre
/// `_db.movimientoInventario`/`_db.articuloUnidad`/`_db.egreso`.
abstract interface class CompraRepository {
  Future<CompraData?> obtenerPorId(String compraId);

  Future<List<CompraPartidaData>> listarPartidas(String compraId);

  Future<List<CompraEventoData>> listarEventos(String compraId);

  /// Filtros combinables — cada uno se aplica solo si viene no-nulo.
  /// `articuloId` filtra por Compras que tengan al menos una partida de
  /// ese Artículo.
  Future<List<CompraData>> listar({
    DateTime? desde,
    DateTime? hasta,
    String? folio,
    String? proveedor,
    String? articuloId,
    String? estatus,
  });

  /// Total derivado de una Compra — `SUM(cantidad × costoUnitario)`
  /// sobre sus partidas, nunca una columna guardada.
  Future<int> calcularTotal(String compraId);

  /// Mismo cálculo que [calcularTotal], resuelto para varias Compras a
  /// la vez en una sola consulta — evita N+1 en el listado.
  Future<Map<String, int>> calcularTotalesPorCompra(Iterable<String> compraIds);

  /// Gasto total en Compras `registrada` dentro del rango — excluye
  /// `cancelada` (mismo criterio que `EgresoRepository.totalEgresos`
  /// excluye lo cancelado: solo dinero real vigente).
  Future<int> totalCompradoEnRango({DateTime? desde, DateTime? hasta});

  /// Todas las `CompraPartida` de las Compras en rango, ya emparejadas
  /// con su `Compra` — Etapa 12C (Reportes): una sola consulta de la
  /// que se derivan en Dart los desgloses por destino/proveedor/
  /// artículo/concepto, en vez de tres consultas separadas para lo
  /// mismo. `estatus == null` trae registradas y canceladas juntas —
  /// el llamador decide cómo separarlas (mismo criterio que `listar`).
  Future<List<({CompraData compra, CompraPartidaData partida})>> listarPartidasEnRango({
    DateTime? desde,
    DateTime? hasta,
    String? estatus,
  });

  /// Todos los `MovimientoInventario` generados por esta Compra (vía
  /// `CompraPartidaMovimiento`) — usado por el expediente ("Integraciones")
  /// y por el chequeo de bloqueo de cancelación.
  Future<List<MovimientoInventarioData>> listarMovimientosGenerados(String compraId);

  /// Las `ArticuloUnidad` generadas por esta Compra (subconjunto
  /// serializado de [listarMovimientosGenerados]) — usado por
  /// `CancelarCompraUseCase` para el chequeo de bloqueo.
  Future<List<ArticuloUnidadData>> listarUnidadesGeneradas(String compraId);

  /// Las `ArticuloUnidad` que pertenecen a una `CompraPartida`
  /// puntual (vía `CompraPartidaMovimiento`, nunca por texto) — usado
  /// por la pantalla de corrección para mostrar/gestionar las unidades
  /// de una partida serializada (Etapa 15, ampliación de "Corregir
  /// datos").
  Future<List<ArticuloUnidadData>> listarUnidadesPorPartida(String compraPartidaId);

  /// Resuelve el origen de un `MovimientoInventario` puntual —
  /// `null` si no vino de ninguna Compra.
  Future<OrigenCompra?> obtenerOrigenPorMovimiento(String movimientoInventarioId);

  /// Igual que [obtenerOrigenPorMovimiento], resuelto en bloque para
  /// varios movimientos a la vez — evita N+1 en listados de Inventario.
  Future<Map<String, OrigenCompra>> obtenerOrigenesPorMovimientos(Iterable<String> movimientoInventarioIds);

  /// Registra la Compra completa en una sola transacción: el Egreso
  /// automático por el total combinado, cada `CompraPartida`, y — para
  /// las partidas `destino == inventario` — la entrada real en
  /// Inventario (`InventarioRepository.registrarEntrada` para
  /// Artículos simples/con variante, `registrarEntradaUnidad` una vez
  /// por número de serie para Artículos serializados) más su fila
  /// `CompraPartidaMovimiento`. [folioCompra] se genera antes de
  /// llamar aquí (mismo criterio que `PagoNominaRepositoryImpl.crear`
  /// recibe `folioPagoNomina` ya generado).
  Future<CompraData> crear({
    required String folioCompra,
    required DateTime fecha,
    String? proveedor,
    required String formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required List<PartidaCompraInput> partidas,
    String? actorUsuarioId,
  });

  /// Corrige campos administrativos y, opcionalmente ([cambiosPartidas],
  /// Etapa 15, ampliación real de "Corregir datos"), las partidas de una
  /// Compra ya registrada — artículo/variante, cantidad, costo, o
  /// partidas completas agregadas/quitadas. Cada cambio se reconcilia
  /// contra Inventario solo por lo que le pertenece a esa partida (vía
  /// `CompraPartidaMovimiento`, nunca por texto), nunca toca movimientos
  /// ajenos. Si el total de la Compra cambia, sincroniza el mismo
  /// `Egreso` (nunca crea uno nuevo). Todo en una sola transacción — si
  /// cualquier cambio está bloqueado (existencia ya consumida), NINGÚN
  /// cambio se aplica. Llamar [obtenerResumenCorreccion] antes para
  /// verificar elegibilidad y mostrar el impacto real.
  Future<CompraData> corregir({
    required String compraId,
    DateTime? fecha,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    List<CorreccionPartida> cambiosPartidas = const [],
    required String motivo,
    String? actorUsuarioId,
  });

  /// Elegibilidad de solo lectura de [cambiosPartidas] antes de
  /// aplicarlos — ver el doc comment de `ResumenCorreccionCompra`.
  Future<ResumenCorreccionCompra> obtenerResumenCorreccion({
    required String compraId,
    List<CorreccionPartida> cambiosPartidas = const [],
  });

  /// Reversión completa: por cada `MovimientoInventario` generado,
  /// llama a `InventarioRepository.registrarBaja`/`registrarBajaUnidad`
  /// (nunca edita el movimiento `entrada` original), cancela el Egreso
  /// vía `EgresoRepository.cancelar`, y marca la Compra `cancelada`.
  /// **No valida** si es seguro cancelar — ese chequeo vive en
  /// `CancelarCompraUseCase`, antes de llamar aquí (mismo criterio que
  /// `DesactivarAreaUseCase`).
  Future<CompraData> cancelar({required String compraId, required String motivo, String? actorUsuarioId});

  Future<AttachmentData> adjuntarComprobante({
    required String compraId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Elegibilidad de solo lectura para [eliminarFisicamente] — ver el
  /// doc comment de `ResumenEliminacionCompra`.
  Future<ResumenEliminacionCompra> obtenerResumenEliminacionFisica(String compraId);

  /// Eliminación física extraordinaria (Etapa 15) — ver el doc comment
  /// completo en `CompraRepositoryImpl.eliminarFisicamente`.
  Future<EliminarCompraFisicamenteResultado> eliminarFisicamente({
    required String compraId,
    required String motivo,
    String? actorUsuarioId,
  });
}
