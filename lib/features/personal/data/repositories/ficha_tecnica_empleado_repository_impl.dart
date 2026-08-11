import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/ficha_tecnica_empleado_repository.dart';
import '../tables/empleado_table.dart';
import 'empleado_evento_writer.dart';

class FichaTecnicaEmpleadoRepositoryImpl implements FichaTecnicaEmpleadoRepository {
  FichaTecnicaEmpleadoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<FichaTecnicaEmpleadoData> generar({
    required String empleadoId,
    required String folio,
    String? servicioId,
    String? camposExcluidos,
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
              categoria: const Value('fichaTecnica'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );

      final ficha = await _db.into(_db.fichaTecnicaEmpleado).insertReturning(
            FichaTecnicaEmpleadoCompanion.insert(
              folio: folio,
              empleadoId: empleadoId,
              servicioId: Value(servicioId),
              attachmentId: adjunto.id,
              camposExcluidos: Value(camposExcluidos),
            ),
          );

      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.fichaTecnicaGenerada,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'folio': folio, if (servicioId != null) 'servicioId': servicioId},
      );

      return ficha;
    });
  }

  @override
  Future<List<FichaTecnicaEmpleadoData>> listarPorEmpleado(String empleadoId) {
    // Orden por `folio` (no `createdAt`): `currentDateAndTime` en SQLite
    // solo tiene precisión de segundo, así que dos fichas generadas en
    // el mismo segundo empatarían. El folio, en cambio, es único y
    // estrictamente correlativo (`GenerarCodigoUseCase`) — comparación
    // lexicográfica ya equivale a numérica gracias al padding fijo de
    // dígitos, así que ordena "la más reciente primero" sin ambigüedad.
    return (_db.select(_db.fichaTecnicaEmpleado)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.desc(t.folio)]))
        .get();
  }
}
