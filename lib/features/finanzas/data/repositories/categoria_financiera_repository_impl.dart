import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/categoria_financiera_repository.dart';
import '../../domain/usecases/eliminar_categoria_financiera_fisicamente_usecase.dart';

class CategoriaFinancieraRepositoryImpl implements CategoriaFinancieraRepository {
  CategoriaFinancieraRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<CategoriaFinancieraData?> obtenerPorId(String id) {
    return (_db.select(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<CategoriaFinancieraData>> listar({String? tipo}) {
    final query = _db.select(_db.categoriaFinanciera)..where((t) => t.cicloVidaRegistro.equals('activo'));
    if (tipo != null) {
      query.where((t) => t.tipo.equals(tipo) | t.tipo.equals('ambos'));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    return query.get();
  }

  @override
  Future<CategoriaFinancieraData> crear({
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  }) {
    return _db.into(_db.categoriaFinanciera).insertReturning(
          CategoriaFinancieraCompanion.insert(
            codigo: codigo,
            nombre: nombre,
            tipo: tipo,
            tipoMovimiento: tipoMovimiento,
          ),
        );
  }

  @override
  Future<CategoriaFinancieraData> actualizar({
    required String id,
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).write(
        CategoriaFinancieraCompanion(
          codigo: Value(codigo),
          nombre: Value(nombre),
          tipo: Value(tipo),
          tipoMovimiento: Value(tipoMovimiento),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  @override
  Future<CategoriaFinancieraData> archivar(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).write(
        CategoriaFinancieraCompanion(
          cicloVidaRegistro: const Value('archivado'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  /// Único bloqueo real: un Ingreso y/o Egreso todavía referencia esta
  /// Categoría vía `categoriaFinancieraId` (`onDelete: restrict`, ya lo
  /// impediría a nivel SQLite) — se verifica aquí primero para dar un
  /// mensaje específico con las cantidades reales, nunca una excepción
  /// SQL cruda.
  @override
  Future<ResumenEliminacionCategoriaFinanciera> obtenerResumenEliminacionFisica(String categoriaFinancieraId) async {
    final categoria = await obtenerPorId(categoriaFinancieraId);
    if (categoria == null) return const ResumenEliminacionCategoriaFinanciera(existe: false);

    final ingresos =
        await (_db.select(_db.ingreso)..where((t) => t.categoriaFinancieraId.equals(categoriaFinancieraId))).get();
    final egresos =
        await (_db.select(_db.egreso)..where((t) => t.categoriaFinancieraId.equals(categoriaFinancieraId))).get();

    if (ingresos.isNotEmpty || egresos.isNotEmpty) {
      final partes = <String>[
        if (ingresos.isNotEmpty) '${ingresos.length} ingreso(s)',
        if (egresos.isNotEmpty) '${egresos.length} egreso(s)',
      ];
      return ResumenEliminacionCategoriaFinanciera(
        existe: true,
        detalleBloqueo: 'Esta categoría está utilizada por ${partes.join(' y ')} registrado(s).',
      );
    }

    return const ResumenEliminacionCategoriaFinanciera(existe: true);
  }

  /// Eliminación física extraordinaria (Etapa 18) — condición exacta:
  /// elegible solo si ningún Ingreso/Egreso la referencia. Toda la
  /// validación, snapshot, registro de auditoría y `DELETE` ocurre en
  /// una sola transacción; nunca `CASCADE`.
  @override
  Future<EliminarCategoriaFinancieraFisicamenteResultado> eliminarFisicamente({
    required String categoriaFinancieraId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final categoria = await obtenerPorId(categoriaFinancieraId);
      if (categoria == null) return EliminarCategoriaFinancieraFisicamenteNoExiste();

      final resumen = await obtenerResumenEliminacionFisica(categoriaFinancieraId);
      if (resumen.bloqueado) {
        return EliminarCategoriaFinancieraFisicamenteTieneDependencias(resumen.detalleBloqueo!);
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'categoriaFinanciera',
              entidadIdOriginal: categoriaFinancieraId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(categoria.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.categoriaFinanciera)..where((t) => t.id.equals(categoriaFinancieraId))).go();

      return EliminarCategoriaFinancieraFisicamenteExitoso();
    });
  }
}
