import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/catalogo_repository.dart';

class CatalogoRepositoryImpl implements CatalogoRepository {
  CatalogoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<CatalogoItem>> listarTiposSucursal() async {
    final filas = await (_db.select(_db.tipoSucursal)
          ..where((t) => t.activo.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.orden), (t) => OrderingTerm.asc(t.nombre)]))
        .get();
    return [for (final fila in filas) CatalogoItem(id: fila.id, codigo: fila.codigo, nombre: fila.nombre)];
  }

  @override
  Future<List<CatalogoItem>> listarTiposServicio() async {
    final filas = await (_db.select(_db.tipoServicio)
          ..where((t) => t.activo.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.orden), (t) => OrderingTerm.asc(t.nombre)]))
        .get();
    return [for (final fila in filas) CatalogoItem(id: fila.id, codigo: fila.codigo, nombre: fila.nombre)];
  }

  @override
  Future<List<CatalogoItem>> listarModalidadesTurno() async {
    final filas = await (_db.select(_db.tipoModalidadTurno)
          ..where((t) => t.activo.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.orden), (t) => OrderingTerm.asc(t.nombre)]))
        .get();
    return [for (final fila in filas) CatalogoItem(id: fila.id, codigo: fila.codigo, nombre: fila.nombre)];
  }

  @override
  Future<List<CatalogoItem>> listarFrecuenciasCobro() async {
    final filas = await (_db.select(_db.tipoFrecuenciaCobro)
          ..where((t) => t.activo.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.orden), (t) => OrderingTerm.asc(t.nombre)]))
        .get();
    return [for (final fila in filas) CatalogoItem(id: fila.id, codigo: fila.codigo, nombre: fila.nombre)];
  }
}
