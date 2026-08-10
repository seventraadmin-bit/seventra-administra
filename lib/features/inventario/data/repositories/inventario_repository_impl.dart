import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/inventario_repository.dart';
import '../../domain/usecases/existencia_articulo.dart';
import '../tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../tables/movimiento_inventario_table.dart' show TipoMovimientoInventario;

class InventarioRepositoryImpl implements InventarioRepository {
  InventarioRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ArticuloUnidadData?> obtenerUnidadPorId(String id) {
    return (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<ArticuloUnidadTelefonoData?> obtenerTelefono(String unidadId) {
    return (_db.select(_db.articuloUnidadTelefono)..where((t) => t.unidadId.equals(unidadId))).getSingleOrNull();
  }

  @override
  Future<List<ArticuloUnidadData>> listarUnidades(String articuloId, {String? estatus}) {
    final query = _db.select(_db.articuloUnidad)..where((t) => t.articuloId.equals(articuloId));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    query.orderBy([(t) => OrderingTerm.asc(t.codigo)]);
    return query.get();
  }

  @override
  Future<List<MovimientoInventarioData>> listarMovimientos({String? articuloId, String? varianteId, String? unidadId}) {
    final query = _db.select(_db.movimientoInventario);
    if (articuloId != null) query.where((t) => t.articuloId.equals(articuloId));
    if (varianteId != null) query.where((t) => t.varianteId.equals(varianteId));
    if (unidadId != null) query.where((t) => t.unidadId.equals(unidadId));
    query.orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    return query.get();
  }

  Future<MovimientoInventarioData> _insertarMovimiento({
    required String articuloId,
    String? varianteId,
    String? unidadId,
    required int cantidad,
    required TipoMovimientoInventario tipo,
    required DateTime fecha,
    int? costoUnitario,
    String? observaciones,
    String? actor,
  }) {
    return _db.into(_db.movimientoInventario).insertReturning(
          MovimientoInventarioCompanion.insert(
            articuloId: articuloId,
            varianteId: Value(varianteId),
            unidadId: Value(unidadId),
            cantidad: cantidad,
            tipoMovimiento: tipo.name,
            fecha: fecha,
            costoUnitario: Value(costoUnitario),
            observaciones: Value(observaciones),
            actor: Value(actor),
          ),
        );
  }

  @override
  Future<MovimientoInventarioData> registrarEntrada({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() => _insertarMovimiento(
          articuloId: articuloId,
          varianteId: varianteId,
          cantidad: cantidad,
          tipo: TipoMovimientoInventario.entrada,
          fecha: fecha,
          costoUnitario: costoUnitario,
          observaciones: observaciones,
          actor: actor,
        ));
  }

  @override
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
  }) {
    return _db.transaction(() async {
      final unidad = await _db.into(_db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: codigo,
              articuloId: articuloId,
              numeroSerie: numeroSerie,
              marca: Value(marca),
              modelo: Value(modelo),
            ),
          );

      if ((imei != null && imei.isNotEmpty) || (numeroTelefonico != null && numeroTelefonico.isNotEmpty)) {
        await _db.into(_db.articuloUnidadTelefono).insert(
              ArticuloUnidadTelefonoCompanion.insert(
                unidadId: unidad.id,
                imei: Value(imei),
                numeroTelefonico: Value(numeroTelefonico),
              ),
            );
      }

      await _insertarMovimiento(
        articuloId: articuloId,
        unidadId: unidad.id,
        cantidad: 1,
        tipo: TipoMovimientoInventario.entrada,
        fecha: fecha,
        costoUnitario: costoUnitario,
        observaciones: observaciones,
        actor: actor,
      );

      return unidad;
    });
  }

  @override
  Future<MovimientoInventarioData> registrarBaja({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required String observaciones,
    String? actor,
  }) {
    return _db.transaction(() => _insertarMovimiento(
          articuloId: articuloId,
          varianteId: varianteId,
          cantidad: cantidad,
          tipo: TipoMovimientoInventario.baja,
          fecha: DateTime.now(),
          observaciones: observaciones,
          actor: actor,
        ));
  }

  @override
  Future<ArticuloUnidadData> registrarBajaUnidad({
    required String unidadId,
    required String observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final unidad = await (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle();

      await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).write(
        ArticuloUnidadCompanion(
          estatus: Value(EstatusArticuloUnidad.baja.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _insertarMovimiento(
        articuloId: unidad.articuloId,
        unidadId: unidadId,
        cantidad: 1,
        tipo: TipoMovimientoInventario.baja,
        fecha: DateTime.now(),
        observaciones: observaciones,
        actor: actor,
      );

      return (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle();
    });
  }

  @override
  Future<MovimientoInventarioData> registrarAjuste({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required bool esEntrada,
    required String observaciones,
    String? actor,
  }) {
    return _db.transaction(() => _insertarMovimiento(
          articuloId: articuloId,
          varianteId: varianteId,
          cantidad: cantidad,
          tipo: esEntrada ? TipoMovimientoInventario.ajusteEntrada : TipoMovimientoInventario.ajusteSalida,
          fecha: DateTime.now(),
          observaciones: observaciones,
          actor: actor,
        ));
  }

  @override
  Future<ExistenciaArticulo> calcularExistencia({required String articuloId, String? varianteId}) async {
    final query = _db.select(_db.movimientoInventario)..where((t) => t.articuloId.equals(articuloId));
    if (varianteId == null) {
      query.where((t) => t.varianteId.isNull());
    } else {
      query.where((t) => t.varianteId.equals(varianteId));
    }
    final movimientos = await query.get();

    var disponible = 0;
    var asignado = 0;
    var danado = 0;
    var perdido = 0;
    for (final m in movimientos) {
      final tipo = TipoMovimientoInventario.values.byName(m.tipoMovimiento);
      switch (tipo) {
        case TipoMovimientoInventario.entrada:
        case TipoMovimientoInventario.ajusteEntrada:
          disponible += m.cantidad;
        case TipoMovimientoInventario.baja:
        case TipoMovimientoInventario.ajusteSalida:
          disponible -= m.cantidad;
        case TipoMovimientoInventario.salidaAsignacion:
          disponible -= m.cantidad;
          asignado += m.cantidad;
        case TipoMovimientoInventario.entradaDevolucion:
          asignado -= m.cantidad;
          disponible += m.cantidad;
        case TipoMovimientoInventario.salidaDano:
          asignado -= m.cantidad;
          danado += m.cantidad;
        case TipoMovimientoInventario.salidaPerdida:
          asignado -= m.cantidad;
          perdido += m.cantidad;
      }
    }

    return ExistenciaArticulo(disponible: disponible, asignado: asignado, danado: danado, perdido: perdido);
  }

  @override
  Future<ExistenciaArticulo> calcularExistenciaUnidades(String articuloId) async {
    final unidades = await (_db.select(_db.articuloUnidad)..where((t) => t.articuloId.equals(articuloId))).get();

    var disponible = 0;
    var asignado = 0;
    var danado = 0;
    var perdido = 0;
    for (final u in unidades) {
      switch (EstatusArticuloUnidad.values.byName(u.estatus)) {
        case EstatusArticuloUnidad.disponible:
          disponible++;
        case EstatusArticuloUnidad.asignado:
          asignado++;
        case EstatusArticuloUnidad.danado:
          danado++;
        case EstatusArticuloUnidad.perdido:
          perdido++;
        case EstatusArticuloUnidad.baja:
          break;
      }
    }

    return ExistenciaArticulo(disponible: disponible, asignado: asignado, danado: danado, perdido: perdido);
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String movimientoInventarioId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              categoria: const Value('comprobante'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.movimientoInventarioAttachment).insert(
            MovimientoInventarioAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              movimientoInventarioId: movimientoInventarioId,
            ),
          );
      return adjunto;
    });
  }
}
