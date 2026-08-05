import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

import '../../domain/repositories/servicio_repository.dart';

class ServicioRepositoryImpl implements ServicioRepository {
  ServicioRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ServicioData> crear({
    required String codigoServicio,
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required DateTime fechaInicio,
    required String codigoUbicacionRaiz,
    DateTime? fechaTermino,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final servicio = await _db.into(_db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: codigoServicio,
              clienteId: clienteId,
              nombre: nombre,
              tipoServicioId: tipoServicioId,
              fechaInicio: fechaInicio,
              fechaTermino: Value(fechaTermino),
              observaciones: Value(observaciones),
            ),
          );

      // Ancla estructural del árbol de Ubicación — se crea siempre,
      // exista o no todavía una Dirección operativa (Etapa 4F.1, punto 8
      // de la aprobación: "la Ubicación raíz es el ancla estructural del
      // árbol, no la Dirección").
      await _db.into(_db.ubicacion).insert(
            UbicacionCompanion.insert(
              codigo: codigoUbicacionRaiz,
              nombre: nombre,
              tipoUbicacion: TipoUbicacion.servicio.name,
              servicioId: Value(servicio.id),
            ),
          );

      return servicio;
    });
  }

  @override
  Future<ServicioData?> obtenerPorId(String id) {
    return (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ServicioListItem>> listar() async {
    final query = _db.select(_db.servicio).join([
      innerJoin(_db.cliente, _db.cliente.id.equalsExp(_db.servicio.clienteId)),
      innerJoin(_db.tipoServicio, _db.tipoServicio.id.equalsExp(_db.servicio.tipoServicioId)),
    ]);

    final filas = await query.get();
    return [
      for (final fila in filas)
        ServicioListItem(
          servicio: fila.readTable(_db.servicio),
          clienteNombre: fila.readTable(_db.cliente).nombreComercial,
          tipoServicioNombre: fila.readTable(_db.tipoServicio).nombre,
        ),
    ];
  }

  @override
  Future<ServicioData> actualizar({required String id, required ServicioCompanion cambios}) async {
    await (_db.update(_db.servicio)..where((t) => t.id.equals(id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<ServicioData> cambiarEstatus({
    required String id,
    required EstatusServicio nuevo,
    DateTime? fechaTermino,
  }) async {
    await (_db.update(_db.servicio)..where((t) => t.id.equals(id))).write(
      ServicioCompanion(
        estatus: Value(nuevo.name),
        fechaTermino: Value(fechaTermino),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<bool> tieneDireccionOperativaActiva(String servicioId) async {
    final fila = await (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.servicioId.equals(servicioId) &
                t.tipoDireccion.equals(TipoDireccion.operativa.name) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
    return fila != null;
  }
}
