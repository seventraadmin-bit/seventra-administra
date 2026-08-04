import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

import '../../domain/repositories/sucursal_repository.dart';

class SucursalRepositoryImpl implements SucursalRepository {
  SucursalRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<SucursalData> crear({
    required String codigoSucursal,
    required String nombre,
    required String tipoSucursalId,
    required String codigoUbicacionRaiz,
    required String codigoAlmacenGeneral,
  }) {
    return _db.transaction(() async {
      final sucursal = await _db.into(_db.sucursal).insertReturning(
            SucursalCompanion.insert(
              codigo: codigoSucursal,
              nombre: nombre,
              tipoSucursalId: tipoSucursalId,
            ),
          );

      final raiz = await _db.into(_db.ubicacion).insertReturning(
            UbicacionCompanion.insert(
              codigo: codigoUbicacionRaiz,
              nombre: nombre,
              tipoUbicacion: TipoUbicacion.sucursal.name,
              sucursalId: Value(sucursal.id),
            ),
          );

      await _db.into(_db.ubicacion).insert(
            UbicacionCompanion.insert(
              codigo: codigoAlmacenGeneral,
              nombre: 'Almacén General',
              tipoUbicacion: TipoUbicacion.almacen.name,
              parentId: Value(raiz.id),
            ),
          );

      return sucursal;
    });
  }

  @override
  Future<SucursalData?> obtenerPorId(String id) {
    return (_db.select(_db.sucursal)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<SucursalData>> listarActivas() {
    return (_db.select(_db.sucursal)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }
}
