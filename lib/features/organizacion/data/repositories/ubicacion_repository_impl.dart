import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

import '../../domain/repositories/ubicacion_repository.dart';

class UbicacionRepositoryImpl implements UbicacionRepository {
  UbicacionRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<UbicacionData?> obtenerPorId(String id) {
    return (_db.select(_db.ubicacion)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<UbicacionData?> obtenerRaizDeSucursal(String sucursalId) {
    return (_db.select(_db.ubicacion)
          ..where((t) => t.sucursalId.equals(sucursalId) & t.parentId.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<UbicacionData?> obtenerRaizDeServicio(String servicioId) {
    return (_db.select(_db.ubicacion)
          ..where((t) => t.servicioId.equals(servicioId) & t.parentId.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<List<UbicacionData>> obtenerHijos(String parentId) {
    return (_db.select(_db.ubicacion)..where((t) => t.parentId.equals(parentId))).get();
  }

  @override
  Future<UbicacionArbol> obtenerArbol(String raizId) async {
    final raiz = await obtenerPorId(raizId);
    if (raiz == null) {
      throw StateError('Ubicación no encontrada: $raizId');
    }
    return _construirArbol(raiz);
  }

  Future<UbicacionArbol> _construirArbol(UbicacionData nodo) async {
    final hijos = await obtenerHijos(nodo.id);
    final hijosArbol = <UbicacionArbol>[];
    for (final hijo in hijos) {
      hijosArbol.add(await _construirArbol(hijo));
    }
    return UbicacionArbol(nodo: nodo, hijos: hijosArbol);
  }

  @override
  Future<UbicacionData> crearHijo({
    required String codigo,
    required String nombre,
    required TipoUbicacion tipo,
    required String parentId,
  }) {
    return _db.into(_db.ubicacion).insertReturning(
          UbicacionCompanion.insert(
            codigo: codigo,
            nombre: nombre,
            tipoUbicacion: tipo.name,
            parentId: Value(parentId),
          ),
        );
  }

  @override
  Future<void> moverA({required String ubicacionId, required String nuevoParentId}) async {
    if (ubicacionId == nuevoParentId) {
      throw StateError('Una ubicación no puede ser su propio padre.');
    }
    await (_db.update(_db.ubicacion)..where((t) => t.id.equals(ubicacionId))).write(
      UbicacionCompanion(parentId: Value(nuevoParentId)),
    );
  }
}
