import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_data.dart';

import '../../generated_migrations/schema.dart';

/// Verifica la migración real 1 → 2 sobre una base física construida
/// desde el snapshot de schemaVersion 1 (`drift_schemas/riseg_one/`) —
/// no una prueba manual de `onUpgrade`, sino la migración generada
/// corriendo contra el esquema histórico real.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('1.json representa exactamente el schemaVersion 1 actual (solo AppMetadata)', () async {
    final schema = await verifier.schemaAt(1);
    final tablas = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toList();

    expect(tablas, contains('app_metadata'));
    // Ninguna tabla de la Etapa 4A debe existir todavía en v1.
    expect(tablas, isNot(contains('empresa')));
    expect(tablas, isNot(contains('cliente')));
    schema.rawDatabase.dispose();
  });

  test('2.json coincide con el esquema final de la Etapa 4A', () async {
    final schema = await verifier.schemaAt(2);
    final tablas = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toSet();

    expect(
      tablas,
      containsAll(<String>[
        'app_metadata', 'codigo_secuencia', 'tipo_sucursal', 'industria',
        'tipo_servicio', 'area', 'direccion', 'medio_contacto', 'attachment',
        'horario', 'horario_detalle', 'empresa', 'sucursal', 'cliente',
        'contacto', 'servicio', 'ubicacion', 'puesto',
      ]),
    );
    schema.rawDatabase.dispose();
  });

  test('migración 1 → 2 conserva AppMetadata original y aplica la siembra', () async {
    // Construye una base física en schemaVersion 1 con un renglón real de
    // AppMetadata, como tendría una instalación existente.
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());

    // Corre la migración real 1 -> 2 generada por el proyecto y valida
    // que el esquema resultante coincide con drift_schema_v2.json.
    await verifier.migrateAndValidate(db, 2);

    // El renglón de AppMetadata que ya existía antes de migrar debe
    // seguir intacto — la migración es puramente aditiva.
    final metadata = await db.select(db.appMetadata).getSingle();
    expect(metadata.installationId, 'instalacion-real-existente');

    // La siembra debió correr como parte de onUpgrade.
    final empresas = await db.select(db.empresa).get();
    expect(empresas, hasLength(1));
    expect(empresas.single.codigo, 'RSG-01');

    final tiposSucursal = await db.select(db.tipoSucursal).get();
    expect(tiposSucursal, hasLength(3));

    await db.close();
  });

  test('runSeed es idempotente: llamarlo varias veces no duplica filas', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, 2);

    // La migración ya corrió la siembra una vez; se invoca explícitamente
    // varias veces más para comprobar que no duplica nada.
    await runSeed(db);
    await runSeed(db);
    await runSeed(db);

    final empresas = await db.select(db.empresa).get();
    expect(empresas, hasLength(1));

    final tiposSucursal = await db.select(db.tipoSucursal).get();
    expect(tiposSucursal, hasLength(3));

    final industrias = await db.select(db.industria).get();
    expect(industrias, hasLength(5));

    final tiposServicio = await db.select(db.tipoServicio).get();
    expect(tiposServicio, hasLength(4));

    final areas = await db.select(db.area).get();
    expect(areas, hasLength(6));

    final codigosSecuencia = await db.select(db.codigoSecuencia).get();
    expect(codigosSecuencia, hasLength(6));

    await db.close();
  });
}
