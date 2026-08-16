import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart' show TipoMovimientoInventario;

import '../../domain/repositories/compra_repository.dart';
import '../../domain/usecases/correccion_partida_compra.dart';
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
  CompraRepositoryImpl(this._db, this._inventarioRepository, this._articuloRepository, this._egresoRepository);

  final AppDatabase _db;
  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;
  final EgresoRepository _egresoRepository;
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
  }) async {
    final query = _db.select(_db.compra);
    if (desde != null) query.where((t) => t.fecha.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where((t) => t.fecha.isSmallerOrEqualValue(hasta));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
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
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final montoTotal = partidas.fold<int>(0, (s, p) => s + p.cantidad * p.costoUnitario);

      final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
      final egreso = await _egresoRepository.crear(
        folioEgreso: folioEgreso,
        monto: montoTotal,
        fecha: fecha,
        formaPago: formaPago,
        beneficiario: proveedor,
        concepto: proveedor == null || proveedor.trim().isEmpty ? 'Compra $folioCompra' : 'Compra $folioCompra · $proveedor',
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );

      final compra = await _db.into(_db.compra).insertReturning(
            CompraCompanion.insert(
              folioCompra: folioCompra,
              fecha: fecha,
              proveedor: Value(proveedor),
              formaPago: formaPago,
              formaPagoOtroDescripcion: Value(formaPagoOtroDescripcion),
              observaciones: Value(observaciones),
              egresoId: Value(egreso.id),
            ),
          );

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

  /// Misma regla conservadora ya usada por [obtenerResumenEliminacionFisica]
  /// para partidas por cantidad (sin unidad individual): bloquea si el
  /// artículo/variante tiene cualquier `Asignacion` registrada.
  Future<String?> _detalleBloqueoArticuloVariante(String articuloId, String? varianteId) async {
    final asignaciones = await (_db.select(_db.asignacion)
          ..where(
            (t) => t.articuloId.equals(articuloId) &
                (varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(varianteId)),
          ))
        .get();
    if (asignaciones.isNotEmpty) {
      return 'El artículo de esta partida tiene asignaciones registradas — no puede reducirse/corregirse esta '
          'cantidad de forma segura.';
    }
    return null;
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
              final bloqueo = await _detalleBloqueoArticuloVariante(partida.articuloId!, partida.varianteId);
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
            final bloqueo = await _detalleBloqueoArticuloVariante(partida.articuloId!, partida.varianteId);
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
            final bloqueo = await _detalleBloqueoArticuloVariante(partida.articuloId!, partida.varianteId);
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
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();
      final totalAnterior = await calcularTotal(compraId);

      if (cambiosPartidas.isNotEmpty) {
        final bloqueo = await _detalleBloqueoCambios(cambiosPartidas);
        if (bloqueo != null) throw StateError(bloqueo);
      }

      await (_db.update(_db.compra)..where((t) => t.id.equals(compraId))).write(
        CompraCompanion(
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          proveedor: proveedor == null ? const Value.absent() : Value(proveedor),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
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
      if (totalNuevo != totalAnterior && anterior.egresoId != null) {
        await _egresoRepository.corregirMonto(
          egresoId: anterior.egresoId!,
          nuevoMonto: totalNuevo,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      await _registrarEventoInterno(
        compraId: compraId,
        tipoEvento: TipoEventoCompra.corregida,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'proveedorAnterior': anterior.proveedor,
          'formaPagoAnterior': anterior.formaPago,
          if (detallesPartidas.isNotEmpty) 'partidas': detallesPartidas,
          if (totalNuevo != totalAnterior) 'totalAnterior': totalAnterior,
          if (totalNuevo != totalAnterior) 'totalNuevo': totalNuevo,
        },
      );

      return (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();
    });
  }

  @override
  Future<CompraData> cancelar({required String compraId, required String motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final compra = await (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();
      final movimientos = await listarMovimientosGenerados(compraId);

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
            observaciones: 'Cancelación de Compra ${compra.folioCompra}: $motivo',
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
            observaciones: 'Cancelación de Compra ${compra.folioCompra}: $motivo',
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
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (compra.egresoId != null) {
        await _egresoRepository.cancelar(egresoId: compra.egresoId!, motivo: motivo, actorUsuarioId: actorUsuarioId);
      }

      await _registrarEventoInterno(
        compraId: compraId,
        tipoEvento: TipoEventoCompra.cancelada,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
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
    // forma de probar que el remanente de ESTA Compra específica no
    // fue el asignado — se bloquea de forma conservadora si el
    // artículo/variante tiene cualquier `Asignacion` registrada.
    final partidas = await listarPartidas(compraId);
    for (final partida in partidas) {
      if (partida.destino != DestinoCompraPartida.inventario.name || partida.articuloId == null) continue;
      final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
      if (articulo == null || articulo.manejaSerie) continue;

      final asignaciones = await (_db.select(_db.asignacion)
            ..where(
              (t) => t.articuloId.equals(articulo.id) &
                  (partida.varianteId == null ? t.varianteId.isNull() : t.varianteId.equals(partida.varianteId!)),
            ))
          .get();
      if (asignaciones.isNotEmpty) {
        return ResumenEliminacionCompra(
          existe: true,
          detalleBloqueo:
              'El artículo ${articulo.nombre} recibido por esta Compra tiene asignaciones registradas — no puede '
              'eliminarse.',
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
    String? actorUsuarioId,
  }) async {
    final compraInicial = await obtenerPorId(compraId);
    if (compraInicial == null) return EliminarCompraFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(compraId);
    if (resumen.bloqueado) {
      return EliminarCompraFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

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

    await _db.transaction(() async {
      final snapshot = <String, Object?>{
        'compra': compraInicial.toJson(),
        'partidas': [for (final p in partidas) p.toJson()],
        'movimientosGenerados': [for (final m in movimientos) m.toJson()],
        'unidadesGeneradas': [for (final u in unidades) u.toJson()],
        'egreso': egreso?.toJson(),
        'compraAdjuntos': [for (final a in compraAdjuntos) a.toJson()],
        'egresoAdjuntos': [for (final a in egresoAdjuntos) a.toJson()],
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
              motivo: motivo,
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

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
    });

    return EliminarCompraFisicamenteExitoso();
  }
}
