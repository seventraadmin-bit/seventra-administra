import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/cliente_repository.dart';

class ClienteRepositoryImpl implements ClienteRepository {
  ClienteRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<bool> existeRfc(String rfcNormalizado) async {
    final fila = await (_db.select(_db.cliente)..where((t) => t.rfc.equals(rfcNormalizado)))
        .getSingleOrNull();
    return fila != null;
  }

  @override
  Future<ClienteData> crear(ClienteCompanion datos) {
    return _db.into(_db.cliente).insertReturning(datos);
  }

  @override
  Future<ClienteData?> obtenerPorId(String id) {
    return (_db.select(_db.cliente)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ClienteData>> listarActivos() {
    return (_db.select(_db.cliente)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }

  @override
  Future<ContactoData> agregarContacto(ContactoCompanion datos) {
    return _db.into(_db.contacto).insertReturning(datos);
  }

  @override
  Future<List<ContactoData>> obtenerContactos(String clienteId) {
    return (_db.select(_db.contacto)..where((t) => t.clienteId.equals(clienteId))).get();
  }
}
