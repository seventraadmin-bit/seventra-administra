import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/asignacion_repository.dart';
import '../tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../tables/asignacion_table.dart' show EstatusAsignacion, MotivoCierreAsignacion;
import '../tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import '../tables/movimiento_inventario_table.dart' show TipoMovimientoInventario;

class AsignacionRepositoryImpl implements AsignacionRepository {
  AsignacionRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<AsignacionData?> obtenerPorId(String id) {
    return (_db.select(_db.asignacion)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<AsignacionData>> listarActivasPorEmpleado(String empleadoId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.empleadoId.equals(empleadoId) & t.estatus.equals(EstatusAsignacion.activa.name))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarActivasPorServicio(String servicioId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.servicioId.equals(servicioId) & t.estatus.equals(EstatusAsignacion.activa.name))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarHistorialPorEmpleado(String empleadoId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.empleadoId.equals(empleadoId))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarHistorialPorServicio(String servicioId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.servicioId.equals(servicioId))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarPorUnidad(String unidadId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.unidadId.equals(unidadId))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<AsignacionData?> obtenerActivaPorUnidad(String unidadId) {
    return (_db.select(_db.asignacion)..where((t) => t.unidadId.equals(unidadId) & t.estatus.equals('activa')))
        .getSingleOrNull();
  }

  @override
  Future<DescuentoInventarioData?> obtenerDescuentoPorId(String id) {
    return (_db.select(_db.descuentoInventario)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<DescuentoInventarioData?> obtenerDescuentoPorAsignacion(String asignacionId) {
    return (_db.select(_db.descuentoInventario)..where((t) => t.asignacionId.equals(asignacionId)))
        .getSingleOrNull();
  }

  @override
  Future<List<DescuentoInventarioData>> listarDescuentosPendientesPorEmpleado(String empleadoId) {
    final query = _db.select(_db.descuentoInventario)
      ..where((t) => t.empleadoId.equals(empleadoId) & t.estatus.equals(EstatusDescuentoInventario.pendiente.name))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarTodasActivas() {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.estatus.equals(EstatusAsignacion.activa.name))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarDanadasPerdidas() {
    final query = _db.select(_db.asignacion)
      ..where(
        (t) =>
            t.estatus.equals(EstatusAsignacion.danada.name) | t.estatus.equals(EstatusAsignacion.perdida.name),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.fechaCierre)]);
    return query.get();
  }

  @override
  Future<List<DescuentoInventarioData>> listarTodosDescuentosPendientes() {
    final query = _db.select(_db.descuentoInventario)
      ..where((t) => t.estatus.equals(EstatusDescuentoInventario.pendiente.name))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<AsignacionData?> obtenerAsignacionReemplazada(String asignacionId) {
    return (_db.select(_db.asignacion)..where((t) => t.asignacionReemplazoId.equals(asignacionId))).getSingleOrNull();
  }

  Future<MovimientoInventarioData> _insertarMovimiento({
    required String articuloId,
    String? varianteId,
    String? unidadId,
    required int cantidad,
    required TipoMovimientoInventario tipo,
    required DateTime fecha,
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
            observaciones: Value(observaciones),
            actor: Value(actor),
          ),
        );
  }

  Future<AsignacionData> _crear({
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
  }) async {
    final asignacion = await _db.into(_db.asignacion).insertReturning(
          AsignacionCompanion.insert(
            articuloId: articuloId,
            varianteId: Value(varianteId),
            unidadId: Value(unidadId),
            cantidad: cantidad,
            empleadoId: Value(empleadoId),
            servicioId: Value(servicioId),
            fechaEntrega: fechaEntrega,
            condicionEntrega: Value(condicionEntrega),
            observaciones: Value(observaciones),
          ),
        );

    await _insertarMovimiento(
      articuloId: articuloId,
      varianteId: varianteId,
      unidadId: unidadId,
      cantidad: cantidad,
      tipo: TipoMovimientoInventario.salidaAsignacion,
      fecha: fechaEntrega,
      actor: actor,
    );

    if (unidadId != null) {
      await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).write(
        ArticuloUnidadCompanion(
          estatus: Value(EstatusArticuloUnidad.asignado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    return asignacion;
  }

  @override
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
  }) {
    return _db.transaction(() => _crear(
          articuloId: articuloId,
          varianteId: varianteId,
          unidadId: unidadId,
          cantidad: cantidad,
          empleadoId: empleadoId,
          servicioId: servicioId,
          fechaEntrega: fechaEntrega,
          condicionEntrega: condicionEntrega,
          observaciones: observaciones,
          actor: actor,
        ));
  }

  Future<AsignacionData> _cerrar({
    required String asignacionId,
    required String motivo,
    required DateTime fechaCierre,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    String? actor,
  }) async {
    final asignacion = await (_db.select(_db.asignacion)..where((t) => t.id.equals(asignacionId))).getSingle();

    final motivoEnum = MotivoCierreAsignacion.values.byName(motivo);
    final estatusFinal = switch (motivoEnum) {
      MotivoCierreAsignacion.dano => EstatusAsignacion.danada,
      MotivoCierreAsignacion.perdida => EstatusAsignacion.perdida,
      _ => EstatusAsignacion.devuelta,
    };

    await (_db.update(_db.asignacion)..where((t) => t.id.equals(asignacionId))).write(
      AsignacionCompanion(
        estatus: Value(estatusFinal.name),
        fechaCierre: Value(fechaCierre),
        motivoCierre: Value(motivo),
        observacionesCierre: Value(observacionesCierre),
        atribuibleAlEmpleado: Value(atribuibleAlEmpleado),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final tipoMovimiento = switch (estatusFinal) {
      EstatusAsignacion.danada => TipoMovimientoInventario.salidaDano,
      EstatusAsignacion.perdida => TipoMovimientoInventario.salidaPerdida,
      _ => TipoMovimientoInventario.entradaDevolucion,
    };

    await _insertarMovimiento(
      articuloId: asignacion.articuloId,
      varianteId: asignacion.varianteId,
      unidadId: asignacion.unidadId,
      cantidad: asignacion.cantidad,
      tipo: tipoMovimiento,
      fecha: fechaCierre,
      observaciones: observacionesCierre,
      actor: actor,
    );

    if (asignacion.unidadId != null) {
      final estatusUnidad = switch (estatusFinal) {
        EstatusAsignacion.danada => EstatusArticuloUnidad.danado,
        EstatusAsignacion.perdida => EstatusArticuloUnidad.perdido,
        _ => EstatusArticuloUnidad.disponible,
      };
      await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(asignacion.unidadId!))).write(
        ArticuloUnidadCompanion(estatus: Value(estatusUnidad.name), updatedAt: Value(DateTime.now())),
      );
    }

    if (generaDescuento) {
      await _db.into(_db.descuentoInventario).insert(
            DescuentoInventarioCompanion.insert(
              asignacionId: asignacionId,
              empleadoId: empleadoResponsableDescuentoId!,
              motivo: motivo,
              importe: importeDescuento!,
            ),
          );
    }

    return (_db.select(_db.asignacion)..where((t) => t.id.equals(asignacionId))).getSingle();
  }

  @override
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
  }) {
    return _db.transaction(() => _cerrar(
          asignacionId: asignacionId,
          motivo: motivo,
          fechaCierre: fechaCierre,
          observacionesCierre: observacionesCierre,
          atribuibleAlEmpleado: atribuibleAlEmpleado,
          generaDescuento: generaDescuento,
          importeDescuento: importeDescuento,
          empleadoResponsableDescuentoId: empleadoResponsableDescuentoId,
          actor: actor,
        ));
  }

  @override
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
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.asignacion)..where((t) => t.id.equals(asignacionId))).getSingle();

      await _cerrar(
        asignacionId: asignacionId,
        motivo: motivo,
        fechaCierre: fechaCierre,
        observacionesCierre: observacionesCierre,
        atribuibleAlEmpleado: atribuibleAlEmpleado,
        generaDescuento: generaDescuento,
        importeDescuento: importeDescuento,
        empleadoResponsableDescuentoId: empleadoResponsableDescuentoId,
        actor: actor,
      );

      final nueva = await _crear(
        articuloId: articuloIdReemplazo,
        varianteId: varianteIdReemplazo,
        unidadId: unidadIdReemplazo,
        cantidad: cantidadReemplazo,
        empleadoId: anterior.empleadoId,
        servicioId: anterior.servicioId,
        fechaEntrega: fechaCierre,
        condicionEntrega: condicionEntregaReemplazo,
        observaciones: observacionesReemplazo,
        actor: actor,
      );

      await (_db.update(_db.asignacion)..where((t) => t.id.equals(asignacionId))).write(
        AsignacionCompanion(asignacionReemplazoId: Value(nueva.id), updatedAt: Value(DateTime.now())),
      );

      return nueva;
    });
  }

  @override
  Future<DescuentoInventarioData> cancelarDescuento({
    required String descuentoId,
    String? observaciones,
    String? actor,
  }) async {
    await (_db.update(_db.descuentoInventario)..where((t) => t.id.equals(descuentoId))).write(
      DescuentoInventarioCompanion(
        estatus: Value(EstatusDescuentoInventario.cancelado.name),
        observaciones: Value(observaciones),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.descuentoInventario)..where((t) => t.id.equals(descuentoId))).getSingle();
  }

  @override
  Future<AttachmentData> adjuntarResguardo({
    required List<String> asignacionIds,
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
              categoria: const Value('resguardo'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      for (final asignacionId in asignacionIds) {
        await _db.into(_db.asignacionAttachment).insert(
              AsignacionAttachmentCompanion.insert(attachmentId: adjunto.id, asignacionId: asignacionId),
            );
      }
      return adjunto;
    });
  }
}
