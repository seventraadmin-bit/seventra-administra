// Prueba unitaria directa de `migrarCodigosAreaV3` — a diferencia de
// `migration_test.dart` (que verifica la migración real 1→3/2→3 sobre
// esquemas históricos vía `SchemaVerifier`), esta prueba llama a la
// función de migración directamente para forzar el caso de colisión,
// que no ocurre en un flujo real pero debe manejarse sin ambigüedad.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/migrations/migrar_codigos_area_v3.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('correr la migración sobre una base ya en el formato definitivo es un no-op seguro', () async {
    // Una base recién creada ya siembra directo en `ARE-0001..0006` — la
    // migración debe poder correr de nuevo sin error ni cambios.
    await migrarCodigosAreaV3(db);

    final areas = await db.select(db.area).get();
    expect(areas.map((a) => a.codigo).toSet(), {
      'ARE-0001', 'ARE-0002', 'ARE-0003', 'ARE-0004', 'ARE-0005', 'ARE-0006',
    });
  });

  test('falla con un mensaje claro si el código destino ya pertenece a otra fila', () async {
    // Fuerza una colisión a propósito: la fila de RH "roba" el código que
    // le correspondería a Operaciones, y Operaciones vuelve a su código
    // anterior (simulando una migración a medias / dato corrupto).
    await (db.update(db.area)..where((t) => t.id.equals(SeedIds.areaOperaciones))).write(
      const AreaCompanion(codigo: Value('OPERACIONES')),
    );
    await (db.update(db.area)..where((t) => t.id.equals(SeedIds.areaRecursosHumanos))).write(
      const AreaCompanion(codigo: Value('ARE-0001')),
    );

    await expectLater(migrarCodigosAreaV3(db), throwsStateError);

    // Nada debe haberse escrito a medias: Operaciones sigue con su
    // código anterior, no con `ARE-0001` a medio aplicar.
    final operaciones = await (db.select(db.area)..where((t) => t.id.equals(SeedIds.areaOperaciones))).getSingle();
    expect(operaciones.codigo, 'OPERACIONES');
  });
}
