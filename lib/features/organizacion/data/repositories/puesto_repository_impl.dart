import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/puesto_repository.dart';
import '../../domain/usecases/eliminar_puesto_fisicamente_usecase.dart';

class PuestoRepositoryImpl implements PuestoRepository {
  PuestoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<PuestoData> crear(PuestoCompanion datos) {
    return _db.into(_db.puesto).insertReturning(datos);
  }

  @override
  Future<PuestoData> actualizar({required String id, required PuestoCompanion cambios}) async {
    await (_db.update(_db.puesto)..where((t) => t.id.equals(id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<PuestoData?> obtenerPorId(String id) {
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<PuestoData>> listarActivos() {
    return (_db.select(_db.puesto)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }

  @override
  Future<PuestoData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo}) async {
    await (_db.update(_db.puesto)..where((t) => t.id.equals(id))).write(
      PuestoCompanion(cicloVidaRegistro: Value(nuevo.name), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<int> contarActivosPorArea(String areaId) async {
    final conteo = _db.puesto.id.count();
    final query = _db.selectOnly(_db.puesto)
      ..addColumns([conteo])
      ..where(
        _db.puesto.areaId.equals(areaId) &
            _db.puesto.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
      );
    final fila = await query.getSingle();
    return fila.read(conteo) ?? 0;
  }

  /// Eliminación física extraordinaria (Etapa 11D) — condiciones
  /// exactas acordadas con Marlon: elegible solo si el Puesto nunca
  /// tuvo `ServicioLineaComercialVigencia`, ni fue asignado a ningún
  /// `Usuario` (vía `puestoId`) ni a ningún `Empleado` (vía
  /// `puestoId`). Todo — validación, snapshot, registro de auditoría y
  /// `DELETE` — ocurre en una sola transacción; nunca `CASCADE` sobre
  /// ninguna de esas tablas.
  @override
  Future<EliminarPuestoFisicamenteResultado> eliminarFisicamente({
    required String puestoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final puesto = await (_db.select(_db.puesto)..where((t) => t.id.equals(puestoId))).getSingleOrNull();
      if (puesto == null) return EliminarPuestoFisicamenteNoExiste();

      final vigencias = await (_db.select(_db.servicioLineaComercialVigencia)
            ..where((t) => t.puestoId.equals(puestoId)))
          .get();
      if (vigencias.isNotEmpty) {
        return EliminarPuestoFisicamenteTieneDependencias(
          'Tiene ${vigencias.length} vigencia(s) comercial(es) registrada(s).',
        );
      }

      final usuarios = await (_db.select(_db.usuario)..where((t) => t.puestoId.equals(puestoId))).get();
      if (usuarios.isNotEmpty) {
        return EliminarPuestoFisicamenteTieneDependencias('Tiene ${usuarios.length} usuario(s) registrado(s).');
      }

      final empleados = await (_db.select(_db.empleado)..where((t) => t.puestoId.equals(puestoId))).get();
      if (empleados.isNotEmpty) {
        return EliminarPuestoFisicamenteTieneDependencias('Tiene ${empleados.length} empleado(s) registrado(s).');
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'puesto',
              entidadIdOriginal: puestoId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(puesto.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.puesto)..where((t) => t.id.equals(puestoId))).go();

      return EliminarPuestoFisicamenteExitoso();
    });
  }
}
