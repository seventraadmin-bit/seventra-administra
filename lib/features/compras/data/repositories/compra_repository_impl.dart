import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show EstatusAsignacion;
import 'package:riseg_one/features/inventario/data/tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart' show TipoMovimientoInventario;

import '../../domain/repositories/compra_repository.dart';
import '../../domain/usecases/cancelar_compra_usecase.dart' show MotivoCancelacionCompra, MotivoCancelacionCompraLabel;
import '../../domain/usecases/correccion_partida_compra.dart';
import '../../domain/usecases/eliminar_cadena_prueba_compra_usecase.dart';
import '../../domain/usecases/eliminar_compra_fisicamente_usecase.dart';
import '../tables/compra_partida_table.dart' show DestinoCompraPartida;
import '../tables/compra_table.dart' show TipoEventoCompra;

/// Compone con `InventarioRepository`/`ArticuloRepository`/
/// `EgresoRepository` reales (mismo criterio que
/// `PagoNominaRepositoryImpl` compone `EgresoRepository`, y que
/// `LineaTelefonicaEquipoRepositoryImpl` compone los repositorios
/// reales de Inventario) — nunca escribe directo sobre
/// `_db.movimientoInventario`/`_db.articuloUnidad`/`_db.egreso`.
class CompraRepositoryImpl implements CompraRepository {
  CompraRepositoryImpl(
    this._db,
    this._inventarioRepository,
    this._articuloRepository,
    this._egresoRepository,
    this._deudaRepository,
  );

  final AppDatabase _db;
  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;
  final EgresoRepository _egresoRepository;
  final DeudaRepository _deudaRepository;
  late final _codigoSecuencia = CodigoSecuenciaService(_db);

  @override
  Future<CompraData?> obtenerPorId(String compraId) {
    return (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingleOrNull();
  }

  @override
  Future<List<CompraPartidaData>> listarPartidas(String compraId) {
    return (_db.select(_db.compraPartida)
          ..where((t) => t.compraId.equals(compraId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<CompraEventoData>> listarEventos(String compraId) {
    return (_db.select(_db.compraEvento)
          ..where((t) => t.compraId.equals(compraId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<List<CompraData>> listar({
    DateTime? desde,
    DateTime? hasta,
    String? folio,
    String? proveedor,
    String? articuloId,
    String? estatus,
    String? formaPago,
  }) async {
    final query = _db.select(_db.compra);
    if (desde != null) query.where((t) => t.fecha.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where((t) => t.fecha.isSmallerOrEqualValue(hasta));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (formaPago != null) query.where((t) => t.formaPago.equals(formaPago));
    query.orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    var compras = await query.get();

    if (folio != null && folio.trim().isNotEmpty) {
      final f = folio.trim().toLowerCase();
      compras = compras.where((c) => c.folioCompra.toLowerCase().contains(f)).toList();
    }
    if (proveedor != null && proveedor.trim().isNotEmpty) {
      final p = proveedor.trim().toLowerCase();
      compras = compras.where((c) => (c.proveedor ?? '').toLowerCase().contains(p)).toList();
    }
    if (articuloId != null) {
      final partidas = await (_db.select(_db.compraPartida)..where((t) => t.articuloId.equals(articuloId))).get();
      final compraIdsConArticulo = partidas.map((p) => p.compraId).toSet();
      compras = compras.where((c) => compraIdsConArticulo.contains(c.id)).toList();
    }
    return compras;
  }

  @override
  Future<int> calcularTotal(String compraId) async {
    final partidas = await listarPartidas(compraId);
    return partidas.fold<int>(0, (s, p) => s + p.cantidad * p.costoUnitario);
  }

  @override
  Future<Map<String, int>> calcularTotalesPorCompra(Iterable<String> compraIds) async {
    final ids = compraIds.toSet();
    if (ids.isEmpty) return {};
    final partidas = await (_db.select(_db.compraPartida)..where((t) => t.compraId.isIn(ids))).get();
    final totales = <String, int>{};
    for (final p in partidas) {
      totales[p.compraId] = (totales[p.compraId] ?? 0) + p.cantidad * p.costoUnitario;
    }
    return totales;
  }

  @override
  Future<int> totalCompradoPorTdcEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.select(_db.compra)
      ..where((t) => t.estatus.equals('registrada') & t.deudaId.isNotNull());
    if (rangoInicio != null) query.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    final compras = await query.get();
    if (compras.isEmpty) return 0;
    final totales = await calcularTotalesPorCompra(compras.map((c) => c.id));
    return totales.values.fold<int>(0, (s, t) => s + t);
  }

  @override
  Future<Map<String, List<({String articuloId, int cantidad})>>> listarArticulosPorCompra(
    Iterable<String> compraIds,
  ) async {
    final ids = compraIds.toSet();
    if (ids.isEmpty) return {};
    final partidas = await (_db.select(_db.compraPartida)
          ..where((t) => t.compraId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final resultado = <String, List<({String articuloId, int cantidad})>>{for (final id in ids) id: []};
    for (final p in partidas) {
      if (p.destino != DestinoCompraPartida.inventario.name) continue;
      resultado[p.compraId]!.add((articuloId: p.articuloId!, cantidad: p.cantidad));
    }
    return resultado;
  }

  @override
  Future<int> totalCompradoEnRango({DateTime? desde, DateTime? hasta}) async {
    final compras = await listar(desde: desde, hasta: hasta, estatus: 'registrada');
    if (compras.isEmpty) return 0;
    final totales = await calcularTotalesPorCompra(compras.map((c) => c.id));
    return totales.values.fold<int>(0, (s, t) => s + t);
  }

  @override
  Future<List<({CompraData compra, CompraPartidaData partida})>> listarPartidasEnRango({
    DateTime? desde,
    DateTime? hasta,
    String? estatus,
  }) async {
    final compras = await listar(desde: desde, hasta: hasta, estatus: estatus);
    if (compras.isEmpty) return [];
    final ids = compras.map((c) => c.id).toSet();
    final partidas = await (_db.select(_db.compraPartida)..where((t) => t.compraId.isIn(ids))).get();
    final comprasPorId = {for (final c in compras) c.id: c};
    return [
      for (final p in partidas) (compra: comprasPorId[p.compraId]!, partida: p),
    ];
  }

  @override
  Future<List<MovimientoInventarioData>> listarMovimientosGenerados(String compraId) async {
    final partidas = await listarPartidas(compraId);
    final partidaIds = partidas.map((p) => p.id).toSet();
    if (partidaIds.isEmpty) return [];
    final puentes =
        await (_db.select(_db.compraPartidaMovimiento)..where((t) => t.compraPartidaId.isIn(partidaIds))).get();
    if (puentes.isEmpty) return [];
    final movimientoIds = puentes.map((p) => p.movimientoInventarioId).toSet();
    return (_db.select(_db.movimientoInventario)..where((t) => t.id.isIn(movimientoIds))).get();
  }

  @override
  Future<List<ArticuloUnidadData>> listarUnidadesGeneradas(String compraId) async {
    final movimientos = await listarMovimientosGenerados(compraId);
    final unidadIds = movimientos.map((m) => m.unidadId).whereType<String>().toSet();
    if (unidadIds.isEmpty) return [];
    return (_db.select(_db.articuloUnidad)..where((t) => t.id.isIn(unidadIds))).get();
  }

  @override
  Future<List<ArticuloUnidadData>> listarUnidadesPorPartida(String compraPartidaId) =>
      _unidadesDeLaPartida(compraPartidaId);

  @override
  Future<OrigenCompra?> obtenerOrigenPorEgreso(String egresoId) async {
    final compra = await (_db.select(_db.compra)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (compra == null) return null;
    return (compraId: compra.id, folioCompra: compra.folioCompra);
  }

  @override
  Future<OrigenCompra?> obtenerOrigenPorMovimiento(String movimientoInventarioId) async {
    final resultado = await obtenerOrigenesPorMovimientos([movimientoInventarioId]);
    return resultado[movimientoInventarioId];
  }

  @override
  Future<Map<String, OrigenCompra>> obtenerOrigenesPorMovimientos(Iterable<String> movimientoInventarioIds) async {
    final ids = movimientoInventarioIds.toSet();
    if (ids.isEmpty) return {};

    final puentes =
        await (_db.select(_db.compraPartidaMovimiento)..where((t) => t.movimientoInventarioId.isIn(ids))).get();
    if (puentes.isEmpty) return {};

    final partidaIds = puentes.map((p) => p.compraPartidaId).toSet();
    final partidas = await (_db.select(_db.compraPartida)..where((t) => t.id.isIn(partidaIds))).get();
    final partidasPorId = {for (final p in partidas) p.id: p};

    final compraIds = partidas.map((p) => p.compraId).toSet();
    final compras = await (_db.select(_db.compra)..where((t) => t.id.isIn(compraIds))).get();
    final comprasPorId = {for (final c in compras) c.id: c};

    final resultado = <String, OrigenCompra>{};
    for (final puente in puentes) {
      final partida = partidasPorId[puente.compraPartidaId];
      final compra = partida == null ? null : comprasPorId[partida.compraId];
      if (compra == null) continue;
      resultado[puente.movimientoInventarioId] = (compraId: compra.id, folioCompra: compra.folioCompra);
    }
    return resultado;
  }

  Future<void> _componerPartidaInventario({
    required String compraPartidaId,
    required PartidaCompraInput partida,
    required String folioCompra,
    required DateTime fecha,
    String? actorUsuarioId,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
    if (articulo == null) return;

    if (articulo.manejaSerie) {
      for (final numeroSerie in partida.numerosSerie!) {
        final codigoUnidad = await _codigoSecuencia.siguienteCodigo('articulo_unidad');
        final unidad = await _inventarioRepository.registrarEntradaUnidad(
          articuloId: partida.articuloId!,
          codigo: codigoUnidad,
          numeroSerie: numeroSerie,
          marca: partida.marca,
          modelo: partida.modelo,
          costoUnitario: partida.costoUnitario,
          fecha: fecha,
          observaciones: 'Compra $folioCompra',
          actorUsuarioId: actorUsuarioId,
        );
        final movimientos = await _inventarioRepository.listarMovimientos(unidadId: unidad.id);
        await _db.into(_db.compraPartidaMovimiento).insert(
              CompraPartidaMovimientoCompanion.insert(
                compraPartidaId: compraPartidaId,
                movimientoInventarioId: movimientos.single.id,
              ),
            );
      }
    } else {
      final movimiento = await _inventarioRepository.registrarEntrada(
        articuloId: partida.articuloId!,
        varianteId: partida.varianteId,
        cantidad: partida.cantidad,
        costoUnitario: partida.costoUnitario,
        fecha: fecha,
        observaciones: 'Compra $folioCompra',
        actorUsuarioId: actorUsuarioId,
      );
      await _db.into(_db.compraPartidaMovimiento).insert(
            CompraPartidaMovimientoCompanion.insert(
              compraPartidaId: compraPartidaId,
              movimientoInventarioId: movimiento.id,
            ),
          );
    }
  }

  @override
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
  }) {
    return _db.transaction(() async {
      final montoTotal = partidas.fold<int>(0, (s, p) => s + p.cantidad * p.costoUnitario);
      final esTarjeta = formaPago == 'tarjeta';
      if (esTarjeta && deudaId == null) {
        throw StateError('Una Compra con formaPago == tarjeta requiere una tarjeta (deudaId).');
      }

      // La Compra se inserta primero en ambas ramas: el cargo de
      // tarjeta necesita `compra.id` real para su vínculo determinista
      // (`MovimientoDeuda.compraId`); el Egreso, en cambio, no depende
      // de la Compra (se enlaza después vía `Compra.egresoId`, como
      // siempre).
      var compra = await _db.into(_db.compra).insertReturning(
            CompraCompanion.insert(
              folioCompra: folioCompra,
              fecha: fecha,
              proveedor: Value(proveedor),
              formaPago: formaPago,
              formaPagoOtroDescripcion: Value(formaPagoOtroDescripcion),
              observaciones: Value(observaciones),
              deudaId: Value(deudaId),
            ),
          );

      // Etapa 19B: pagada con tarjeta → nunca genera Egreso (el gasto
      // operativo se reconoce vía el cargo a la tarjeta, no aquí — ver
      // el doc comment de `Compra`); cualquier otra forma de pago
      // conserva el comportamiento original sin cambios.
      if (esTarjeta) {
        await _deudaRepository.registrarCargoCompra(
          deudaId: deudaId!,
          compraId: compra.id,
          monto: montoTotal,
          fecha: fecha,
          observaciones:
              proveedor == null || proveedor.trim().isEmpty ? 'Compra $folioCompra' : 'Compra $folioCompra · $proveedor',
          actorUsuarioId: actorUsuarioId,
        );
      } else {
        final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
        final egreso = await _egresoRepository.crear(
          folioEgreso: folioEgreso,
          monto: montoTotal,
          fecha: fecha,
          cuentaFinancieraId: cuentaFinancieraId,
          formaPago: formaPago,
          beneficiario: proveedor,
          concepto: proveedor == null || proveedor.trim().isEmpty ? 'Compra $folioCompra' : 'Compra $folioCompra · $proveedor',
          observaciones: observaciones,
          actorUsuarioId: actorUsuarioId,
        );
        compra = await (_db.update(_db.compra)..where((t) => t.id.equals(compra.id)))
            .writeReturning(CompraCompanion(egresoId: Value(egreso.id)))
            .then((rows) => rows.single);
      }

      for (final partida in partidas) {
        final partidaRow = await _db.into(_db.compraPartida).insertReturning(
              CompraPartidaCompanion.insert(
                compraId: compra.id,
                destino: partida.destino,
                articuloId: Value(partida.articuloId),
                varianteId: Value(partida.varianteId),
                concepto: Value(partida.concepto),
                cantidad: partida.cantidad,
                costoUnitario: partida.costoUnitario,
              ),
            );

        if (partida.destino == DestinoCompraPartida.inventario.name) {
          await _componerPartidaInventario(
            compraPartidaId: partidaRow.id,
            partida: partida,
            folioCompra: folioCompra,
            fecha: fecha,
            actorUsuarioId: actorUsuarioId,
          );
        }
      }

      await _registrarEventoInterno(
        compraId: compra.id,
        tipoEvento: TipoEventoCompra.registrada,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'folioCompra': folioCompra, 'montoTotal': montoTotal, 'partidas': partidas.length},
      );

      return compra;
    });
  }

  /// Movimientos que pertenecen exclusivamente a una `CompraPartida`
  /// puntual — nunca por texto/descripción, siempre vía
  /// `CompraPartidaMovimiento` (Etapa 15, ampliación de "Corregir
  /// datos").
  Future<List<MovimientoInventarioData>> _movimientosDeLaPartida(String compraPartidaId) async {
    final puentes =
        await (_db.select(_db.compraPartidaMovimiento)..where((t) => t.compraPartidaId.equals(compraPartidaId))).get();
    if (puentes.isEmpty) return [];
    final ids = puentes.map((p) => p.movimientoInventarioId).toSet();
    return (_db.select(_db.movimientoInventario)..where((t) => t.id.isIn(ids))).get();
  }

  /// Unidades vigentes de la partida — excluye las ya dadas de baja
  /// por una corrección previa (nunca se vuelve a procesar una unidad
  /// que esta misma partida ya retiró, mismo criterio que
  /// `RegistrarBajaUnidadUseCase` nunca da de baja dos veces).
  Future<List<ArticuloUnidadData>> _unidadesDeLaPartida(String compraPartidaId) async {
    final movimientos = await _movimientosDeLaPartida(compraPartidaId);
    final unidadIds = movimientos.map((m) => m.unidadId).whereType<String>().toSet();
    if (unidadIds.isEmpty) return [];
    return (_db.select(_db.articuloUnidad)
          ..where((t) => t.id.isIn(unidadIds) & t.estatus.equals(EstatusArticuloUnidad.baja.name).not()))
        .get();
  }

  /// Misma regla ya usada por [obtenerResumenEliminacionFisica], a
  /// nivel de una sola unidad serializada: asignada, vinculada a
  /// telefonía, o con movimientos ajenos.
  Future<String?> _detalleBloqueoUnidad(ArticuloUnidadData unidad) async {
    final asignaciones = await (_db.select(_db.asignacion)..where((t) => t.unidadId.equals(unidad.id))).get();
    if (asignaciones.isNotEmpty) {
      return 'La unidad ${unidad.codigo} ya fue asignada a un empleado o servicio — no puede corregirse.';
    }
    final lineasEquipo = await (_db.select(_db.lineaTelefonicaEquipo)..where((t) => t.unidadId.equals(unidad.id))).get();
    if (lineasEquipo.isNotEmpty) {
      return 'La unidad ${unidad.codigo} está vinculada a una línea telefónica — no puede corregirse.';
    }
    final movimientosUnidad = await _inventarioRepository.listarMovimientos(unidadId: unidad.id);
    final propios = await (_db.select(_db.compraPartidaMovimiento)
          ..where((t) => t.movimientoInventarioId.isIn(movimientosUnidad.map((m) => m.id))))
        .get();
    if (movimientosUnidad.length > propios.length) {
      return 'La unidad ${unidad.codigo} tiene movimientos adicionales registrados — no puede corregirse.';
    }
    return null;
  }

  /// Tipos de `MovimientoInventario` que reducen `disponible` — usados
  /// por [_tieneMovimientosDeSalidaAjenos] para la política conservadora
  /// de partidas por cantidad.
  static const _tiposMovimientoSalida = {'baja', 'ajusteSalida', 'salidaAsignacion', 'salidaDano', 'salidaPerdida'};

  /// Política conservadora para un artículo/variante SIN número de
  /// serie (existencia fungible, agrupada en un solo `disponible`
  /// pooled): no hay forma de saber si el remanente que corresponde
  /// específicamente a [compraId] ya se consumió, así que se bloquea si
  /// existe CUALQUIER movimiento de salida (`baja` manual,
  /// `ajusteSalida`, `salidaAsignacion`, `salidaDano`, `salidaPerdida`)
  /// sobre ese artículo/variante que no pertenezca a esta misma Compra
  /// (vía `CompraPartidaMovimiento`) — los propios (la entrada original
  /// y, si ya se canceló antes, su baja de reversa) nunca cuentan como
  /// bloqueo.
  ///
  /// Amplía la política previa (Etapa 15, verificación explícita de
  /// Marlon): antes solo se verificaba la tabla `Asignacion`, lo cual
  /// dejaba pasar el caso real de `RegistrarBajaUseCase`/
  /// `RegistrarAjusteUseCase` — ambos consumen existencia fungible
  /// (tipos `baja`/`ajusteSalida`) sin generar ninguna `Asignacion`.
  /// `salidaAsignacion` sigue cubriendo el caso original: `Asignacion.crear`
  /// siempre inserta ese movimiento en la misma transacción.
  Future<bool> _tieneMovimientosDeSalidaAjenos({
    required String articuloId,
    String? varianteId,
    required String compraId,
  }) async {
    final propios = (await listarMovimientosGenerados(compraId)).map((m) => m.id).toSet();
    final movimientos = await (_db.select(_db.movimientoInventario)
          ..where(
            (t) => t.articuloId.equals(articuloId) &
                (varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(varianteId)) &
                t.tipoMovimiento.isIn(_tiposMovimientoSalida),
          ))
        .get();
    return movimientos.any((m) => !propios.contains(m.id));
  }

  /// Envoltura de [_tieneMovimientosDeSalidaAjenos] con el mensaje
  /// compartido que usa `corregir()` — ver el doc comment de ese
  /// método para la política completa.
  Future<String?> _detalleBloqueoArticuloVariante(String articuloId, String? varianteId, {required String compraId}) async {
    final bloqueado =
        await _tieneMovimientosDeSalidaAjenos(articuloId: articuloId, varianteId: varianteId, compraId: compraId);
    if (bloqueado) {
      return 'El artículo de esta partida tiene movimientos de salida registrados (asignación, baja o ajuste) — no '
          'puede reducirse/corregirse esta cantidad de forma segura.';
    }
    return null;
  }

  /// Implementa [CompraRepository.listarDetalleBloqueoCancelacionPorCantidad]
  /// — misma política conservadora exacta que [_tieneMovimientosDeSalidaAjenos],
  /// aplicada a cada partida por CANTIDAD (artículo sin número de
  /// serie) de esta Compra. Las partidas de artículos serializados se
  /// ignoran aquí — esas ya se verifican por unidad individual en
  /// `CancelarCompraUseCase` vía [listarUnidadesGeneradas].
  @override
  Future<List<String>> listarDetalleBloqueoCancelacionPorCantidad(String compraId) async {
    final partidas = await listarPartidas(compraId);
    final detalles = <String>[];
    for (final partida in partidas) {
      if (partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) continue;
      final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
      if (articulo == null || articulo.manejaSerie) continue;

      final bloqueado = await _tieneMovimientosDeSalidaAjenos(
        articuloId: articulo.id,
        varianteId: partida.varianteId,
        compraId: compraId,
      );
      if (bloqueado) {
        detalles.add(
          'El artículo ${articulo.nombre} de esta Compra tiene movimientos de salida registrados (asignación, baja '
          'o ajuste) — no puede cancelarse esta Compra sin dejar existencia negativa.',
        );
      }
    }
    return detalles;
  }

  /// Recorre los cambios propuestos y devuelve el primer bloqueo real
  /// encontrado — solo revisa lo que efectivamente reduce/sustituye
  /// existencia (aumentar cantidad, agregar partida, o solo cambiar
  /// costo, siempre son seguros).
  Future<String?> _detalleBloqueoCambios(List<CorreccionPartida> cambios) async {
    for (final cambio in cambios) {
      switch (cambio) {
        case CorreccionPartidaCantidadCosto(
            :final compraPartidaId,
            :final nuevaCantidad,
            :final unidadesIdAEliminar,
          ):
          final partida =
              await (_db.select(_db.compraPartida)..where((t) => t.id.equals(compraPartidaId))).getSingleOrNull();
          if (partida == null) continue;
          if (unidadesIdAEliminar.isNotEmpty) {
            for (final unidadId in unidadesIdAEliminar) {
              final unidad = await (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingleOrNull();
              if (unidad == null) continue;
              final bloqueo = await _detalleBloqueoUnidad(unidad);
              if (bloqueo != null) return bloqueo;
            }
          } else if (nuevaCantidad != null &&
              nuevaCantidad < partida.cantidad &&
              partida.destino == DestinoCompraPartida.inventario.name &&
              partida.articuloId != null) {
            final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
            if (articulo != null && !articulo.manejaSerie) {
              final bloqueo = await _detalleBloqueoArticuloVariante(partida.articuloId!, partida.varianteId, compraId: partida.compraId);
              if (bloqueo != null) return bloqueo;
            }
          }
        case CorreccionPartidaVariante(:final compraPartidaId):
          final partida =
              await (_db.select(_db.compraPartida)..where((t) => t.id.equals(compraPartidaId))).getSingleOrNull();
          if (partida == null || partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) {
            continue;
          }
          final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
          if (articulo == null) continue;
          if (articulo.manejaSerie) {
            for (final unidad in await _unidadesDeLaPartida(partida.id)) {
              final bloqueo = await _detalleBloqueoUnidad(unidad);
              if (bloqueo != null) return bloqueo;
            }
          } else {
            final bloqueo = await _detalleBloqueoArticuloVariante(partida.articuloId!, partida.varianteId, compraId: partida.compraId);
            if (bloqueo != null) return bloqueo;
          }
        case CorreccionPartidaAgregar():
          continue;
        case CorreccionPartidaQuitar(:final compraPartidaId):
          final partida =
              await (_db.select(_db.compraPartida)..where((t) => t.id.equals(compraPartidaId))).getSingleOrNull();
          if (partida == null || partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) {
            continue;
          }
          final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
          if (articulo == null) continue;
          if (articulo.manejaSerie) {
            for (final unidad in await _unidadesDeLaPartida(partida.id)) {
              final bloqueo = await _detalleBloqueoUnidad(unidad);
              if (bloqueo != null) return bloqueo;
            }
          } else {
            final bloqueo = await _detalleBloqueoArticuloVariante(partida.articuloId!, partida.varianteId, compraId: partida.compraId);
            if (bloqueo != null) return bloqueo;
          }
      }
    }
    return null;
  }

  @override
  Future<ResumenCorreccionCompra> obtenerResumenCorreccion({
    required String compraId,
    List<CorreccionPartida> cambiosPartidas = const [],
  }) async {
    final compra = await obtenerPorId(compraId);
    if (compra == null) return const ResumenCorreccionCompra(existe: false);

    final bloqueo = await _detalleBloqueoCambios(cambiosPartidas);
    if (bloqueo != null) return ResumenCorreccionCompra(existe: true, detalleBloqueo: bloqueo);

    final totalAnterior = await calcularTotal(compraId);
    var totalNuevo = totalAnterior;
    for (final cambio in cambiosPartidas) {
      switch (cambio) {
        case CorreccionPartidaCantidadCosto(:final compraPartidaId, :final nuevaCantidad, :final nuevoCostoUnitario):
          final partida =
              await (_db.select(_db.compraPartida)..where((t) => t.id.equals(compraPartidaId))).getSingleOrNull();
          if (partida == null) continue;
          totalNuevo -= partida.cantidad * partida.costoUnitario;
          totalNuevo += (nuevaCantidad ?? partida.cantidad) * (nuevoCostoUnitario ?? partida.costoUnitario);
        case CorreccionPartidaVariante():
          continue;
        case CorreccionPartidaAgregar(:final input):
          totalNuevo += input.cantidad * input.costoUnitario;
        case CorreccionPartidaQuitar(:final compraPartidaId):
          final partida =
              await (_db.select(_db.compraPartida)..where((t) => t.id.equals(compraPartidaId))).getSingleOrNull();
          if (partida == null) continue;
          totalNuevo -= partida.cantidad * partida.costoUnitario;
      }
    }

    return ResumenCorreccionCompra(existe: true, totalAnterior: totalAnterior, totalNuevo: totalNuevo);
  }

  Future<void> _aplicarCambioCantidadCosto(
    CorreccionPartidaCantidadCosto cambio,
    String? actorUsuarioId,
    List<Map<String, Object?>> detalles,
  ) async {
    final partida = await (_db.select(_db.compraPartida)..where((t) => t.id.equals(cambio.compraPartidaId))).getSingle();
    final esInventario = partida.destino == DestinoCompraPartida.inventario.name;
    final articulo =
        (esInventario && partida.articuloId != null) ? await _articuloRepository.obtenerPorId(partida.articuloId!) : null;
    final costoEfectivo = cambio.nuevoCostoUnitario ?? partida.costoUnitario;

    if (cambio.nuevoCostoUnitario != null && cambio.nuevoCostoUnitario != partida.costoUnitario && esInventario) {
      for (final m in await _movimientosDeLaPartida(partida.id)) {
        await (_db.update(_db.movimientoInventario)..where((t) => t.id.equals(m.id)))
            .write(MovimientoInventarioCompanion(costoUnitario: Value(cambio.nuevoCostoUnitario)));
      }
    }

    if (esInventario && articulo != null) {
      if (articulo.manejaSerie) {
        for (final serie in cambio.numerosSerieNuevos) {
          final codigoUnidad = await _codigoSecuencia.siguienteCodigo('articulo_unidad');
          final unidad = await _inventarioRepository.registrarEntradaUnidad(
            articuloId: partida.articuloId!,
            codigo: codigoUnidad,
            numeroSerie: serie,
            costoUnitario: costoEfectivo,
            fecha: DateTime.now(),
            observaciones: 'Corrección de Compra (partida ${partida.id})',
            actorUsuarioId: actorUsuarioId,
          );
          final mov = (await _inventarioRepository.listarMovimientos(unidadId: unidad.id)).single;
          await _db.into(_db.compraPartidaMovimiento).insert(
                CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: mov.id),
              );
        }
        for (final unidadId in cambio.unidadesIdAEliminar) {
          await _inventarioRepository.registrarBajaUnidad(
            unidadId: unidadId,
            observaciones: 'Corrección de Compra (partida ${partida.id})',
            actorUsuarioId: actorUsuarioId,
          );
          final movimientosUnidad = await _inventarioRepository.listarMovimientos(unidadId: unidadId);
          final baja = movimientosUnidad.firstWhere((m) => m.tipoMovimiento == TipoMovimientoInventario.baja.name);
          await _db.into(_db.compraPartidaMovimiento).insert(
                CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: baja.id),
              );
        }
      } else if (cambio.nuevaCantidad != null && cambio.nuevaCantidad != partida.cantidad) {
        final delta = cambio.nuevaCantidad! - partida.cantidad;
        final MovimientoInventarioData mov;
        if (delta > 0) {
          mov = await _inventarioRepository.registrarEntrada(
            articuloId: partida.articuloId!,
            varianteId: partida.varianteId,
            cantidad: delta,
            costoUnitario: costoEfectivo,
            fecha: DateTime.now(),
            observaciones: 'Corrección de Compra (partida ${partida.id})',
            actorUsuarioId: actorUsuarioId,
          );
        } else {
          mov = await _inventarioRepository.registrarBaja(
            articuloId: partida.articuloId!,
            varianteId: partida.varianteId,
            cantidad: -delta,
            observaciones: 'Corrección de Compra (partida ${partida.id})',
            actorUsuarioId: actorUsuarioId,
          );
        }
        await _db.into(_db.compraPartidaMovimiento).insert(
              CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: mov.id),
            );
      }
    }

    final cantidadFinal = (articulo?.manejaSerie ?? false)
        ? partida.cantidad + cambio.numerosSerieNuevos.length - cambio.unidadesIdAEliminar.length
        : (cambio.nuevaCantidad ?? partida.cantidad);

    await (_db.update(_db.compraPartida)..where((t) => t.id.equals(partida.id)))
        .write(CompraPartidaCompanion(cantidad: Value(cantidadFinal), costoUnitario: Value(costoEfectivo)));

    detalles.add({
      'partidaId': partida.id,
      'cantidadAnterior': partida.cantidad,
      'cantidadNueva': cantidadFinal,
      'costoAnterior': partida.costoUnitario,
      'costoNuevo': costoEfectivo,
    });
  }

  Future<void> _aplicarCambioVariante(
    CorreccionPartidaVariante cambio,
    String? actorUsuarioId,
    List<Map<String, Object?>> detalles,
  ) async {
    final partida = await (_db.select(_db.compraPartida)..where((t) => t.id.equals(cambio.compraPartidaId))).getSingle();
    final articuloAnterior =
        partida.articuloId == null ? null : await _articuloRepository.obtenerPorId(partida.articuloId!);

    if (articuloAnterior != null && articuloAnterior.manejaSerie) {
      // Sustitución de unidad (caso B: no es la misma unidad, es un
      // artículo distinto) — nunca se reutiliza/renombra la unidad
      // anterior, se da de baja y se crean unidades nuevas.
      for (final unidad in await _unidadesDeLaPartida(partida.id)) {
        await _inventarioRepository.registrarBajaUnidad(
          unidadId: unidad.id,
          observaciones: 'Corrección de Compra: sustitución de artículo (partida ${partida.id})',
          actorUsuarioId: actorUsuarioId,
        );
        final movimientosUnidad = await _inventarioRepository.listarMovimientos(unidadId: unidad.id);
        final baja = movimientosUnidad.firstWhere((m) => m.tipoMovimiento == TipoMovimientoInventario.baja.name);
        await _db.into(_db.compraPartidaMovimiento).insert(
              CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: baja.id),
            );
      }
      for (final serie in cambio.numerosSerieNuevos) {
        final codigoUnidad = await _codigoSecuencia.siguienteCodigo('articulo_unidad');
        final nueva = await _inventarioRepository.registrarEntradaUnidad(
          articuloId: cambio.nuevoArticuloId,
          codigo: codigoUnidad,
          numeroSerie: serie,
          costoUnitario: cambio.nuevoCostoUnitario ?? partida.costoUnitario,
          fecha: DateTime.now(),
          observaciones: 'Corrección de Compra: sustitución de artículo (partida ${partida.id})',
          actorUsuarioId: actorUsuarioId,
        );
        final mov = (await _inventarioRepository.listarMovimientos(unidadId: nueva.id)).single;
        await _db.into(_db.compraPartidaMovimiento).insert(
              CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: mov.id),
            );
      }
    } else if (partida.destino == DestinoCompraPartida.inventario.name && partida.articuloId != null) {
      final reversa = await _inventarioRepository.registrarBaja(
        articuloId: partida.articuloId!,
        varianteId: partida.varianteId,
        cantidad: partida.cantidad,
        observaciones: 'Corrección de Compra: cambio de artículo/variante (partida ${partida.id})',
        actorUsuarioId: actorUsuarioId,
      );
      await _db.into(_db.compraPartidaMovimiento).insert(
            CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: reversa.id),
          );
      final nuevo = await _inventarioRepository.registrarEntrada(
        articuloId: cambio.nuevoArticuloId,
        varianteId: cambio.nuevaVarianteId,
        cantidad: cambio.nuevaCantidad ?? partida.cantidad,
        costoUnitario: cambio.nuevoCostoUnitario ?? partida.costoUnitario,
        fecha: DateTime.now(),
        observaciones: 'Corrección de Compra: cambio de artículo/variante (partida ${partida.id})',
        actorUsuarioId: actorUsuarioId,
      );
      await _db.into(_db.compraPartidaMovimiento).insert(
            CompraPartidaMovimientoCompanion.insert(compraPartidaId: partida.id, movimientoInventarioId: nuevo.id),
          );
    }

    final cantidadEfectiva = articuloAnterior != null && articuloAnterior.manejaSerie
        ? cambio.numerosSerieNuevos.length
        : cambio.nuevaCantidad ?? partida.cantidad;
    final costoEfectivo = cambio.nuevoCostoUnitario ?? partida.costoUnitario;

    await (_db.update(_db.compraPartida)..where((t) => t.id.equals(partida.id))).write(
      CompraPartidaCompanion(
        articuloId: Value(cambio.nuevoArticuloId),
        varianteId: Value(cambio.nuevaVarianteId),
        cantidad: Value(cantidadEfectiva),
        costoUnitario: Value(costoEfectivo),
      ),
    );

    detalles.add({
      'partidaId': partida.id,
      'articuloAnterior': partida.articuloId,
      'varianteAnterior': partida.varianteId,
      'articuloNuevo': cambio.nuevoArticuloId,
      'varianteNueva': cambio.nuevaVarianteId,
      if (cantidadEfectiva != partida.cantidad) 'cantidadAnterior': partida.cantidad,
      if (cantidadEfectiva != partida.cantidad) 'cantidadNueva': cantidadEfectiva,
      if (costoEfectivo != partida.costoUnitario) 'costoUnitarioAnterior': partida.costoUnitario,
      if (costoEfectivo != partida.costoUnitario) 'costoUnitarioNuevo': costoEfectivo,
    });
  }

  Future<void> _aplicarAgregarPartida(
    String compraId,
    String folioCompra,
    DateTime fechaCompra,
    CorreccionPartidaAgregar cambio,
    String? actorUsuarioId,
    List<Map<String, Object?>> detalles,
  ) async {
    final input = cambio.input;
    final partidaRow = await _db.into(_db.compraPartida).insertReturning(
          CompraPartidaCompanion.insert(
            compraId: compraId,
            destino: input.destino,
            articuloId: Value(input.articuloId),
            varianteId: Value(input.varianteId),
            concepto: Value(input.concepto),
            cantidad: input.cantidad,
            costoUnitario: input.costoUnitario,
          ),
        );

    if (input.destino == DestinoCompraPartida.inventario.name) {
      await _componerPartidaInventario(
        compraPartidaId: partidaRow.id,
        partida: input,
        folioCompra: folioCompra,
        fecha: fechaCompra,
        actorUsuarioId: actorUsuarioId,
      );
    }

    detalles.add({
      'partidaId': partidaRow.id,
      'agregada': true,
      'articuloId': input.articuloId,
      'cantidad': input.cantidad,
      'costoUnitario': input.costoUnitario,
    });
  }

  Future<void> _aplicarQuitarPartida(
    CorreccionPartidaQuitar cambio,
    String? actorUsuarioId,
    List<Map<String, Object?>> detalles,
  ) async {
    final partida = await (_db.select(_db.compraPartida)..where((t) => t.id.equals(cambio.compraPartidaId))).getSingle();
    final articulo = partida.articuloId == null ? null : await _articuloRepository.obtenerPorId(partida.articuloId!);

    if (partida.destino == DestinoCompraPartida.inventario.name && partida.articuloId != null) {
      if (articulo != null && articulo.manejaSerie) {
        for (final unidad in await _unidadesDeLaPartida(partida.id)) {
          await _inventarioRepository.registrarBajaUnidad(
            unidadId: unidad.id,
            observaciones: 'Corrección de Compra: partida eliminada (${partida.id})',
            actorUsuarioId: actorUsuarioId,
          );
        }
      } else {
        await _inventarioRepository.registrarBaja(
          articuloId: partida.articuloId!,
          varianteId: partida.varianteId,
          cantidad: partida.cantidad,
          observaciones: 'Corrección de Compra: partida eliminada (${partida.id})',
          actorUsuarioId: actorUsuarioId,
        );
      }
    }

    // Libera el `restrict` de `CompraPartidaMovimiento` — los propios
    // `MovimientoInventario` (entrada + la reversa recién creada) se
    // conservan intactos en el ledger, solo quedan sin partida que los
    // referencie (mismo criterio de nunca editar/borrar un movimiento).
    await (_db.delete(_db.compraPartidaMovimiento)..where((t) => t.compraPartidaId.equals(partida.id))).go();
    await (_db.delete(_db.compraPartida)..where((t) => t.id.equals(partida.id))).go();

    detalles.add({
      'partidaId': partida.id,
      'quitada': true,
      'articuloId': partida.articuloId,
      'cantidad': partida.cantidad,
    });
  }

  @override
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
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();
      final totalAnterior = await calcularTotal(compraId);

      // Etapa 3: la Cuenta financiera ACTUAL no vive en `Compra` — hay
      // que leerla del `Egreso` vinculado (si existe) para poder
      // compararla contra `nuevaCuentaFinancieraId` y para la
      // auditoría before/after.
      String? cuentaFinancieraIdAnterior;
      if (anterior.egresoId != null) {
        cuentaFinancieraIdAnterior = (await _egresoRepository.obtenerPorId(anterior.egresoId!))?.cuentaFinancieraId;
      }

      // El `formaPago` a persistir se DERIVA del origen destino cuando
      // se pide un cambio de origen — nunca un valor independiente que
      // pueda desincronizarse del FK real (el bug original de Etapa 0).
      final formaPagoAEscribir = nuevaDeudaId != null ? FormaPago.tarjeta.name : (formaPago ?? anterior.formaPago);

      if (cambiosPartidas.isNotEmpty) {
        final bloqueo = await _detalleBloqueoCambios(cambiosPartidas);
        if (bloqueo != null) throw StateError(bloqueo);
      }

      await (_db.update(_db.compra)..where((t) => t.id.equals(compraId))).write(
        CompraCompanion(
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          proveedor: proveedor == null ? const Value.absent() : Value(proveedor),
          formaPago: Value(formaPagoAEscribir),
          formaPagoOtroDescripcion: formaPagoOtroDescripcion == null ? const Value.absent() : Value(formaPagoOtroDescripcion),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final detallesPartidas = <Map<String, Object?>>[];
      for (final cambio in cambiosPartidas) {
        switch (cambio) {
          case CorreccionPartidaCantidadCosto():
            await _aplicarCambioCantidadCosto(cambio, actorUsuarioId, detallesPartidas);
          case CorreccionPartidaVariante():
            await _aplicarCambioVariante(cambio, actorUsuarioId, detallesPartidas);
          case CorreccionPartidaAgregar():
            await _aplicarAgregarPartida(
              compraId,
              anterior.folioCompra,
              fecha ?? anterior.fecha,
              cambio,
              actorUsuarioId,
              detallesPartidas,
            );
          case CorreccionPartidaQuitar():
            await _aplicarQuitarPartida(cambio, actorUsuarioId, detallesPartidas);
        }
      }

      final totalNuevo = await calcularTotal(compraId);

      // --- Origen financiero: las 6 transiciones (Etapa 3) ---
      // `egresoIdNuevo`/`deudaIdNuevo`/`cuentaFinancieraIdNueva`
      // arrancan en su valor ACTUAL — cada rama solo los toca si de
      // verdad cambia algo, y todas corren dentro de esta misma
      // transacción (Drift anida `_db.transaction` de forma segura):
      // revertir el origen anterior, aplicar el nuevo, y más abajo
      // actualizar la FK de `Compra` — si cualquier paso falla
      // (`DeudaRepository`/`EgresoRepository` lanzan sobre un id que no
      // existe, por ejemplo), la transacción completa hace rollback y
      // nunca queda una Compra sin origen o con ambos.
      var egresoIdNuevo = anterior.egresoId;
      var deudaIdNuevo = anterior.deudaId;
      var cuentaFinancieraIdNueva = cuentaFinancieraIdAnterior;

      if (nuevaCuentaFinancieraId != null) {
        if (anterior.egresoId != null) {
          // A. Cuenta → misma Cuenta / B. Cuenta → otra Cuenta —
          // reutiliza el MISMO Egreso, nunca crea uno segundo.
          if (nuevaCuentaFinancieraId != cuentaFinancieraIdAnterior) {
            await _egresoRepository.corregir(
              egresoId: anterior.egresoId!,
              cuentaFinancieraId: nuevaCuentaFinancieraId,
              motivo: motivo,
              actorUsuarioId: actorUsuarioId,
            );
          }
          if (totalNuevo != totalAnterior) {
            await _egresoRepository.corregirMonto(
              egresoId: anterior.egresoId!,
              nuevoMonto: totalNuevo,
              motivo: motivo,
              actorUsuarioId: actorUsuarioId,
            );
          }
          cuentaFinancieraIdNueva = nuevaCuentaFinancieraId;
        } else {
          // F. TDC → Cuenta — revierte el cargo por completo, crea un
          // Egreso nuevo (mismo criterio que el alta original).
          await _deudaRepository.revertirCargoCompra(
            deudaId: anterior.deudaId!,
            compraId: compraId,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
          final proveedorEfectivo = proveedor ?? anterior.proveedor;
          final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
          final egresoNuevo = await _egresoRepository.crear(
            folioEgreso: folioEgreso,
            monto: totalNuevo,
            fecha: fecha ?? anterior.fecha,
            cuentaFinancieraId: nuevaCuentaFinancieraId,
            formaPago: formaPagoAEscribir,
            beneficiario: proveedorEfectivo,
            concepto: proveedorEfectivo == null || proveedorEfectivo.trim().isEmpty
                ? 'Compra ${anterior.folioCompra}'
                : 'Compra ${anterior.folioCompra} · $proveedorEfectivo',
            observaciones: observaciones ?? anterior.observaciones,
            actorUsuarioId: actorUsuarioId,
          );
          egresoIdNuevo = egresoNuevo.id;
          deudaIdNuevo = null;
          cuentaFinancieraIdNueva = nuevaCuentaFinancieraId;
        }
      } else if (nuevaDeudaId != null) {
        if (anterior.deudaId == nuevaDeudaId) {
          // C. TDC → misma TDC — nunca reescribe el cargo original, un
          // ajuste auditable por la diferencia.
          if (totalNuevo != totalAnterior) {
            await _deudaRepository.registrarAjusteCargoCompra(
              deudaId: nuevaDeudaId,
              compraId: compraId,
              deltaImporte: totalNuevo - totalAnterior,
              motivo: motivo,
              actorUsuarioId: actorUsuarioId,
            );
          }
        } else if (anterior.deudaId != null) {
          // D. TDC → otra TDC — revierte el efecto neto en la TDC
          // anterior, cargo nuevo en la TDC destino.
          await _deudaRepository.revertirCargoCompra(
            deudaId: anterior.deudaId!,
            compraId: compraId,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
          await _deudaRepository.registrarCargoCompra(
            deudaId: nuevaDeudaId,
            compraId: compraId,
            monto: totalNuevo,
            fecha: fecha ?? anterior.fecha,
            observaciones: motivo,
            actorUsuarioId: actorUsuarioId,
          );
          deudaIdNuevo = nuevaDeudaId;
        } else {
          // E. Cuenta → TDC — cancela el Egreso existente, cargo nuevo.
          await _egresoRepository.cancelar(
            egresoId: anterior.egresoId!,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
          await _deudaRepository.registrarCargoCompra(
            deudaId: nuevaDeudaId,
            compraId: compraId,
            monto: totalNuevo,
            fecha: fecha ?? anterior.fecha,
            observaciones: motivo,
            actorUsuarioId: actorUsuarioId,
          );
          egresoIdNuevo = null;
          deudaIdNuevo = nuevaDeudaId;
          cuentaFinancieraIdNueva = null;
        }
      } else {
        // Sin cambio de origen solicitado — mismo comportamiento que
        // antes de esta etapa: solo sincroniza el monto en el origen
        // YA vigente, si cambió por partidas.
        if (totalNuevo != totalAnterior && anterior.egresoId != null) {
          await _egresoRepository.corregirMonto(
            egresoId: anterior.egresoId!,
            nuevoMonto: totalNuevo,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        } else if (totalNuevo != totalAnterior && anterior.deudaId != null) {
          await _deudaRepository.registrarAjusteCargoCompra(
            deudaId: anterior.deudaId!,
            compraId: compraId,
            deltaImporte: totalNuevo - totalAnterior,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
      }

      if (egresoIdNuevo != anterior.egresoId || deudaIdNuevo != anterior.deudaId) {
        await (_db.update(_db.compra)..where((t) => t.id.equals(compraId))).write(
          CompraCompanion(egresoId: Value(egresoIdNuevo), deudaId: Value(deudaIdNuevo)),
        );
      }

      // Etapa 2 (convención común de auditoría): `estadoAnterior`/
      // `estadoNuevo` ya existían como columnas en `CompraEvento` pero
      // nunca se poblaban — todo iba a `datosRelevantes`, que además
      // solo capturaba el lado "anterior" de proveedor/formaPago
      // (nunca el nuevo). `DiffEvento` reemplaza eso para los campos
      // escalares reales; `datosRelevantes` se conserva únicamente
      // para `partidas`, una estructura (lista de líneas cambiadas)
      // que no encaja en un simple par campo→valor. Etapa 3: nunca
      // basta con "formaPago" — si lo que cambió fue el origen real,
      // `cuentaFinancieraId`/`deudaId` (los IDs, nunca nombres) también
      // quedan en el diff.
      final diff = DiffEvento()
        ..anotar('proveedor', anterior.proveedor, proveedor ?? anterior.proveedor)
        ..anotar('formaPago', anterior.formaPago, formaPagoAEscribir)
        ..anotar('cuentaFinancieraId', cuentaFinancieraIdAnterior, cuentaFinancieraIdNueva)
        ..anotar('deudaId', anterior.deudaId, deudaIdNuevo)
        ..anotar('total', totalAnterior, totalNuevo);

      await _registrarEventoInterno(
        compraId: compraId,
        tipoEvento: TipoEventoCompra.corregida,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        estadoAnterior: diff.estadoAnteriorJson,
        estadoNuevo: diff.estadoNuevoJson,
        datosRelevantes: detallesPartidas.isEmpty ? null : {'partidas': detallesPartidas},
      );

      return (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();
    });
  }

  @override
  Future<CompraData> cancelar({
    required String compraId,
    required String motivo,
    String? detalle,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    // El código estructurado no siempre resuelve a un `MotivoCancelacionCompra`
    // conocido en teoría (defensivo — `CancelarCompraUseCase` siempre
    // manda `.name` de un valor real del enum) — si no resuelve, se usa
    // el propio código como etiqueta para el Egreso, nunca se lanza.
    final etiquetaMotivo =
        MotivoCancelacionCompra.values.where((m) => m.name == motivo).firstOrNull?.etiqueta ?? motivo;

    return _db.transaction(() async {
      final compra = await (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();

      // Idempotente ante un segundo intento (Etapa 15, verificación
      // explícita de Marlon): `CancelarCompraUseCase.ejecutar` ya
      // bloquea esto antes de llegar aquí, pero ese chequeo vive en el
      // caso de uso, no en el repositorio — este `return` reforzado
      // hace que `cancelar()` en sí mismo nunca vuelva a descontar
      // Inventario ni a cancelar el Egreso si se invoca directo una
      // segunda vez sobre una Compra ya cancelada.
      if (compra.estatus == 'cancelada') {
        return compra;
      }

      // Solo las `entrada` originales de esta Compra — nunca las
      // `baja` de reversa que una cancelación previa ya vinculó a la
      // misma `CompraPartidaMovimiento` (ver el comentario más abajo).
      // Sin este filtro, `listarMovimientosGenerados` devolvería
      // también esas bajas de reversa, y este bucle intentaría
      // "revertirlas" otra vez.
      final movimientos = (await listarMovimientosGenerados(compraId))
          .where((m) => m.tipoMovimiento == TipoMovimientoInventario.entrada.name)
          .toList();

      for (final movimiento in movimientos) {
        // El puente que ya vincula la entrada original con su
        // partida — se reutiliza la misma fila para la baja de
        // reversa (mismo `compraPartidaId`), nunca una tabla nueva.
        final puenteOriginal = await (_db.select(_db.compraPartidaMovimiento)
              ..where((t) => t.movimientoInventarioId.equals(movimiento.id)))
            .getSingle();

        final String movimientoReversaId;
        if (movimiento.unidadId != null) {
          await _inventarioRepository.registrarBajaUnidad(
            unidadId: movimiento.unidadId!,
            observaciones: 'Cancelación de Compra ${compra.folioCompra}: $etiquetaMotivo',
            actorUsuarioId: actorUsuarioId,
          );
          final movimientosUnidad = await _inventarioRepository.listarMovimientos(unidadId: movimiento.unidadId!);
          movimientoReversaId =
              movimientosUnidad.firstWhere((m) => m.tipoMovimiento == TipoMovimientoInventario.baja.name).id;
        } else {
          final reversa = await _inventarioRepository.registrarBaja(
            articuloId: movimiento.articuloId,
            varianteId: movimiento.varianteId,
            cantidad: movimiento.cantidad,
            observaciones: 'Cancelación de Compra ${compra.folioCompra}: $etiquetaMotivo',
            actorUsuarioId: actorUsuarioId,
          );
          movimientoReversaId = reversa.id;
        }

        // Sin este vínculo, la baja de reversa queda invisible para
        // `listarMovimientosGenerados`/`eliminarFisicamente` — Etapa
        // 15, hallazgo real: eliminar físicamente una Compra ya
        // cancelada borraba solo su entrada, dejando la baja de
        // reversa huérfana y la existencia en negativo.
        await _db.into(_db.compraPartidaMovimiento).insert(
              CompraPartidaMovimientoCompanion.insert(
                compraPartidaId: puenteOriginal.compraPartidaId,
                movimientoInventarioId: movimientoReversaId,
              ),
            );
      }

      await (_db.update(_db.compra)..where((t) => t.id.equals(compraId))).write(
        CompraCompanion(
          estatus: const Value('cancelada'),
          motivoCancelacionCodigo: Value(motivo),
          motivoCancelacionDetalle: Value(detalle),
          motivoCancelacionObservaciones: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (compra.egresoId != null) {
        await _egresoRepository.cancelar(
          egresoId: compra.egresoId!,
          motivo: etiquetaMotivo,
          actorUsuarioId: actorUsuarioId,
        );
      } else if (compra.deudaId != null) {
        // Etapa 19B: sin Egreso que cancelar — revierte por completo el
        // cargo a la tarjeta (un `ajusteNegativo` nuevo, nunca reescribe
        // el cargo original).
        await _deudaRepository.revertirCargoCompra(
          deudaId: compra.deudaId!,
          compraId: compraId,
          motivo: etiquetaMotivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      await _registrarEventoInterno(
        compraId: compraId,
        tipoEvento: TipoEventoCompra.cancelada,
        observacion: etiquetaMotivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'motivoCodigo': motivo,
          if (detalle != null) 'detalle': detalle,
          if (observaciones != null) 'observaciones': observaciones,
        },
      );

      return (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String compraId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.compraAttachment).insert(
            CompraAttachmentCompanion.insert(attachmentId: adjunto.id, compraId: compraId),
          );

      await _registrarEventoInterno(
        compraId: compraId,
        tipoEvento: TipoEventoCompra.comprobanteAdjuntado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  Future<void> _registrarEventoInterno({
    required String compraId,
    required TipoEventoCompra tipoEvento,
    String? estadoAnterior,
    String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, dynamic>? datosRelevantes,
  }) {
    return _db.into(_db.compraEvento).insert(
          CompraEventoCompanion.insert(
            compraId: compraId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: datosRelevantes == null ? const Value.absent() : Value(jsonEncode(datosRelevantes)),
          ),
        );
  }

  /// Único bloqueo real (Etapa 15): historia posterior a la propia
  /// Compra que no es seguro revertir. `CancelarCompraUseCase` ya
  /// verifica que cada `ArticuloUnidad` generada siga `disponible`,
  /// pero eso solo dice "nadie la tiene ahora" — no alcanza para
  /// eliminación física, que exige "nunca se movió de aquí". Por eso
  /// aquí se revisa la red de dependencias real a nivel de motor:
  /// `Asignacion`/`LineaTelefonicaEquipo` (unidad ya usada en algo
  /// real) y `MovimientoInventario` ajeno a esta Compra (otra
  /// operación tocó esta unidad después). Desde que `cancelar()`
  /// vincula su baja de reversa a la misma `CompraPartidaMovimiento`
  /// de la entrada, una Compra cancelada normal ya trae 2 movimientos
  /// por unidad (entrada + baja) — comparar contra
  /// `listarMovimientosGenerados` (los que sí le pertenecen a esta
  /// Compra) en vez de un conteo fijo evita bloquear ese caso legítimo.
  /// Para partidas por cantidad (sin unidad individual) no hay forma
  /// de saber si el remanente fungible de ESTA Compra específica fue
  /// el que se asignó — se bloquea de forma conservadora si el
  /// artículo/variante tiene cualquier `Asignacion` registrada. El
  /// Egreso propio NUNCA es un bloqueador: es parte del mismo agregado
  /// a eliminar junto con la Compra.
  @override
  Future<ResumenEliminacionCompra> obtenerResumenEliminacionFisica(String compraId) async {
    final compra = await obtenerPorId(compraId);
    if (compra == null) return const ResumenEliminacionCompra(existe: false);

    // Etapa 19B: si esta Compra financió su gasto con tarjeta, su cargo
    // solo puede revertirse si es el movimiento MÁS RECIENTE de esa
    // tarjeta — borrarlo de en medio del historial corrompería el
    // encadenamiento saldoAnterior/saldoPosterior de cualquier
    // movimiento posterior (pago, otro cargo, ajuste). Etapa 3: se
    // consulta SIEMPRE, sin importar `compra.deudaId` VIGENTE — una
    // Compra con historial Cuenta↔TDC (transiciones D/E/F) puede tener
    // `MovimientoDeuda` en una o más tarjetas aunque su origen actual
    // ya sea otro; `detalleBloqueoEliminacionCargoCompra` ya es un
    // no-op seguro cuando la Compra nunca tocó ninguna tarjeta.
    final bloqueoTarjeta = await _deudaRepository.detalleBloqueoEliminacionCargoCompra(compraId);
    if (bloqueoTarjeta != null) {
      return ResumenEliminacionCompra(existe: true, detalleBloqueo: bloqueoTarjeta);
    }

    // Serializados: cada `ArticuloUnidad` generada se verifica
    // individualmente — es la única identidad real que puede probar
    // "nunca se movió de aquí".
    final unidades = await listarUnidadesGeneradas(compraId);
    final movimientosPropios = await listarMovimientosGenerados(compraId);
    for (final unidad in unidades) {
      final asignaciones = await (_db.select(_db.asignacion)..where((t) => t.unidadId.equals(unidad.id))).get();
      if (asignaciones.isNotEmpty) {
        return ResumenEliminacionCompra(
          existe: true,
          detalleBloqueo:
              'La unidad ${unidad.codigo} generada por esta Compra fue asignada a un empleado o servicio — no '
              'puede eliminarse.',
        );
      }

      final lineasEquipo =
          await (_db.select(_db.lineaTelefonicaEquipo)..where((t) => t.unidadId.equals(unidad.id))).get();
      if (lineasEquipo.isNotEmpty) {
        return ResumenEliminacionCompra(
          existe: true,
          detalleBloqueo:
              'La unidad ${unidad.codigo} generada por esta Compra está vinculada a una línea telefónica — no '
              'puede eliminarse.',
        );
      }

      final movimientosUnidad = await _inventarioRepository.listarMovimientos(unidadId: unidad.id);
      final movimientosUnidadPropios = movimientosPropios.where((m) => m.unidadId == unidad.id).length;
      if (movimientosUnidad.length > movimientosUnidadPropios) {
        return ResumenEliminacionCompra(
          existe: true,
          detalleBloqueo:
              'La unidad ${unidad.codigo} generada por esta Compra tiene movimientos adicionales registrados '
              'después — no puede eliminarse.',
        );
      }
    }

    // Por cantidad (sin unidad individual): al ser fungible, no hay
    // forma de probar que el remanente de ESTA Compra específica no se
    // consumió ya — se bloquea de forma conservadora si el
    // artículo/variante tiene cualquier movimiento de salida (asignación,
    // baja o ajuste) ajeno a esta Compra — ver [_tieneMovimientosDeSalidaAjenos].
    final partidas = await listarPartidas(compraId);
    for (final partida in partidas) {
      if (partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) continue;
      final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
      if (articulo == null || articulo.manejaSerie) continue;

      final bloqueado = await _tieneMovimientosDeSalidaAjenos(
        articuloId: articulo.id,
        varianteId: partida.varianteId,
        compraId: compraId,
      );
      if (bloqueado) {
        return ResumenEliminacionCompra(
          existe: true,
          detalleBloqueo:
              'El artículo ${articulo.nombre} recibido por esta Compra tiene movimientos de salida registrados '
              '(asignación, baja o ajuste) — no puede eliminarse.',
        );
      }
    }

    return const ResumenEliminacionCompra(existe: true);
  }

  /// Eliminación física extraordinaria (Etapa 15) — Maestro-only. El
  /// único bloqueador real es historia posterior verificada por
  /// [obtenerResumenEliminacionFisica]; el estatus (`registrada`/
  /// `cancelada`) nunca bloquea por sí solo. Todo lo demás se limpia
  /// explícitamente, en una sola transacción y en el orden que exige
  /// cada FK `restrict`: primero la tabla puente
  /// `CompraPartidaMovimiento`, luego los `MovimientoInventario`
  /// generados (y sus comprobantes), luego las `ArticuloUnidad`
  /// generadas (serializados) con su bitácora propia, luego las
  /// `CompraPartida`, luego la Compra misma, y **hasta el final** su
  /// Egreso propio (con sus comprobantes — nunca bloquea, es parte del
  /// mismo agregado): `Compra.egresoId` es `restrict` hacia `Egreso`,
  /// así que el Egreso solo puede borrarse una vez que la fila de
  /// Compra que lo referencia ya no existe. Nunca se toca el
  /// `Pago`/otras Compras/movimientos ajenos.
  @override
  Future<EliminarCompraFisicamenteResultado> eliminarFisicamente({
    required String compraId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final compraInicial = await obtenerPorId(compraId);
    if (compraInicial == null) return EliminarCompraFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(compraId);
    if (resumen.bloqueado) {
      return EliminarCompraFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

    await _db.transaction(() async {
      await _eliminarCompraYArtefactosPropios(
        compraInicial: compraInicial,
        motivo: motivo,
        etiquetaMotivo: MotivoEliminacionFisicaCompra.values.where((m) => m.name == motivo).firstOrNull?.etiqueta ?? motivo,
        detalle: detalle,
        actorUsuarioId: actorUsuarioId,
      );
    });

    return EliminarCompraFisicamenteExitoso();
  }

  /// Núcleo compartido de la eliminación física: limpia todo lo que
  /// esta Compra generó DIRECTAMENTE (movimientos propios `entrada`,
  /// unidades, partidas, Egreso, adjuntos) y registra la auditoría.
  /// Asume que el llamador YA verificó que no hay ningún bloqueo real
  /// y que ya limpió cualquier cadena derivada (Asignación/descuentos)
  /// que hiciera falta — usado tanto por [eliminarFisicamente] como
  /// por [eliminarCadenaPrueba]. Debe llamarse siempre dentro de una
  /// transacción ya abierta por el llamador.
  Future<void> _eliminarCompraYArtefactosPropios({
    required CompraData compraInicial,
    required String motivo,
    required String etiquetaMotivo,
    String? detalle,
    String? actorUsuarioId,
    Map<String, Object?> snapshotExtra = const {},
  }) async {
    final compraId = compraInicial.id;
    final partidas = await listarPartidas(compraId);
    final movimientos = await listarMovimientosGenerados(compraId);
    final unidades = await listarUnidadesGeneradas(compraId);

    final compraAdjuntosQuery = _db.select(_db.attachment).join([
      innerJoin(_db.compraAttachment, _db.compraAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.compraAttachment.compraId.equals(compraId));
    final compraAdjuntos = await compraAdjuntosQuery.map((row) => row.readTable(_db.attachment)).get();

    EgresoData? egreso;
    List<AttachmentData> egresoAdjuntos = const [];
    if (compraInicial.egresoId != null) {
      egreso = await (_db.select(_db.egreso)..where((t) => t.id.equals(compraInicial.egresoId!))).getSingleOrNull();
      if (egreso != null) {
        final egresoAdjuntosQuery = _db.select(_db.attachment).join([
          innerJoin(_db.egresoAttachment, _db.egresoAttachment.attachmentId.equalsExp(_db.attachment.id)),
        ])
          ..where(_db.egresoAttachment.egresoId.equals(egreso.id));
        egresoAdjuntos = await egresoAdjuntosQuery.map((row) => row.readTable(_db.attachment)).get();
      }
    }

    // Etapa 3: filtrado SIEMPRE por `compraId`, nunca gateado por
    // `compraInicial.deudaId` VIGENTE — una Compra con historial
    // Cuenta↔TDC puede tener `MovimientoDeuda` de una tarjeta anterior
    // aunque su origen actual ya no sea esa tarjeta; el snapshot debe
    // preservarlos igual que el resto de la evidencia financiera.
    final movimientosDeuda = await (_db.select(_db.movimientoDeuda)..where((t) => t.compraId.equals(compraId))).get();

    final snapshot = <String, Object?>{
      'compra': compraInicial.toJson(),
      'partidas': [for (final p in partidas) p.toJson()],
      'movimientosGenerados': [for (final m in movimientos) m.toJson()],
      'unidadesGeneradas': [for (final u in unidades) u.toJson()],
      'egreso': egreso?.toJson(),
      'movimientosDeuda': [for (final m in movimientosDeuda) m.toJson()],
      'compraAdjuntos': [for (final a in compraAdjuntos) a.toJson()],
      'egresoAdjuntos': [for (final a in egresoAdjuntos) a.toJson()],
      ...snapshotExtra,
    };

    // 1. Puente Compra→Movimiento (restrict en ambas columnas).
    for (final partida in partidas) {
      await (_db.delete(_db.compraPartidaMovimiento)..where((t) => t.compraPartidaId.equals(partida.id))).go();
    }

    // 2. Comprobantes de cada movimiento (cascade al borrar el
    // movimiento, pero el `Attachment` en sí queda huérfano si no se
    // borra explícitamente).
    for (final movimiento in movimientos) {
      final adjuntosMovQuery = _db.select(_db.attachment).join([
        innerJoin(
          _db.movimientoInventarioAttachment,
          _db.movimientoInventarioAttachment.attachmentId.equalsExp(_db.attachment.id),
        ),
      ])
        ..where(_db.movimientoInventarioAttachment.movimientoInventarioId.equals(movimiento.id));
      final adjuntosMov = await adjuntosMovQuery.map((row) => row.readTable(_db.attachment)).get();
      for (final adjunto in adjuntosMov) {
        await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
      }
    }

    // 3. Movimientos generados por esta Compra.
    for (final movimiento in movimientos) {
      await (_db.delete(_db.movimientoInventario)..where((t) => t.id.equals(movimiento.id))).go();
    }

    // 4. Unidades serializadas generadas — su bitácora propia
    // (restrict) se limpia primero; `ArticuloUnidadTelefono`/
    // `EquipoTelefonicoCredencial` son `cascade`, se limpian solas.
    for (final unidad in unidades) {
      await (_db.delete(_db.articuloUnidadEvento)..where((t) => t.unidadId.equals(unidad.id))).go();
      await (_db.delete(_db.equipoTelefonicoEvento)..where((t) => t.unidadId.equals(unidad.id))).go();
      await (_db.delete(_db.articuloUnidad)..where((t) => t.id.equals(unidad.id))).go();
    }

    // 5. Renglones de la Compra — libera la única FK `restrict`
    // real que sigue apuntando a la Compra.
    for (final partida in partidas) {
      await (_db.delete(_db.compraPartida)..where((t) => t.id.equals(partida.id))).go();
    }

    await _db.into(_db.eliminacionFisicaEvento).insert(
          EliminacionFisicaEventoCompanion.insert(
            tipoEntidad: 'compra',
            entidadIdOriginal: compraId,
            fechaHora: DateTime.now(),
            motivo: etiquetaMotivo,
            motivoCodigo: Value(motivo),
            detalle: Value(detalle),
            snapshotJson: jsonEncode(snapshot),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );

    // 5.5. Etapa 19B — cargo(s) de tarjeta vinculados a esta Compra
    // (`MovimientoDeuda.compraId` es `restrict`): deben revertirse
    // ANTES de borrar la Compra, no después como el Egreso (`egresoId`
    // corre en la dirección contraria). El llamador ya verificó, vía
    // `obtenerResumenEliminacionFisica`/`obtenerResumenCadenaPrueba`,
    // que son el movimiento más reciente de esa tarjeta. Etapa 3: se
    // invoca SIEMPRE (nunca gateado por `compraInicial.deudaId`) —
    // ver el comentario equivalente en `obtenerResumenEliminacionFisica`.
    await _deudaRepository.eliminarCargoCompraFisicamente(compraId);

    // 6. La Compra en sí — `CompraEvento`/`CompraAttachment` son
    // `cascade`, se limpian solas; el `Attachment` propio (fila 8)
    // se borra después, sin depender de este `DELETE`.
    await (_db.delete(_db.compra)..where((t) => t.id.equals(compraId))).go();

    // 7. Egreso propio — parte del mismo agregado, nunca un
    // bloqueo. Debe ir DESPUÉS de borrar la Compra: `Compra.egresoId`
    // es `restrict` hacia `Egreso`, así que mientras la fila de
    // Compra exista, el motor rechaza el `DELETE` del Egreso.
    if (egreso != null) {
      for (final adjunto in egresoAdjuntos) {
        await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
      }
      await (_db.delete(_db.egreso)..where((t) => t.id.equals(egreso!.id))).go();
    }

    // 8. Comprobantes propios de la Compra.
    for (final adjunto in compraAdjuntos) {
      await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
    }
  }

  /// Recorre las `ArticuloUnidad` generadas por esta Compra y, para
  /// cada una, resuelve TODAS sus `Asignacion` (cualquier estatus —
  /// activa, devuelta, dañada, perdida) vía relación exacta
  /// `Asignacion.unidadId`, nunca por artículo/empleado/fecha. Cada
  /// unidad serializada tiene identidad propia: cualquier `Asignacion`
  /// sobre ella pertenece inequívocamente a esta Compra, sin ambigüedad
  /// posible (a diferencia de lo fungible, ver el doc comment de
  /// [eliminarCadenaPrueba]).
  Future<List<AsignacionData>> _asignacionesDeUnidadesGeneradas(String compraId) async {
    final unidades = await listarUnidadesGeneradas(compraId);
    if (unidades.isEmpty) return [];
    final unidadIds = unidades.map((u) => u.id).toSet();
    return (_db.select(_db.asignacion)..where((t) => t.unidadId.isIn(unidadIds))).get();
  }

  /// Tipos de `MovimientoInventario` que agregan existencia — la única
  /// forma en que un artículo por cantidad "nace" en el sistema.
  static const _tiposMovimientoEntrada = {'entrada', 'ajusteEntrada'};

  /// Tipos de `MovimientoInventario` de salida SIN una `Asignacion`
  /// detrás — una acción manual deliberada (conteo físico, merma,
  /// decomiso directo) que "Eliminar cadena de prueba" no sabe revertir
  /// (a diferencia de `salidaAsignacion`/`entradaDevolucion`/
  /// `salidaDano`/`salidaPerdida`, que siempre corresponden a una
  /// `Asignacion` que sí se puede desandar).
  static const _tiposMovimientoSalidaManual = {'baja', 'ajusteSalida'};

  /// Determina si la existencia de un artículo/variante POR CANTIDAD
  /// (sin número de serie) es atribuible con exactitud matemática a
  /// [compraId] — la pregunta que hizo Marlon: no "¿qué pieza física
  /// era?", sino "¿puedo demostrar que TODA la existencia de este
  /// artículo/variante, sin excepción, proviene de esta Compra?".
  ///
  /// Se demuestra (nunca se asume) verificando dos condiciones sobre el
  /// historial COMPLETO de `MovimientoInventario` de ese
  /// artículo/variante — nunca solo el de esta Compra:
  ///
  /// 1. **Origen único**: ningún `entrada`/`ajusteEntrada` ajeno existe
  ///    (otra Compra, o un ajuste de conteo). Si lo hay, el pool está
  ///    mezclado con existencia de otro origen — matemáticamente
  ///    imposible saber cuánta de una `Asignacion` posterior vino de
  ///    esta Compra y cuánta de la otra fuente.
  /// 2. **Sin salidas manuales ajenas**: ningún `baja`/`ajusteSalida`
  ///    suelto (sin `Asignacion` detrás) existe fuera de los propios de
  ///    esta Compra (su entrada, o la baja de reversa si ya se
  ///    canceló). Una baja/ajuste manual es una acción real que esta
  ///    operación no sabe desandar.
  ///
  /// Si ambas se cumplen, CUALQUIER `Asignacion` sobre ese
  /// artículo/variante (activa, devuelta, dañada, perdida — cualquier
  /// estatus) queda demostrada por eliminación: no hay otro origen
  /// posible, así que pertenece a esta Compra sin ambigüedad — el mismo
  /// nivel de certeza que ya tiene lo serializado vía `unidadId`, solo
  /// que aquí se prueba por reconciliación agregada en vez de por FK
  /// directa (los movimientos derivados de una Asignación fungible no
  /// cargan su propio id — ver el doc comment de `MovimientoInventario`).
  ///
  /// Devuelve el mensaje de bloqueo exacto si NO es atribuible, o
  /// `null` si sí lo es.
  Future<String?> _motivoBloqueoAtribucionFungible({
    required ArticuloData articulo,
    String? varianteId,
    required String compraId,
  }) async {
    final propios = (await listarMovimientosGenerados(compraId)).map((m) => m.id).toSet();

    final entradas = await (_db.select(_db.movimientoInventario)
          ..where(
            (t) => t.articuloId.equals(articulo.id) &
                (varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(varianteId)) &
                t.tipoMovimiento.isIn(_tiposMovimientoEntrada),
          ))
        .get();
    if (entradas.any((m) => !propios.contains(m.id))) {
      return 'El artículo ${articulo.nombre} tiene existencia registrada desde otro origen (otra Compra o un '
          'ajuste de entrada) — no se puede demostrar matemáticamente que toda la existencia proviene de esta '
          'Compra, así que no puede limpiarse como cadena de prueba.';
    }

    final salidasManuales = await (_db.select(_db.movimientoInventario)
          ..where(
            (t) => t.articuloId.equals(articulo.id) &
                (varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(varianteId)) &
                t.tipoMovimiento.isIn(_tiposMovimientoSalidaManual),
          ))
        .get();
    if (salidasManuales.any((m) => !propios.contains(m.id))) {
      return 'El artículo ${articulo.nombre} tiene una baja o un ajuste manual registrado que no pertenece a '
          'esta Compra — su atribución dejaría de ser exacta, así que no puede limpiarse como cadena de prueba.';
    }

    return null;
  }

  /// Todas las `Asignacion` de un artículo/variante POR CANTIDAD (sin
  /// `unidadId`) — seguro llamar solo DESPUÉS de que
  /// [_motivoBloqueoAtribucionFungible] confirmó que el alcance
  /// completo es atribuible a una sola Compra; en ese caso, cualquier
  /// `Asignacion` en este alcance pertenece a ella sin ambigüedad.
  Future<List<AsignacionData>> _asignacionesFungiblesDeCompra({required String articuloId, String? varianteId}) {
    return (_db.select(_db.asignacion)
          ..where(
            (t) =>
                t.articuloId.equals(articuloId) &
                (varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(varianteId)) &
                t.unidadId.isNull(),
          ))
        .get();
  }

  @override
  Future<ResumenCadenaPruebaCompra> obtenerResumenCadenaPrueba(String compraId) async {
    final compra = await obtenerPorId(compraId);
    if (compra == null) return const ResumenCadenaPruebaCompra(existe: false);

    // Etapa 19B — mismo criterio exacto que `obtenerResumenEliminacionFisica`:
    // el cargo a la tarjeta solo es seguro de revertir si es el
    // movimiento más reciente de esa tarjeta. Etapa 3: consultado
    // SIEMPRE, sin gatearlo por `compra.deudaId` VIGENTE — mismo
    // motivo que en `obtenerResumenEliminacionFisica`.
    final bloqueoTarjeta = await _deudaRepository.detalleBloqueoEliminacionCargoCompra(compraId);
    if (bloqueoTarjeta != null) {
      return ResumenCadenaPruebaCompra(existe: true, folioCompra: compra.folioCompra, detalleBloqueo: bloqueoTarjeta);
    }

    final partidas = await listarPartidas(compraId);
    final entradasInventario = partidas.where((p) => p.destino == DestinoCompraPartida.inventario.name).length;

    String? folioEgreso;
    int? montoEgreso;
    if (compra.egresoId != null) {
      final egreso = await (_db.select(_db.egreso)..where((t) => t.id.equals(compra.egresoId!))).getSingleOrNull();
      folioEgreso = egreso?.folioEgreso;
      montoEgreso = egreso?.monto;
    }

    // Serializados: cada Asignación (cualquier estatus) sobre una
    // unidad generada por esta Compra es atribuible con exactitud —
    // se listaría para eliminar, salvo que algo la haga irreversible.
    final asignacionesUnidades = await _asignacionesDeUnidadesGeneradas(compraId);
    final descripcionesAsignaciones = <String>[];
    var movimientosDerivados = 0;
    var descuentosPendientes = 0;
    var totalDescuentosPendientes = 0;

    for (final asignacion in asignacionesUnidades) {
      final unidad = await (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(asignacion.unidadId!))).getSingleOrNull();
      final articulo = unidad == null ? null : await _articuloRepository.obtenerPorId(unidad.articuloId);
      descripcionesAsignaciones.add('${articulo?.nombre ?? '—'} — ${unidad?.codigo ?? asignacion.unidadId}');

      // Punto irreversible 1: la unidad quedó vinculada a una línea
      // telefónica real — nunca se relaja, ni en cadena de prueba.
      final lineasEquipo =
          await (_db.select(_db.lineaTelefonicaEquipo)..where((t) => t.unidadId.equals(asignacion.unidadId!))).get();
      if (lineasEquipo.isNotEmpty) {
        return ResumenCadenaPruebaCompra(
          existe: true,
          folioCompra: compra.folioCompra,
          detalleBloqueo:
              'La unidad ${unidad?.codigo ?? asignacion.unidadId} está vinculada a una línea telefónica real — '
              'no puede limpiarse ni como cadena de prueba.',
        );
      }

      if (asignacion.estatus != EstatusAsignacion.activa.name) movimientosDerivados++;

      final descuento = await (_db.select(_db.descuentoInventario)..where((t) => t.asignacionId.equals(asignacion.id))).getSingleOrNull();
      if (descuento != null) {
        // Punto irreversible 2: el descuento ya está `aplicado` — sin
        // importar si la Nómina que lo aplicó sigue en Borrador o ya
        // se cerró/pagó. Un descuento `aplicado` es un cruce real
        // hacia otro dominio (Nómina); esta operación nunca lo
        // desenreda por su cuenta — primero hay que resolver/eliminar
        // esa Nómina (`eliminarNominaFisicamenteAutorizadoProvider`,
        // que sí revierte el descuento a `pendiente`).
        if (descuento.estatus == EstatusDescuentoInventario.aplicado.name) {
          return ResumenCadenaPruebaCompra(
            existe: true,
            folioCompra: compra.folioCompra,
            detalleBloqueo:
                'El descuento por daño/pérdida de ${articulo?.nombre ?? 'un artículo'} ya está aplicado en una '
                'Nómina — elimina o corrige esa Nómina primero (ver "Eliminar físicamente" en Nómina).',
          );
        }
        if (descuento.estatus == EstatusDescuentoInventario.pendiente.name) {
          descuentosPendientes++;
          totalDescuentosPendientes += descuento.importe;
        }
      }
    }

    // Por cantidad (fungible): a diferencia de `eliminarFisicamente`
    // (que bloquea ante CUALQUIER Asignación, política conservadora
    // correcta para producción), aquí sí se demuestra matemáticamente
    // si la existencia completa del artículo/variante es atribuible a
    // esta Compra — ver el doc comment de `_motivoBloqueoAtribucionFungible`.
    for (final partida in partidas) {
      if (partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) continue;
      final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
      if (articulo == null || articulo.manejaSerie) continue;

      final motivoBloqueo = await _motivoBloqueoAtribucionFungible(
        articulo: articulo,
        varianteId: partida.varianteId,
        compraId: compraId,
      );
      if (motivoBloqueo != null) {
        return ResumenCadenaPruebaCompra(existe: true, folioCompra: compra.folioCompra, detalleBloqueo: motivoBloqueo);
      }

      final asignacionesFungibles = await _asignacionesFungiblesDeCompra(articuloId: articulo.id, varianteId: partida.varianteId);
      for (final asignacion in asignacionesFungibles) {
        descripcionesAsignaciones.add('${articulo.nombre} — cantidad ${asignacion.cantidad}');
        if (asignacion.estatus != EstatusAsignacion.activa.name) movimientosDerivados++;

        final descuento =
            await (_db.select(_db.descuentoInventario)..where((t) => t.asignacionId.equals(asignacion.id))).getSingleOrNull();
        if (descuento != null) {
          // Mismo punto irreversible que en lo serializado — nunca se
          // relaja, sin importar el estatus de la Nómina.
          if (descuento.estatus == EstatusDescuentoInventario.aplicado.name) {
            return ResumenCadenaPruebaCompra(
              existe: true,
              folioCompra: compra.folioCompra,
              detalleBloqueo:
                  'El descuento por daño/pérdida de ${articulo.nombre} ya está aplicado en una Nómina — elimina '
                  'o corrige esa Nómina primero (ver "Eliminar físicamente" en Nómina).',
            );
          }
          if (descuento.estatus == EstatusDescuentoInventario.pendiente.name) {
            descuentosPendientes++;
            totalDescuentosPendientes += descuento.importe;
          }
        }
      }
    }

    return ResumenCadenaPruebaCompra(
      existe: true,
      folioCompra: compra.folioCompra,
      folioEgreso: folioEgreso,
      montoEgreso: montoEgreso,
      entradasInventario: entradasInventario,
      asignaciones: descripcionesAsignaciones,
      movimientosDerivados: movimientosDerivados,
      descuentosPendientes: descuentosPendientes,
      totalDescuentosPendientes: totalDescuentosPendientes,
    );
  }

  /// "Eliminar cadena de prueba" (Etapa 15, limpieza segura de datos de
  /// prueba, Maestro-only) — a diferencia de [eliminarFisicamente]
  /// (que bloquea ante CUALQUIER `Asignacion`/movimiento posterior),
  /// esta acción SÍ elimina la cadena derivada completa, pero
  /// EXCLUSIVAMENTE por relación de IDs exacta y solo cuando nada
  /// cruzó un punto irreversible real:
  ///
  /// 1. **Serializados**: cada `Asignacion` sobre una `ArticuloUnidad`
  ///    generada por esta Compra (identidad propia, vínculo exacto vía
  ///    `unidadId`) se elimina junto con sus movimientos derivados
  ///    (`salidaAsignacion`/`entradaDevolucion`/`salidaDano`/
  ///    `salidaPerdida`, todos referenciados por el mismo `unidadId`) y
  ///    su `DescuentoInventario` si sigue `pendiente`/`cancelado`.
  /// 2. **Por cantidad (fungible)**: sin identidad propia, pero SÍ
  ///    demostrable por reconciliación agregada — ver el doc comment de
  ///    `_motivoBloqueoAtribucionFungible`. Solo procede si esta Compra
  ///    es el ÚNICO origen de existencia de ese artículo/variante (sin
  ///    otra Compra ni ajuste de entrada) y no existe ninguna baja/
  ///    ajuste de salida manual (sin `Asignacion` detrás) — en ese caso
  ///    CUALQUIER `Asignacion` sobre ese artículo/variante queda
  ///    demostrada por eliminación y se borra igual que lo serializado
  ///    (por reconciliación agregada, ya que estos movimientos no
  ///    cargan su propio id de Asignación). Si cualquiera de las dos
  ///    condiciones falla, bloquea exactamente igual que
  ///    `eliminarFisicamente` — nunca se relaja por debajo de eso.
  /// 3. **Puntos irreversibles que bloquean TODO** (nada se elimina,
  ///    ni siquiera lo seguro): una unidad vinculada a una línea
  ///    telefónica real, o un `DescuentoInventario` ya `aplicado` a
  ///    cualquier Nómina (Borrador, Cerrada o Pagada).
  ///
  /// Todo en una sola transacción — si algo falla, no queda ninguna
  /// eliminación parcial.
  @override
  Future<EliminarCadenaPruebaCompraResultado> eliminarCadenaPrueba({
    required String compraId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final compraInicial = await obtenerPorId(compraId);
    if (compraInicial == null) return EliminarCadenaPruebaCompraNoExiste();

    final resumen = await obtenerResumenCadenaPrueba(compraId);
    if (resumen.bloqueado) {
      return EliminarCadenaPruebaCompraTieneDependencias(resumen.detalleBloqueo!);
    }

    final asignaciones = await _asignacionesDeUnidadesGeneradas(compraId);
    final partidas = await listarPartidas(compraId);

    await _db.transaction(() async {
      final snapshotAsignaciones = <Map<String, Object?>>[];

      // Por cantidad (fungible) — ya se demostró en `obtenerResumenCadenaPrueba`
      // que cada uno de estos alcances es de origen único; se borra por
      // reconciliación agregada, no por FK directa (ver el doc comment
      // de `_motivoBloqueoAtribucionFungible`).
      for (final partida in partidas) {
        if (partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) continue;
        final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
        if (articulo == null || articulo.manejaSerie) continue;

        final varianteId = partida.varianteId;
        final asignacionesFungibles = await _asignacionesFungiblesDeCompra(articuloId: articulo.id, varianteId: varianteId);
        if (asignacionesFungibles.isEmpty) continue;

        for (final asignacion in asignacionesFungibles) {
          final descuento =
              await (_db.select(_db.descuentoInventario)..where((t) => t.asignacionId.equals(asignacion.id))).getSingleOrNull();
          if (descuento != null) {
            await (_db.delete(_db.descuentoInventario)..where((t) => t.id.equals(descuento.id))).go();
          }

          final adjuntosQuery = _db.select(_db.attachment).join([
            innerJoin(_db.asignacionAttachment, _db.asignacionAttachment.attachmentId.equalsExp(_db.attachment.id)),
          ])
            ..where(_db.asignacionAttachment.asignacionId.equals(asignacion.id));
          final adjuntos = await adjuntosQuery.map((row) => row.readTable(_db.attachment)).get();
          for (final adjunto in adjuntos) {
            await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
          }

          snapshotAsignaciones.add({'asignacion': asignacion.toJson(), 'descuento': descuento?.toJson()});
        }

        // Movimientos derivados (salidaAsignacion/entradaDevolucion/
        // salidaDano/salidaPerdida) de este artículo/variante — sin id
        // propio de Asignación, se eliminan por el mismo alcance ya
        // probado como exclusivo de esta cadena, nunca por artículo en
        // general.
        await (_db.delete(_db.movimientoInventario)
              ..where(
                (t) =>
                    t.articuloId.equals(articulo.id) &
                    (varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(varianteId)) &
                    t.tipoMovimiento.isIn(const ['salidaAsignacion', 'entradaDevolucion', 'salidaDano', 'salidaPerdida']),
              ))
            .go();

        for (final asignacion in asignacionesFungibles) {
          await (_db.delete(_db.asignacion)..where((t) => t.id.equals(asignacion.id))).go();
        }
      }

      for (final asignacion in asignaciones) {
        final unidadId = asignacion.unidadId!;

        // Descuento derivado (si sigue pendiente/cancelado — un
        // aplicado ya habría bloqueado todo arriba).
        final descuento = await (_db.select(_db.descuentoInventario)..where((t) => t.asignacionId.equals(asignacion.id))).getSingleOrNull();
        if (descuento != null) {
          await (_db.delete(_db.descuentoInventario)..where((t) => t.id.equals(descuento.id))).go();
        }

        // Adjuntos del resguardo de esta Asignación (AsignacionAttachment
        // es `cascade` sobre Asignacion, pero el Attachment en sí queda
        // huérfano si no se borra explícitamente — mismo criterio que
        // los comprobantes de MovimientoInventario en `eliminarFisicamente`).
        final adjuntosAsignacionQuery = _db.select(_db.attachment).join([
          innerJoin(_db.asignacionAttachment, _db.asignacionAttachment.attachmentId.equalsExp(_db.attachment.id)),
        ])
          ..where(_db.asignacionAttachment.asignacionId.equals(asignacion.id));
        final adjuntosAsignacion = await adjuntosAsignacionQuery.map((row) => row.readTable(_db.attachment)).get();

        // Movimientos derivados de ESTA unidad que NO son la `entrada`
        // original de la Compra (salidaAsignacion/entradaDevolucion/
        // salidaDano/salidaPerdida) — relación exacta por `unidadId`,
        // nunca por artículo.
        final movimientosUnidad = await _inventarioRepository.listarMovimientos(unidadId: unidadId);
        final movimientosDerivados = movimientosUnidad.where((m) => m.tipoMovimiento != TipoMovimientoInventario.entrada.name);

        snapshotAsignaciones.add({
          'asignacion': asignacion.toJson(),
          'descuento': descuento?.toJson(),
          'movimientosDerivados': [for (final m in movimientosDerivados) m.toJson()],
        });

        for (final adjunto in adjuntosAsignacion) {
          await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
        }
        for (final movimiento in movimientosDerivados) {
          await (_db.delete(_db.movimientoInventario)..where((t) => t.id.equals(movimiento.id))).go();
        }
        await (_db.delete(_db.asignacion)..where((t) => t.id.equals(asignacion.id))).go();
      }

      await _eliminarCompraYArtefactosPropios(
        compraInicial: compraInicial,
        motivo: motivo,
        etiquetaMotivo: MotivoCadenaPruebaCompra.values.where((m) => m.name == motivo).firstOrNull?.etiqueta ?? motivo,
        detalle: detalle,
        actorUsuarioId: actorUsuarioId,
        snapshotExtra: {'asignacionesEliminadas': snapshotAsignaciones},
      );
    });

    return EliminarCadenaPruebaCompraExitoso();
  }
}
