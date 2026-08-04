import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/empresa_repository.dart';

class EmpresaRepositoryImpl implements EmpresaRepository {
  EmpresaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EmpresaData> obtenerActiva() async {
    final activas = await (_db.select(_db.empresa)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();

    if (activas.isEmpty) {
      throw StateError('No existe ninguna Empresa activa — la siembra inicial debió crear RSG-01.');
    }
    if (activas.length > 1) {
      throw StateError('Invariante violado: hay ${activas.length} empresas activas simultáneamente.');
    }
    return activas.single;
  }

  @override
  Future<void> actualizarDatosGenerales(EmpresaCompanion cambios) async {
    final activa = await obtenerActiva();
    await (_db.update(_db.empresa)..where((t) => t.id.equals(activa.id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> archivar(String id) async {
    final activa = await obtenerActiva();
    if (activa.id == id) {
      throw StateError(
        'No se puede archivar la única Empresa activa sin una operación administrativa especial.',
      );
    }
    await (_db.update(_db.empresa)..where((t) => t.id.equals(id))).write(
      EmpresaCompanion(
        cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
