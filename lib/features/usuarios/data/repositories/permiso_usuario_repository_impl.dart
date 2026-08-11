import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/permiso_usuario_repository.dart';
import '../tables/usuario_table.dart';

class PermisoUsuarioRepositoryImpl implements PermisoUsuarioRepository {
  PermisoUsuarioRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<Set<String>> obtenerCodigos(String usuarioId) async {
    final filas = await (_db.select(_db.permisoUsuario)..where((t) => t.usuarioId.equals(usuarioId))).get();
    return filas.map((f) => f.codigo).toSet();
  }

  @override
  Future<void> guardar({
    required String usuarioId,
    required Set<String> codigos,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actuales = await obtenerCodigos(usuarioId);
      final agregados = codigos.difference(actuales);
      final removidos = actuales.difference(codigos);

      if (agregados.isEmpty && removidos.isEmpty) return;

      await (_db.delete(_db.permisoUsuario)..where((t) => t.usuarioId.equals(usuarioId))).go();
      if (codigos.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.permisoUsuario,
            [for (final codigo in codigos) PermisoUsuarioCompanion.insert(usuarioId: usuarioId, codigo: codigo)],
          );
        });
      }

      await _db.into(_db.usuarioEvento).insert(
            UsuarioEventoCompanion.insert(
              usuarioId: usuarioId,
              actorUsuarioId: Value(actorUsuarioId),
              fechaHora: DateTime.now(),
              tipoEvento: TipoEventoUsuario.permisosModificados.name,
              datosRelevantes: Value(jsonEncode({
                'agregados': agregados.toList()..sort(),
                'removidos': removidos.toList()..sort(),
              })),
            ),
          );
    });
  }
}
