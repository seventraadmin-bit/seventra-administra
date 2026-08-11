// Pruebas de la Auditoría central (Etapa 11D) — `BuscarAuditoriaUseCase`
// + `AuditoriaRepositoryImpl` agregan ~17 orígenes reales de eventos en
// una sola forma unificada (`EventoAuditoria`). Esta suite no repite
// los ~17 orígenes (ya cubiertos indirectamente por el resto de la
// suite); solo verifica el mecanismo de agregación/filtro y la
// traducción `tipoEntidad -> modulo`, sembrando filas directamente en
// las tablas de origen (`EliminacionFisicaEvento`/`UsuarioEvento`) —
// más simple y suficiente, ya que `AuditoriaRepositoryImpl` solo las
// lee, sin lógica de negocio propia.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';

void main() {
  late AppDatabase db;
  late BuscarAuditoriaUseCase buscarAuditoria;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    buscarAuditoria = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-a'), nombre: 'Usuario A', nombreUsuario: 'usuario-a', passwordHash: 'x'),
        );
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-b'), nombre: 'Usuario B', nombreUsuario: 'usuario-b', passwordHash: 'x'),
        );
  });

  tearDown(() => db.close());

  Future<void> sembrarEliminacionFisica({
    required String tipoEntidad,
    required String entidadIdOriginal,
    String? actorUsuarioId,
    required DateTime fechaHora,
  }) {
    return db.into(db.eliminacionFisicaEvento).insert(
          EliminacionFisicaEventoCompanion.insert(
            tipoEntidad: tipoEntidad,
            entidadIdOriginal: entidadIdOriginal,
            fechaHora: fechaHora,
            motivo: 'motivo de prueba',
            snapshotJson: '{"id":"$entidadIdOriginal"}',
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  Future<void> sembrarUsuarioEvento({
    required String usuarioId,
    String? actorUsuarioId,
    required DateTime fechaHora,
  }) {
    return db.into(db.usuarioEvento).insert(
          UsuarioEventoCompanion.insert(
            usuarioId: usuarioId,
            fechaHora: fechaHora,
            tipoEvento: 'creado',
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  test('filtra por módulo — sembrando eventos de 2 módulos distintos, solo devuelve el pedido', () async {
    await sembrarEliminacionFisica(
      tipoEntidad: 'vehiculo',
      entidadIdOriginal: 'veh-1',
      actorUsuarioId: 'usuario-a',
      fechaHora: DateTime(2026, 1, 1),
    );
    await sembrarUsuarioEvento(usuarioId: 'usuario-b', actorUsuarioId: 'usuario-a', fechaHora: DateTime(2026, 1, 2));

    final resultado = await buscarAuditoria.ejecutar(const FiltroAuditoria(modulo: 'vehiculos'));

    expect(resultado, hasLength(1));
    expect(resultado.single.modulo, 'vehiculos');
    expect(resultado.single.registroId, 'veh-1');
  });

  test('filtra por actorUsuarioId — solo devuelve los eventos de ese actor', () async {
    await sembrarEliminacionFisica(
      tipoEntidad: 'vehiculo',
      entidadIdOriginal: 'veh-1',
      actorUsuarioId: 'usuario-a',
      fechaHora: DateTime(2026, 1, 1),
    );
    await sembrarEliminacionFisica(
      tipoEntidad: 'articulo',
      entidadIdOriginal: 'art-1',
      actorUsuarioId: 'usuario-b',
      fechaHora: DateTime(2026, 1, 1),
    );

    final resultado = await buscarAuditoria.ejecutar(const FiltroAuditoria(actorUsuarioId: 'usuario-a'));

    expect(resultado, hasLength(1));
    expect(resultado.single.registroId, 'veh-1');
    expect(resultado.single.actorUsuarioId, 'usuario-a');
  });

  test('filtra por rango de fechas — solo devuelve el evento dentro de desde/hasta', () async {
    await sembrarEliminacionFisica(tipoEntidad: 'vehiculo', entidadIdOriginal: 'veh-dentro', fechaHora: DateTime(2026, 1, 15));
    await sembrarEliminacionFisica(tipoEntidad: 'vehiculo', entidadIdOriginal: 'veh-fuera', fechaHora: DateTime(2026, 3, 1));

    final resultado =
        await buscarAuditoria.ejecutar(FiltroAuditoria(desde: DateTime(2026, 1, 1), hasta: DateTime(2026, 1, 31)));

    expect(resultado, hasLength(1));
    expect(resultado.single.registroId, 'veh-dentro');
  });

  test('un evento con actorUsuarioId null (histórico legítimo) se devuelve sin romper nada cuando no hay filtro de actor', () async {
    await sembrarEliminacionFisica(tipoEntidad: 'vehiculo', entidadIdOriginal: 'veh-sin-actor', fechaHora: DateTime(2026, 1, 1));

    final resultado = await buscarAuditoria.ejecutar(const FiltroAuditoria());

    expect(resultado, hasLength(1));
    expect(resultado.single.actorUsuarioId, isNull);
  });

  group('traducción tipoEntidad -> módulo (_moduloDeTipoEntidad)', () {
    test("'vehiculo' se traduce al código de módulo 'vehiculos'", () async {
      await sembrarEliminacionFisica(tipoEntidad: 'vehiculo', entidadIdOriginal: 'veh-1', fechaHora: DateTime(2026, 1, 1));

      final resultado = await buscarAuditoria.ejecutar(const FiltroAuditoria(modulo: 'vehiculos'));

      expect(resultado, hasLength(1));
      expect(resultado.single.accion, 'eliminacionFisica:vehiculo', reason: 'tipoEntidad completo se conserva en accion');
    });

    test("'categoriaArticulo' se traduce al código de módulo 'inventario' (mismo que 'articulo')", () async {
      await sembrarEliminacionFisica(tipoEntidad: 'categoriaArticulo', entidadIdOriginal: 'cat-1', fechaHora: DateTime(2026, 1, 1));
      await sembrarEliminacionFisica(tipoEntidad: 'articulo', entidadIdOriginal: 'art-1', fechaHora: DateTime(2026, 1, 1));

      final resultado = await buscarAuditoria.ejecutar(const FiltroAuditoria(modulo: 'inventario'));

      expect(resultado, hasLength(2), reason: 'ambos tipoEntidad comparten el módulo estándar inventario');
      expect(resultado.map((e) => e.registroId), containsAll(['cat-1', 'art-1']));
    });
  });
}
