import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../../domain/repositories/compra_repository.dart';
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

  @override
  Future<CompraData> corregir({
    required String compraId,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.compra)..where((t) => t.id.equals(compraId))).getSingle();

      await (_db.update(_db.compra)..where((t) => t.id.equals(compraId))).write(
        CompraCompanion(
          proveedor: proveedor == null ? const Value.absent() : Value(proveedor),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
          formaPagoOtroDescripcion: formaPagoOtroDescripcion == null ? const Value.absent() : Value(formaPagoOtroDescripcion),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(
        compraId: compraId,
        tipoEvento: TipoEventoCompra.corregida,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'proveedorAnterior': anterior.proveedor,
          'formaPagoAnterior': anterior.formaPago,
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
        if (movimiento.unidadId != null) {
          await _inventarioRepository.registrarBajaUnidad(
            unidadId: movimiento.unidadId!,
            observaciones: 'Cancelación de Compra ${compra.folioCompra}: $motivo',
            actorUsuarioId: actorUsuarioId,
          );
        } else {
          await _inventarioRepository.registrarBaja(
            articuloId: movimiento.articuloId,
            varianteId: movimiento.varianteId,
            cantidad: movimiento.cantidad,
            observaciones: 'Cancelación de Compra ${compra.folioCompra}: $motivo',
            actorUsuarioId: actorUsuarioId,
          );
        }
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
}
