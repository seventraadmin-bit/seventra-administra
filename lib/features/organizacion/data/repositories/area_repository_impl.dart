import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/area_repository.dart';
import '../../domain/usecases/eliminar_area_fisicamente_usecase.dart';

class AreaRepositoryImpl implements AreaRepository {
  AreaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<AreaData> crear({required String codigo, required String nombre, String? descripcion}) {
    return _db.into(_db.area).insertReturning(
          AreaCompanion.insert(
            id: const Uuid().v4(),
            codigo: codigo,
            nombre: nombre,
            descripcion: Value(descripcion),
          ),
        );
  }

  @override
  Future<AreaData> actualizar({required String id, required String nombre, String? descripcion}) async {
    await (_db.update(_db.area)..where((t) => t.id.equals(id))).write(
      AreaCompanion(
        nombre: Value(nombre),
        descripcion: Value(descripcion),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.area)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<AreaData?> obtenerPorId(String id) {
    return (_db.select(_db.area)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<AreaData>> listarTodas() {
    return (_db.select(_db.area)..orderBy([(t) => OrderingTerm.asc(t.codigo)])).get();
  }

  @override
  Future<List<AreaData>> listarActivas() {
    return (_db.select(_db.area)
          ..where((t) => t.activo.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.codigo)]))
        .get();
  }

  @override
  Future<AreaData> activar(String id) => _cambiarActivo(id, true);

  @override
  Future<AreaData> desactivar(String id) => _cambiarActivo(id, false);

  Future<AreaData> _cambiarActivo(String id, bool activo) async {
    await (_db.update(_db.area)..where((t) => t.id.equals(id))).write(
      AreaCompanion(activo: Value(activo), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.area)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Eliminación física extraordinaria (Etapa 11D) — condición
  /// aprobada: elegible solo si ningún `Puesto` referencia esta Área
  /// vía `areaId`. **Chequeos adicionales descubiertos durante la
  /// verificación del grafo de FK real** (no en la lista aprobada
  /// original, agregados por integridad): `Ingreso.areaId` y
  /// `Egreso.areaId` también referencian `Area` con `ON DELETE
  /// RESTRICT` — un Área alguna vez usada en un movimiento financiero
  /// ya es "uso real", no un simple error de captura. Todo —
  /// validación, snapshot, registro de auditoría y `DELETE` — ocurre en
  /// una sola transacción; nunca `CASCADE`.
  @override
  Future<EliminarAreaFisicamenteResultado> eliminarFisicamente({
    required String areaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final area = await (_db.select(_db.area)..where((t) => t.id.equals(areaId))).getSingleOrNull();
      if (area == null) return EliminarAreaFisicamenteNoExiste();

      final puestos = await (_db.select(_db.puesto)..where((t) => t.areaId.equals(areaId))).get();
      if (puestos.isNotEmpty) {
        return EliminarAreaFisicamenteTieneDependencias('Tiene ${puestos.length} puesto(s) registrado(s).');
      }

      final ingresos = await (_db.select(_db.ingreso)..where((t) => t.areaId.equals(areaId))).get();
      if (ingresos.isNotEmpty) {
        return EliminarAreaFisicamenteTieneDependencias('Tiene ${ingresos.length} ingreso(s) registrado(s).');
      }

      final egresos = await (_db.select(_db.egreso)..where((t) => t.areaId.equals(areaId))).get();
      if (egresos.isNotEmpty) {
        return EliminarAreaFisicamenteTieneDependencias('Tiene ${egresos.length} egreso(s) registrado(s).');
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'area',
              entidadIdOriginal: areaId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(area.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.area)..where((t) => t.id.equals(areaId))).go();

      return EliminarAreaFisicamenteExitoso();
    });
  }
}
