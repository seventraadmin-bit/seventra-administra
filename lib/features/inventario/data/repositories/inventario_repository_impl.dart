import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/features/compras/data/tables/compra_table.dart' show EstatusCompra;

import '../../domain/repositories/inventario_repository.dart';
import '../../domain/usecases/existencia_articulo.dart';
import '../../domain/usecases/plegado_inventario.dart';
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
  Future<ArticuloUnidadData?> obtenerUnidadPorNumeroSerie(String numeroSerie) {
    return (_db.select(_db.articuloUnidad)..where((t) => t.numeroSerie.equals(numeroSerie))).getSingleOrNull();
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
  Future<Map<String, int>> contarUnidadesPorEstatus() async {
    final conteo = _db.articuloUnidad.id.count();
    final query = _db.selectOnly(_db.articuloUnidad)
      ..addColumns([_db.articuloUnidad.estatus, conteo])
      ..groupBy([_db.articuloUnidad.estatus]);
    final filas = await query.get();
    return {
      for (final fila in filas) fila.read(_db.articuloUnidad.estatus)!: fila.read(conteo) ?? 0,
    };
  }

  @override
  Future<List<ArticuloUnidadData>> listarTodasUnidades() {
    return (_db.select(_db.articuloUnidad)..orderBy([(t) => OrderingTerm.asc(t.codigo)])).get();
  }

  @override
  Future<List<ArticuloUnidadData>> listarUnidadesTelefono({String? estatus}) {
    final query = _db.select(_db.articuloUnidad).join([
      innerJoin(_db.articuloUnidadTelefono, _db.articuloUnidadTelefono.unidadId.equalsExp(_db.articuloUnidad.id)),
    ])
      ..orderBy([OrderingTerm.asc(_db.articuloUnidad.codigo)]);
    if (estatus != null) query.where(_db.articuloUnidad.estatus.equals(estatus));
    return query.map((row) => row.readTable(_db.articuloUnidad)).get();
  }

  @override
  Future<List<MovimientoInventarioData>> listarMovimientos({
    String? articuloId,
    String? varianteId,
    String? unidadId,
    DateTime? desde,
    DateTime? hasta,
  }) {
    final query = _db.select(_db.movimientoInventario);
    if (articuloId != null) query.where((t) => t.articuloId.equals(articuloId));
    if (varianteId != null) query.where((t) => t.varianteId.equals(varianteId));
    if (unidadId != null) query.where((t) => t.unidadId.equals(unidadId));
    if (desde != null) query.where((t) => t.fecha.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where((t) => t.fecha.isSmallerOrEqualValue(hasta));
    query.orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    return query.get();
  }

  @override
  Future<int> totalMovimientosEnRango({DateTime? desde, DateTime? hasta}) async {
    final query = _db.selectOnly(_db.movimientoInventario)..addColumns([_db.movimientoInventario.id.count()]);
    if (desde != null) query.where(_db.movimientoInventario.fecha.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where(_db.movimientoInventario.fecha.isSmallerOrEqualValue(hasta));
    final fila = await query.getSingle();
    return fila.read(_db.movimientoInventario.id.count()) ?? 0;
  }

  @override
  Future<MovimientoInventarioData?> obtenerMovimientoPorId(String movimientoInventarioId) {
    return (_db.select(_db.movimientoInventario)..where((t) => t.id.equals(movimientoInventarioId))).getSingleOrNull();
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
            costoUnitario: Value(costoUnitario),
            observaciones: Value(observaciones),
            actorUsuarioId: Value(actorUsuarioId),
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
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await _validarVarianteCoherente(articuloId: articuloId, varianteId: varianteId);
      return _insertarMovimiento(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        tipo: TipoMovimientoInventario.entrada,
        fecha: fecha,
        costoUnitario: costoUnitario,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
    });
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
    String? actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
      );

      return unidad;
    });
  }

  @override
  Future<List<ArticuloUnidadData>> regularizarUnidadesDesdeMovimiento({
    required String articuloId,
    required String movimientoInventarioId,
    required List<DatosUnidadRegularizada> unidades,
  }) {
    return _db.transaction(() async {
      final original =
          await (_db.select(_db.movimientoInventario)..where((t) => t.id.equals(movimientoInventarioId))).getSingle();

      await (_db.update(_db.articulo)..where((t) => t.id.equals(articuloId))).write(
        ArticuloCompanion(manejaSerie: const Value(true), updatedAt: Value(DateTime.now())),
      );

      final unidadesCreadas = <ArticuloUnidadData>[];
      final movimientoIdsNuevos = <String>[];
      for (final datos in unidades) {
        final unidad = await _db.into(_db.articuloUnidad).insertReturning(
              ArticuloUnidadCompanion.insert(
                codigo: datos.codigo,
                articuloId: articuloId,
                numeroSerie: datos.numeroSerie,
                marca: Value(datos.marca),
                modelo: Value(datos.modelo),
              ),
            );

        if ((datos.imei != null && datos.imei!.isNotEmpty) || (datos.imei2 != null && datos.imei2!.isNotEmpty)) {
          await _db.into(_db.articuloUnidadTelefono).insert(
                ArticuloUnidadTelefonoCompanion.insert(
                  unidadId: unidad.id,
                  imei: Value(datos.imei),
                  imei2: Value(datos.imei2),
                ),
              );
        }

        final movimientoNuevo = await _insertarMovimiento(
          articuloId: articuloId,
          unidadId: unidad.id,
          cantidad: 1,
          tipo: TipoMovimientoInventario.entrada,
          fecha: original.fecha,
          costoUnitario: original.costoUnitario,
          observaciones: original.observaciones,
          actorUsuarioId: original.actorUsuarioId,
        );

        unidadesCreadas.add(unidad);
        movimientoIdsNuevos.add(movimientoNuevo.id);
      }

      // `CompraPartidaMovimiento.movimientoInventarioId` referencia esta
      // fila con `ON DELETE RESTRICT` — si el movimiento original vino
      // de una Compra, borrar la fila de abajo sin mover primero este
      // puente violaría la FK. Se re-liga aquí, dentro de la misma
      // transacción, no en un paso aparte de Compras: la restricción de
      // la base de datos hace que esta atomicidad no sea opcional.
      final puenteOriginal = await (_db.select(_db.compraPartidaMovimiento)
            ..where((t) => t.movimientoInventarioId.equals(movimientoInventarioId)))
          .getSingleOrNull();
      if (puenteOriginal != null) {
        await (_db.delete(_db.compraPartidaMovimiento)
              ..where((t) => t.movimientoInventarioId.equals(movimientoInventarioId)))
            .go();
        for (final movimientoIdNuevo in movimientoIdsNuevos) {
          await _db.into(_db.compraPartidaMovimiento).insert(
                CompraPartidaMovimientoCompanion.insert(
                  compraPartidaId: puenteOriginal.compraPartidaId,
                  movimientoInventarioId: movimientoIdNuevo,
                ),
              );
        }
      }

      await (_db.delete(_db.movimientoInventario)..where((t) => t.id.equals(movimientoInventarioId))).go();

      return unidadesCreadas;
    });
  }

  @override
  Future<MovimientoInventarioData> registrarBaja({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required String observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await _validarVarianteCoherente(articuloId: articuloId, varianteId: varianteId);
      await _validarNoNegativo(articuloId: articuloId, varianteId: varianteId, cantidad: cantidad);
      return _insertarMovimiento(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        tipo: TipoMovimientoInventario.baja,
        fecha: DateTime.now(),
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
    });
  }

  /// Invariante de dominio (Etapa 15): nunca deja Disponible negativo,
  /// sin importar el llamador — ver el doc comment de
  /// `ExistenciaInsuficienteException`.
  Future<void> _validarNoNegativo({required String articuloId, String? varianteId, required int cantidad}) async {
    final existencia = await calcularExistencia(articuloId: articuloId, varianteId: varianteId);
    if (cantidad > existencia.disponible) {
      throw ExistenciaInsuficienteException(disponible: existencia.disponible, solicitado: cantidad);
    }
  }

  /// Invariante de dominio (Etapa 15): un movimiento por cantidad de
  /// un Artículo con variante SIEMPRE trae `varianteId` — ver el doc
  /// comment de `VarianteInvalidaException`.
  Future<void> _validarVarianteCoherente({required String articuloId, String? varianteId}) async {
    final articulo = await (_db.select(_db.articulo)..where((t) => t.id.equals(articuloId))).getSingleOrNull();
    if (articulo != null && articulo.manejaVariante != (varianteId != null)) {
      throw VarianteInvalidaException(articuloId: articuloId, manejaVariante: articulo.manejaVariante);
    }
  }

  @override
  Future<ArticuloUnidadData> actualizarEstatusUnidad({
    required String unidadId,
    required String estatus,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).write(
      ArticuloUnidadCompanion(estatus: Value(estatus), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle();
  }

  @override
  Future<ArticuloUnidadData> registrarBajaUnidad({
    required String unidadId,
    required String observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final unidad = await (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle();
      if (unidad.estatus == EstatusArticuloUnidad.asignado.name) {
        throw UnidadAsignadaException(unidadId: unidadId);
      }

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
        actorUsuarioId: actorUsuarioId,
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
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await _validarVarianteCoherente(articuloId: articuloId, varianteId: varianteId);
      if (!esEntrada) {
        await _validarNoNegativo(articuloId: articuloId, varianteId: varianteId, cantidad: cantidad);
      }
      return _insertarMovimiento(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        tipo: esEntrada ? TipoMovimientoInventario.ajusteEntrada : TipoMovimientoInventario.ajusteSalida,
        fecha: DateTime.now(),
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
    });
  }

  @override
  Future<ExistenciaArticulo> calcularExistencia({required String articuloId, String? varianteId}) async {
    // `varianteId == null` agrega TODOS los movimientos del artículo
    // (con o sin variante) — nunca se filtra por `varianteId IS NULL`,
    // porque eso excluiría los movimientos reales de un artículo con
    // variante (siempre traen `varianteId` no nulo) y dejaría su
    // existencia total en 0 pese a tener entradas válidas. Un artículo
    // SIN variante nunca genera movimientos con `varianteId`, así que
    // el resultado no cambia para ese caso.
    final query = _db.select(_db.movimientoInventario)..where((t) => t.articuloId.equals(articuloId));
    if (varianteId != null) {
      query.where((t) => t.varianteId.equals(varianteId));
    }
    // El plegado vive en el dominio (`plegarExistenciaDeMovimientos`):
    // esta capa sólo decide QUÉ filas leer. La versión en lote lee
    // distinto y pliega con la misma función, así que no puede
    // divergir.
    return plegarExistenciaDeMovimientos(await query.get());
  }

  @override
  Future<ExistenciaArticulo> calcularExistenciaUnidades(String articuloId) async {
    final unidades = await (_db.select(_db.articuloUnidad)..where((t) => t.articuloId.equals(articuloId))).get();
    return plegarExistenciaDeUnidades(unidades);
  }

  @override
  Future<Map<String, ExistenciaArticulo>> calcularExistenciaPorArticulos(Iterable<ArticuloData> articulos) async {
    final porId = {for (final a in articulos) a.id: a};
    if (porId.isEmpty) return {};

    // Dos consultas para CUALQUIER cantidad de artículos: una de
    // movimientos (artículos por cantidad) y una de unidades
    // (serializados). Nunca una por artículo.
    final serializados = {for (final a in porId.values) if (a.manejaSerie) a.id};
    final porCantidad = {for (final a in porId.values) if (!a.manejaSerie) a.id};

    final movimientos = porCantidad.isEmpty
        ? const <MovimientoInventarioData>[]
        : await (_db.select(_db.movimientoInventario)..where((t) => t.articuloId.isIn(porCantidad))).get();
    final unidades = serializados.isEmpty
        ? const <ArticuloUnidadData>[]
        : await (_db.select(_db.articuloUnidad)..where((t) => t.articuloId.isIn(serializados))).get();

    final movimientosPorArticulo = <String, List<MovimientoInventarioData>>{};
    for (final m in movimientos) {
      movimientosPorArticulo.putIfAbsent(m.articuloId, () => []).add(m);
    }
    final unidadesPorArticulo = <String, List<ArticuloUnidadData>>{};
    for (final u in unidades) {
      unidadesPorArticulo.putIfAbsent(u.articuloId, () => []).add(u);
    }

    // TODOS los artículos pedidos aparecen en el mapa, aunque no tengan
    // ni un movimiento ni una unidad: la versión individual devuelve
    // ceros en ese caso, no ausencia, y las dos tienen que coincidir.
    return {
      for (final articulo in porId.values)
        articulo.id: articulo.manejaSerie
            ? plegarExistenciaDeUnidades(unidadesPorArticulo[articulo.id] ?? const [])
            : plegarExistenciaDeMovimientos(movimientosPorArticulo[articulo.id] ?? const []),
    };
  }

  /// Los movimientos cuyo ORIGEN ECONÓMICO fue cancelado.
  ///
  /// Única definición del criterio: la usan las tres consultas de costo
  /// promedio (individual, por artículo y por variante), así que no
  /// pueden divergir. Se resuelve por la cadena de FK real
  /// `CompraPartidaMovimiento → CompraPartida → Compra.estatus`, nunca
  /// por descripción ni por el movimiento de reversa.
  ///
  /// Es una subconsulta, no una consulta aparte: el filtro viaja dentro
  /// del mismo `SELECT` y no agrega ni un viaje a la base, ni siquiera
  /// en las versiones en lote.
  Expression<bool> _origenCancelado(GeneratedColumn<String> movimientoId) {
    final deComprasCanceladas = _db.selectOnly(_db.compraPartidaMovimiento).join([
      innerJoin(
        _db.compraPartida,
        _db.compraPartida.id.equalsExp(_db.compraPartidaMovimiento.compraPartidaId),
      ),
      innerJoin(_db.compra, _db.compra.id.equalsExp(_db.compraPartida.compraId)),
    ])
      ..addColumns([_db.compraPartidaMovimiento.movimientoInventarioId])
      ..where(_db.compra.estatus.equals(EstatusCompra.cancelada.name));
    return movimientoId.isInQuery(deComprasCanceladas);
  }

  @override
  Future<Map<String, int>> calcularCostoPromedioPorArticulo(Iterable<String> articuloIds) async {
    final unicos = articuloIds.toSet();
    if (unicos.isEmpty) return {};
    // UNA consulta para todos los artículos, con el MISMO alcance que
    // `calcularCostoPromedio(articuloId: x)`: entradas del artículo sin
    // `varianteId`. Un artículo con variante no tiene costo promedio a
    // nivel de artículo —hay que preguntarlo por variante— y el lote no
    // puede inventarle uno promediando entre tallas distintas.
    final entradas = await (_db.select(_db.movimientoInventario)
          ..where((t) =>
              t.articuloId.isIn(unicos) &
              t.tipoMovimiento.equals(TipoMovimientoInventario.entrada.name) &
              t.varianteId.isNull() &
              _origenCancelado(t.id).not()))
        .get();

    final entradasPorArticulo = <String, List<MovimientoInventarioData>>{};
    for (final entrada in entradas) {
      entradasPorArticulo.putIfAbsent(entrada.articuloId, () => []).add(entrada);
    }

    // Un artículo sin costo NO aparece en el mapa — igual que la versión
    // individual devuelve `null`, nunca 0.
    final promedios = <String, int>{};
    for (final articuloId in entradasPorArticulo.keys) {
      final promedio = plegarCostoPromedio(entradasPorArticulo[articuloId]!);
      if (promedio != null) promedios[articuloId] = promedio;
    }
    return promedios;
  }

  @override
  Future<Map<String, int>> calcularCostoPromedioPorVariante(Iterable<String> varianteIds) async {
    final unicos = varianteIds.toSet();
    if (unicos.isEmpty) return {};
    // UNA consulta para todas las variantes, con el MISMO alcance que
    // `calcularCostoPromedio(articuloId: x, varianteId: y)`.
    final entradas = await (_db.select(_db.movimientoInventario)
          ..where((t) =>
              t.varianteId.isIn(unicos) &
              t.tipoMovimiento.equals(TipoMovimientoInventario.entrada.name) &
              _origenCancelado(t.id).not()))
        .get();

    final entradasPorVariante = <String, List<MovimientoInventarioData>>{};
    for (final entrada in entradas) {
      entradasPorVariante.putIfAbsent(entrada.varianteId!, () => []).add(entrada);
    }

    final promedios = <String, int>{};
    for (final varianteId in entradasPorVariante.keys) {
      final promedio = plegarCostoPromedio(entradasPorVariante[varianteId]!);
      if (promedio != null) promedios[varianteId] = promedio;
    }
    return promedios;
  }

  @override
  Future<int?> calcularCostoPromedio({required String articuloId, String? varianteId}) async {
    final query = _db.select(_db.movimientoInventario)
      ..where((t) =>
          t.articuloId.equals(articuloId) &
          t.tipoMovimiento.equals(TipoMovimientoInventario.entrada.name) &
          _origenCancelado(t.id).not());
    if (varianteId == null) {
      query.where((t) => t.varianteId.isNull());
    } else {
      query.where((t) => t.varianteId.equals(varianteId));
    }
    return plegarCostoPromedio(await query.get());
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String movimientoInventarioId,
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

  @override
  Future<ArticuloUnidadTelefonoData> actualizarTelefono({
    required String unidadId,
    String? imei,
    String? imei2,
  }) async {
    final existente = await obtenerTelefono(unidadId);
    if (existente == null) {
      return _db.into(_db.articuloUnidadTelefono).insertReturning(
            ArticuloUnidadTelefonoCompanion.insert(unidadId: unidadId, imei: Value(imei), imei2: Value(imei2)),
          );
    }

    await (_db.update(_db.articuloUnidadTelefono)..where((t) => t.unidadId.equals(unidadId)))
        .write(ArticuloUnidadTelefonoCompanion(imei: Value(imei), imei2: Value(imei2)));
    return (_db.select(_db.articuloUnidadTelefono)..where((t) => t.unidadId.equals(unidadId))).getSingle();
  }

  @override
  Future<List<ArticuloUnidadTelefonoData>> listarTelefonosPorImei(String imei) {
    return (_db.select(_db.articuloUnidadTelefono)
          ..where((t) => t.imei.equals(imei) | t.imei2.equals(imei)))
        .get();
  }

  @override
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
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle();
      final telefonoAnterior =
          await (_db.select(_db.articuloUnidadTelefono)..where((t) => t.unidadId.equals(unidadId))).getSingleOrNull();

      Future<void> registrarCambio(String campo, String? antes, String? despues) async {
        if (antes == despues) return;
        await _db.into(_db.articuloUnidadEvento).insert(
              ArticuloUnidadEventoCompanion.insert(
                unidadId: unidadId,
                fechaHora: DateTime.now(),
                tipoEvento: 'correccionIdentidad',
                campo: campo,
                valorAnterior: Value(antes),
                valorNuevo: Value(despues),
                motivo: motivo,
                actorUsuarioId: Value(actorUsuarioId),
              ),
            );
      }

      final nuevaMarca = limpiarMarca ? null : (marca ?? anterior.marca);
      final nuevoModelo = limpiarModelo ? null : (modelo ?? anterior.modelo);

      if (numeroSerie != null) await registrarCambio('numeroSerie', anterior.numeroSerie, numeroSerie);
      if (limpiarMarca || marca != null) await registrarCambio('marca', anterior.marca, nuevaMarca);
      if (limpiarModelo || modelo != null) await registrarCambio('modelo', anterior.modelo, nuevoModelo);

      await (_db.update(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).write(
        ArticuloUnidadCompanion(
          numeroSerie: numeroSerie == null ? const Value.absent() : Value(numeroSerie),
          marca: (limpiarMarca || marca != null) ? Value(nuevaMarca) : const Value.absent(),
          modelo: (limpiarModelo || modelo != null) ? Value(nuevoModelo) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (imei != null || limpiarImei || imei2 != null || limpiarImei2) {
        final nuevoImei = limpiarImei ? null : (imei ?? telefonoAnterior?.imei);
        final nuevoImei2 = limpiarImei2 ? null : (imei2 ?? telefonoAnterior?.imei2);

        if (limpiarImei || imei != null) await registrarCambio('imei1', telefonoAnterior?.imei, nuevoImei);
        if (limpiarImei2 || imei2 != null) await registrarCambio('imei2', telefonoAnterior?.imei2, nuevoImei2);

        if (telefonoAnterior == null) {
          await _db.into(_db.articuloUnidadTelefono).insert(
                ArticuloUnidadTelefonoCompanion.insert(unidadId: unidadId, imei: Value(nuevoImei), imei2: Value(nuevoImei2)),
              );
        } else {
          await (_db.update(_db.articuloUnidadTelefono)..where((t) => t.unidadId.equals(unidadId)))
              .write(ArticuloUnidadTelefonoCompanion(imei: Value(nuevoImei), imei2: Value(nuevoImei2)));
        }
      }

      return (_db.select(_db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle();
    });
  }

  @override
  Future<List<ArticuloUnidadEventoData>> listarEventosUnidad(String unidadId) {
    return (_db.select(_db.articuloUnidadEvento)
          ..where((t) => t.unidadId.equals(unidadId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaHora)]))
        .get();
  }
}
