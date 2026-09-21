import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_de_unidad_coordinador.dart';

import '../../domain/repositories/asignacion_repository.dart';
import '../../domain/repositories/linea_telefonica_de_unidad.dart';
import '../tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../tables/asignacion_table.dart' show EstatusAsignacion, MotivoCierreAsignacion;
import '../tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import '../tables/movimiento_inventario_table.dart' show TipoMovimientoInventario;

class AsignacionRepositoryImpl implements AsignacionRepository {
  /// [lineaTelefonica] se inyecta sólo en pruebas que quieran aislar
  /// el efecto; por defecto SIEMPRE está activo, para que ningún punto
  /// de construcción se quede sin coherencia por olvido.
  AsignacionRepositoryImpl(AppDatabase db, {LineaTelefonicaDeUnidad? lineaTelefonica})
      : _db = db,
        _lineaTelefonica = lineaTelefonica ?? LineaTelefonicaDeUnidadCoordinador.desde(db);

  final AppDatabase _db;

  /// Inventario manda sobre la custodia física; cuando la mueve, la
  /// línea telefónica que el aparato trae la sigue — dentro de esta
  /// misma transacción. Ver [LineaTelefonicaDeUnidad].
  final LineaTelefonicaDeUnidad _lineaTelefonica;

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
  Future<List<AsignacionData>> listarActivasPorUnidades(List<String> unidadIds) {
    if (unidadIds.isEmpty) return Future.value(const []);
    return (_db.select(_db.asignacion)
          ..where((t) => t.unidadId.isIn(unidadIds) & t.estatus.equals('activa')))
        .get();
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
  Future<List<DescuentoInventarioData>> listarDescuentosPorEmpleado(String empleadoId) {
    final query = _db.select(_db.descuentoInventario)
      ..where((t) => t.empleadoId.equals(empleadoId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<List<DescuentoInventarioData>> listarDescuentosPorNominaEmpleado(String nominaEmpleadoId) {
    final query = _db.select(_db.descuentoInventario)..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId));
    return query.get();
  }

  @override
  Future<List<AsignacionData>> listarPorIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (_db.select(_db.asignacion)..where((t) => t.id.isIn(ids))).get();
  }

  @override
  Future<List<AsignacionData>> listarActivasPorArticulo(String articuloId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.articuloId.equals(articuloId) & t.estatus.equals(EstatusAsignacion.activa.name))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
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
    String? actorUsuarioId,
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
            actorUsuarioId: Value(actorUsuarioId),
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
    String? actorUsuarioId,
    String? entregaId,
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
            actorUsuarioId: Value(actorUsuarioId),
            entregaId: Value(entregaId),
          ),
        );

    await _insertarMovimiento(
      articuloId: articuloId,
      varianteId: varianteId,
      unidadId: unidadId,
      cantidad: cantidad,
      tipo: TipoMovimientoInventario.salidaAsignacion,
      fecha: fechaEntrega,
      actorUsuarioId: actorUsuarioId,
    );

    if (unidadId != null) {
      await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).write(
        ArticuloUnidadCompanion(
          estatus: Value(EstatusArticuloUnidad.asignado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // La custodia física cambió de manos: si el aparato trae una
      // línea telefónica, su asignación sigue a la custodia, aquí
      // dentro. Nunca al revés.
      await _lineaTelefonica.alinearAlNuevoDestino(
        unidadId: unidadId,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fecha: fechaEntrega,
        origenAsignacionInventarioId: asignacion.id,
        actorUsuarioId: actorUsuarioId,
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
    String? actorUsuarioId,
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
          actorUsuarioId: actorUsuarioId,
        ));
  }

  @override
  Future<List<AsignacionData>> listarPorEntrega(String entregaId) {
    final query = _db.select(_db.asignacion)
      ..where((t) => t.entregaId.equals(entregaId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<EntregaCreada> crearEntrega({
    required String folio,
    required List<AsignacionLineaInput> lineas,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaEntrega,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final entrega = await _db.into(_db.entrega).insertReturning(
            EntregaCompanion.insert(
              folio: folio,
              empleadoId: Value(empleadoId),
              servicioId: Value(servicioId),
              fechaEntrega: fechaEntrega,
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      final asignaciones = <AsignacionData>[];
      for (final linea in lineas) {
        asignaciones.add(await _crear(
          articuloId: linea.articuloId,
          varianteId: linea.varianteId,
          unidadId: linea.unidadId,
          cantidad: linea.cantidad,
          empleadoId: empleadoId,
          servicioId: servicioId,
          fechaEntrega: fechaEntrega,
          condicionEntrega: linea.condicionEntrega,
          observaciones: linea.observaciones,
          actorUsuarioId: actorUsuarioId,
          entregaId: entrega.id,
        ));
      }
      return (entrega: entrega, asignaciones: asignaciones);
    });
  }

  @override
  Future<void> marcarPendientesPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  }) async {
    // Una sola sentencia para todos los bienes de la persona: o quedan
    // marcados todos, o ninguno. Ya estamos dentro de la transacción de
    // la baja laboral, así que un fallo aquí la revierte también.
    await (_db.update(_db.asignacion)
          ..where((t) =>
              t.empleadoId.equals(empleadoId) &
              t.estatus.equals(EstatusAsignacion.activa.name) &
              t.pendienteRecuperacionDesde.isNull()))
        .write(
      AsignacionCompanion(
        pendienteRecuperacionDesde: Value(fecha),
        // El actor de la baja laboral: el marcado derivado conserva
        // quién originó la operación.
        actorUsuarioId: actorUsuarioId == null ? const Value.absent() : Value(actorUsuarioId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> marcarPendienteRecuperacion({
    required String asignacionId,
    required DateTime fecha,
    String? actorUsuarioId,
  }) async {
    await (_db.update(_db.asignacion)..where((t) => t.id.equals(asignacionId))).write(
      AsignacionCompanion(
        pendienteRecuperacionDesde: Value(fecha),
        actorUsuarioId: actorUsuarioId == null ? const Value.absent() : Value(actorUsuarioId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<List<AsignacionData>> listarPendientesRecuperacionPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacion)
          ..where((t) =>
              t.empleadoId.equals(empleadoId) &
              t.estatus.equals(EstatusAsignacion.activa.name) &
              t.pendienteRecuperacionDesde.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]))
        .get();
  }

  Future<AsignacionData> _cerrar({
    required String asignacionId,
    required String motivo,
    required DateTime fechaCierre,
    EstatusArticuloUnidad? ubicacionUnidad,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    String? actorUsuarioId,
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
        // El pendiente se resolvió: devuelto, dañado o perdido — los
        // tres son desenlaces válidos del ciclo que ya existía. La
        // marca se limpia; la fecha de cierre es la REAL de la
        // devolución, nunca la de la baja laboral.
        pendienteRecuperacionDesde: const Value(null),
        motivoCierre: Value(motivo),
        observacionesCierre: Value(observacionesCierre),
        atribuibleAlEmpleado: Value(atribuibleAlEmpleado),
        updatedAt: Value(DateTime.now()),
        actorUsuarioId: Value(actorUsuarioId),
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
      actorUsuarioId: actorUsuarioId,
    );

    if (asignacion.unidadId != null) {
      // Una ubicación intermedia gana sobre el mapeo por motivo: el bien
      // volvió a RISEG, pero está en la tintorería o en el taller, no en
      // el anaquel. Decir "disponible" ahí sería ofrecerlo para
      // reasignar mientras sigue fuera.
      final estatusUnidad = ubicacionUnidad ??
          switch (estatusFinal) {
            EstatusAsignacion.danada => EstatusArticuloUnidad.danado,
            EstatusAsignacion.perdida => EstatusArticuloUnidad.perdido,
            _ => EstatusArticuloUnidad.disponible,
          };
      await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(asignacion.unidadId!))).write(
        ArticuloUnidadCompanion(estatus: Value(estatusUnidad.name), updatedAt: Value(DateTime.now())),
      );

      // Ya no hay destino físico al que la línea deba acompañar. La
      // asociación Línea↔Equipo NO se toca: que el teléfono vuelva al
      // anaquel no borra que trajo esa SIM.
      await _lineaTelefonica.cerrarPorFinDeCustodia(
        unidadId: asignacion.unidadId!,
        fecha: fechaCierre,
        origenAsignacionInventarioId: asignacionId,
        actorUsuarioId: actorUsuarioId,
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
    EstatusArticuloUnidad? ubicacionUnidad,
    String? observacionesCierre,
    bool? atribuibleAlEmpleado,
    bool generaDescuento = false,
    int? importeDescuento,
    String? empleadoResponsableDescuentoId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() => _cerrar(
          asignacionId: asignacionId,
          motivo: motivo,
          fechaCierre: fechaCierre,
          ubicacionUnidad: ubicacionUnidad,
          observacionesCierre: observacionesCierre,
          atribuibleAlEmpleado: atribuibleAlEmpleado,
          generaDescuento: generaDescuento,
          importeDescuento: importeDescuento,
          empleadoResponsableDescuentoId: empleadoResponsableDescuentoId,
          actorUsuarioId: actorUsuarioId,
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
    String? actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
      );

      await (_db.update(_db.asignacion)..where((t) => t.id.equals(asignacionId))).write(
        AsignacionCompanion(asignacionReemplazoId: Value(nueva.id), updatedAt: Value(DateTime.now())),
      );

      return nueva;
    });
  }

  @override
  Future<AsignacionData> cambiarResponsable({
    required String asignacionId,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.asignacion)..where((t) => t.id.equals(asignacionId))).getSingle();

      await (_db.update(_db.asignacion)..where((t) => t.id.equals(asignacionId))).write(
        AsignacionCompanion(
          estatus: Value(EstatusAsignacion.reasignada.name),
          fechaCierre: Value(fecha),
          motivoCierre: const Value('cambioResponsable'),
          observacionesCierre: Value(observaciones),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );

      final nueva = await _db.into(_db.asignacion).insertReturning(
            AsignacionCompanion.insert(
              articuloId: anterior.articuloId,
              varianteId: Value(anterior.varianteId),
              unidadId: Value(anterior.unidadId),
              cantidad: anterior.cantidad,
              empleadoId: Value(nuevoEmpleadoId),
              servicioId: Value(nuevoServicioId),
              fechaEntrega: fecha,
              condicionEntrega: Value(anterior.condicionEntrega),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // Transferencia del aparato: la línea que trae viaja con él, en
      // esta misma transacción — nunca queda apuntando al responsable
      // anterior.
      if (anterior.unidadId != null) {
        await _lineaTelefonica.alinearAlNuevoDestino(
          unidadId: anterior.unidadId!,
          empleadoId: nuevoEmpleadoId,
          servicioId: nuevoServicioId,
          fecha: fecha,
          origenAsignacionInventarioId: nueva.id,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return nueva;
    });
  }

  @override
  Future<DescuentoInventarioData> cancelarDescuento({
    required String descuentoId,
    String? observaciones,
    String? actorUsuarioId,
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
  Future<void> aplicarDescuentos({
    required List<String> descuentoIds,
    required String nominaEmpleadoId,
    required DateTime fechaAplicacion,
  }) async {
    if (descuentoIds.isEmpty) return;
    await (_db.update(_db.descuentoInventario)..where((t) => t.id.isIn(descuentoIds))).write(
      DescuentoInventarioCompanion(
        estatus: Value(EstatusDescuentoInventario.aplicado.name),
        nominaEmpleadoId: Value(nominaEmpleadoId),
        fechaAplicacion: Value(fechaAplicacion),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> revertirDescuentosAplicados(List<String> nominaEmpleadoIds) async {
    if (nominaEmpleadoIds.isEmpty) return;
    await (_db.update(_db.descuentoInventario)
          ..where(
            (t) => t.nominaEmpleadoId.isIn(nominaEmpleadoIds) & t.estatus.equals(EstatusDescuentoInventario.aplicado.name),
          ))
        .write(
      DescuentoInventarioCompanion(
        estatus: Value(EstatusDescuentoInventario.pendiente.name),
        nominaEmpleadoId: const Value(null),
        fechaAplicacion: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<AttachmentData> adjuntarResguardo({
    required List<String> asignacionIds,
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
