import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/correccion_partida_compra.dart';
import '../usecases/eliminar_cadena_prueba_compra_usecase.dart';
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
  /// ese Artículo. `formaPago` (Etapa 19) es el nombre estable del enum
  /// `FormaPago`, mismo criterio que `estatus`.
  Future<List<CompraData>> listar({
    DateTime? desde,
    DateTime? hasta,
    String? folio,
    String? proveedor,
    String? articuloId,
    String? estatus,
    String? formaPago,
  });

  /// Total derivado de una Compra — `SUM(cantidad × costoUnitario)`
  /// sobre sus partidas, nunca una columna guardada.
  Future<int> calcularTotal(String compraId);

  /// Mismo cálculo que [calcularTotal], resuelto para varias Compras a
  /// la vez en una sola consulta — evita N+1 en el listado.
  Future<Map<String, int>> calcularTotalesPorCompra(Iterable<String> compraIds);

  /// Etapa 3 (Compras — corrección financiera Cuenta↔TDC): suma el
  /// total de las Compras `registrada` (nunca `cancelada`) cuyo origen
  /// financiero ACTUAL es una TDC (`deudaId != null` — la FK
  /// autoritativa, nunca `formaPago` como proxy), en el rango de
  /// fecha dado.
  ///
  /// Existe porque una Compra financiada por TDC nunca genera un
  /// `Egreso` (solo un cargo en `MovimientoDeuda`), así que
  /// `EgresoRepository.totalEgresos` es ciego a ella — sin esto,
  /// "gasto operativo" caería a cero en cuanto una Compra corregida
  /// quedara en una TDC, violando el invariante de que cambiar el
  /// origen financiero nunca cambia el gasto económico reconocido
  /// (ver `ObtenerResumenFinancieroUseCase`).
  Future<int> totalCompradoPorTdcEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  /// Renglones `destino == inventario` de cada Compra — `articuloId` +
  /// `cantidad`, en el orden en que se capturaron (Etapa 19.1: la
  /// columna "Artículos comprados" del listado necesita el nombre real
  /// y la cantidad de cada renglón, no solo un conteo). Partidas de
  /// `gastoDirecto` se excluyen (no representan un Artículo real).
  /// Resuelto para varias Compras a la vez en una sola consulta —
  /// mismo criterio que [calcularTotalesPorCompra]: nunca N+1 en el
  /// listado. El nombre del Artículo se resuelve en la capa de
  /// presentación contra el catálogo ya cargado (`ArticuloRepository
  /// .listar()`), nunca con una consulta adicional aquí.
  Future<Map<String, List<({String articuloId, int cantidad})>>> listarArticulosPorCompra(Iterable<String> compraIds);

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

  /// Mensajes de bloqueo (uno por partida en conflicto, vacío si
  /// ninguna) para las partidas por CANTIDAD de esta Compra (artículo
  /// sin número de serie) cuyo artículo/variante ya tiene alguna
  /// `Asignacion` registrada — política conservadora, mismo criterio
  /// exacto que `obtenerResumenEliminacionFisica`/`corregir` usan para
  /// el mismo caso. Usado por `CancelarCompraUseCase` para bloquear
  /// proactivamente ANTES de intentar la reversión — nunca dejar que
  /// `InventarioRepository.registrarBaja` lance
  /// `ExistenciaInsuficienteException` a medio camino.
  Future<List<String>> listarDetalleBloqueoCancelacionPorCantidad(String compraId);

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

  /// Resuelve la Compra que generó un `Egreso` puntual (vía
  /// `Compra.egresoId`, la única FK real — nunca por texto) — `null` si
  /// ese Egreso no vino de ninguna Compra. Usado por el bloqueo de
  /// corrección/cancelación directa de Egreso (Etapa "Ingresos y
  /// Egresos") y por la navegación "Ver origen" desde su expediente.
  Future<OrigenCompra?> obtenerOrigenPorEgreso(String egresoId);

  /// Registra la Compra completa en una sola transacción: el Egreso
  /// automático por el total combinado, cada `CompraPartida`, y — para
  /// las partidas `destino == inventario` — la entrada real en
  /// Inventario (`InventarioRepository.registrarEntrada` para
  /// Artículos simples/con variante, `registrarEntradaUnidad` una vez
  /// por número de serie para Artículos serializados) más su fila
  /// `CompraPartidaMovimiento`. [folioCompra] se genera antes de
  /// llamar aquí (mismo criterio que `PagoNominaRepositoryImpl.crear`
  /// recibe `folioPagoNomina` ya generado).
  /// Etapa 19B: cuando `formaPago == tarjeta`, [deudaId] es obligatorio
  /// (la tarjeta que financia la compra) y esta Compra **no** genera
  /// `Egreso` — genera en su lugar un `MovimientoDeuda` tipo
  /// `cargoCompra` (vía `DeudaRepository.registrarCargoCompra`, dentro
  /// de la misma transacción). Para cualquier otra `formaPago`, el
  /// comportamiento es idéntico al de siempre (Egreso automático,
  /// `deudaId` queda `null`). Asume que el llamador ya validó el límite
  /// de crédito disponible — ver el doc comment de
  /// `DeudaRepository.registrarCargoCompra`.
  Future<CompraData> crear({
    required String folioCompra,
    required DateTime fecha,
    String? proveedor,
    required String formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required List<PartidaCompraInput> partidas,
    String? deudaId,
    String? cuentaFinancieraId,
    String? actorUsuarioId,
  });

  /// Corrige campos administrativos, opcionalmente ([cambiosPartidas],
  /// Etapa 15) las partidas, y opcionalmente (Etapa 3) el origen
  /// financiero COMPLETO de una Compra ya registrada.
  ///
  /// Origen financiero — pasar exactamente uno de los dos (nunca
  /// ambos, ya rechazado por `CorregirCompraUseCase` antes de llegar
  /// aquí) para moverlo, o ninguno para conservar el actual:
  /// - [nuevaCuentaFinancieraId]: mueve la Compra a esa Cuenta
  ///   financiera. Si ya estaba en Cuenta, reutiliza el MISMO `Egreso`
  ///   (nunca cancela+crea) — solo repunta `cuentaFinancieraId` si
  ///   cambió, y corrige el monto si cambió. Si venía de TDC, revierte
  ///   por completo el cargo anterior (`DeudaRepository.revertirCargoCompra`)
  ///   y crea un `Egreso` nuevo.
  /// - [nuevaDeudaId]: mueve la Compra a esa TDC. Si ya estaba en la
  ///   MISMA TDC, nunca reescribe el cargo original — registra un
  ///   ajuste auditable por la diferencia
  ///   (`DeudaRepository.registrarAjusteCargoCompra`). Si venía de otra
  ///   TDC, revierte el efecto neto en la TDC anterior y registra un
  ///   cargo nuevo en la TDC destino. Si venía de Cuenta, cancela el
  ///   `Egreso` existente y registra el cargo nuevo.
  ///
  /// Cada transición (Cuenta→misma Cuenta, Cuenta→otra Cuenta,
  /// TDC→misma TDC, TDC→otra TDC, Cuenta→TDC, TDC→Cuenta) — revertir
  /// origen anterior, aplicar origen nuevo, actualizar `Compra.egresoId`/
  /// `deudaId`, y escribir el evento de auditoría — corre dentro de la
  /// MISMA transacción que las partidas/campos administrativos: si
  /// cualquier paso falla, rollback completo, nunca queda una Compra
  /// sin origen financiero o con ambos a la vez.
  ///
  /// `CompraEvento.estadoAnterior`/`estadoNuevo` (Etapa 2) registran
  /// únicamente los campos realmente modificados — nunca solo
  /// `formaPago`, siempre también `cuentaFinancieraId`/`deudaId`/
  /// `total` cuando aplica (nunca nombres como sustituto de IDs).
  Future<CompraData> corregir({
    required String compraId,
    DateTime? fecha,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    List<CorreccionPartida> cambiosPartidas = const [],
    String? nuevaCuentaFinancieraId,
    String? nuevaDeudaId,
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
  /// `DesactivarAreaUseCase`). [motivo] es el nombre estable del enum
  /// `MotivoCancelacionCompra` (Etapa 15), nunca la etiqueta traducida.
  Future<CompraData> cancelar({
    required String compraId,
    required String motivo,
    String? detalle,
    String? observaciones,
    String? actorUsuarioId,
  });

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
  /// completo en `CompraRepositoryImpl.eliminarFisicamente`. [motivo]
  /// es el nombre estable del enum `MotivoEliminacionFisicaCompra`,
  /// nunca la etiqueta traducida.
  Future<EliminarCompraFisicamenteResultado> eliminarFisicamente({
    required String compraId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  });

  /// Vista previa de solo lectura para [eliminarCadenaPrueba] — ver el
  /// doc comment de `ResumenCadenaPruebaCompra`.
  Future<ResumenCadenaPruebaCompra> obtenerResumenCadenaPrueba(String compraId);

  /// "Eliminar cadena de prueba" (Etapa 15, limpieza segura de datos de
  /// prueba) — ver el doc comment completo en
  /// `CompraRepositoryImpl.eliminarCadenaPrueba`. [motivo] es el
  /// nombre estable del enum `MotivoCadenaPruebaCompra`, nunca la
  /// etiqueta traducida.
  Future<EliminarCadenaPruebaCompraResultado> eliminarCadenaPrueba({
    required String compraId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  });
}
