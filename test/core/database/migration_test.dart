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

  test('migración 1 → versión actual conserva AppMetadata original y aplica la siembra', () async {
    // Construye una base física en schemaVersion 1 con un renglón real de
    // AppMetadata, como tendría una instalación existente.
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());

    // Corre la migración real generada por el proyecto hasta la versión
    // actual (4) — no puede validarse contra un objetivo intermedio (2)
    // porque `_createEtapa4ATables` siempre crea Cliente/Contacto con la
    // forma *actual* de sus clases Dart (ya la de la Etapa 4E.1), sin
    // importar el objetivo nominal de la migración.
    await verifier.migrateAndValidate(db, 4);

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
    await verifier.migrateAndValidate(db, 4);

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
    expect(codigosSecuencia, hasLength(7));

    await db.close();
  });

  test('3.json coincide con el esquema final de la Etapa 4D (mismas tablas que 2, sin cambios estructurales)', () async {
    final schema = await verifier.schemaAt(3);
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

  test('migración 1 → versión actual siembra las Áreas ya con el formato definitivo', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final metadata = await db.select(db.appMetadata).getSingle();
    expect(metadata.installationId, 'instalacion-real-existente');

    final areas = await db.select(db.area).get();
    expect(areas, hasLength(6));
    expect(areas.map((a) => a.codigo).toSet(), {
      'ARE-0001', 'ARE-0002', 'ARE-0003', 'ARE-0004', 'ARE-0005', 'ARE-0006',
    });

    final codigoArea = await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('area'))).getSingle();
    expect(codigoArea.prefijo, 'ARE');
    expect(codigoArea.digitos, 4);
    expect(codigoArea.contadorActual, 6);
    expect(codigoArea.reseteaAnualmente, isFalse);

    await db.close();
  });

  test('migración 2 → versión actual convierte los códigos alfabéticos de Área existentes sin duplicar filas', () async {
    // Simula una instalación real que ya pasó por la Etapa 4A/4B/4C —
    // llegó a schemaVersion 2 cuando `_seedArea` todavía sembraba códigos
    // alfabéticos, así que se insertan a mano tal como habrían quedado
    // entonces (nunca se reconstruye ese estado llamando al `runSeed`
    // actual, que ya siembra en el formato nuevo).
    final schemaV2 = await verifier.schemaAt(2);
    schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    final filasArea = [
      ('00000000-0000-4000-8000-000000000301', 'OPERACIONES', 'Operaciones'),
      ('00000000-0000-4000-8000-000000000302', 'RH', 'Recursos Humanos'),
      ('00000000-0000-4000-8000-000000000303', 'ADMINISTRACION', 'Administración'),
      ('00000000-0000-4000-8000-000000000304', 'DIRECCION', 'Dirección'),
      ('00000000-0000-4000-8000-000000000305', 'MONITOREO', 'Monitoreo'),
      ('00000000-0000-4000-8000-000000000306', 'RECLUTAMIENTO', 'Reclutamiento'),
    ];
    for (final (id, codigo, nombre) in filasArea) {
      schemaV2.rawDatabase.execute(
        '''
        INSERT INTO area (id, codigo, nombre, activo, created_at, updated_at)
        VALUES (?, ?, ?, 1, 1700000000, 1700000000);
        ''',
        [id, codigo, nombre],
      );
    }
    // Nota deliberada: en una instalación real llegada a v2, la fila de
    // `codigo_secuencia` para `'area'` todavía NO existe — se introdujo
    // apenas en esta etapa.

    final db = AppDatabase(schemaV2.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final metadata = await db.select(db.appMetadata).getSingle();
    expect(metadata.installationId, 'instalacion-real-existente');

    final areas = await db.select(db.area).get();
    expect(areas, hasLength(6), reason: 'la migración no debe duplicar filas');
    expect(areas.map((a) => a.codigo).toSet(), {
      'ARE-0001', 'ARE-0002', 'ARE-0003', 'ARE-0004', 'ARE-0005', 'ARE-0006',
    });
    // Nombre/descripción/estado se conservan intactos — la migración
    // solo tocó `codigo`.
    final operaciones = areas.firstWhere((a) => a.codigo == 'ARE-0001');
    expect(operaciones.nombre, 'Operaciones');
    expect(operaciones.activo, isTrue);

    final codigoArea = await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('area'))).getSingle();
    expect(codigoArea.contadorActual, 6);

    await db.close();
  });

  test('4.json coincide con el esquema final de la Etapa 4E.1 (sin tablas nuevas)', () async {
    final schema = await verifier.schemaAt(4);
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

    final columnasCliente = schema.rawDatabase
        .select("PRAGMA table_info(cliente)")
        .map((row) => row['name'] as String)
        .toSet();
    expect(columnasCliente, isNot(contains('razon_social')));
    expect(columnasCliente, isNot(contains('rfc')));
    expect(columnasCliente, contains('nombre_comercial'));
    expect(columnasCliente, contains('industria_id'));

    final columnasContacto = schema.rawDatabase
        .select("PRAGMA table_info(contacto)")
        .map((row) => row['name'] as String)
        .toSet();
    expect(columnasContacto, contains('tipo'));

    final indices = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'index'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(indices, contains('idx_contacto_cliente_tipo_principal_activo'));

    schema.rawDatabase.dispose();
  });

  test('migración 1 → 4 directa crea Cliente/Contacto ya con la forma nueva', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final metadata = await db.select(db.appMetadata).getSingle();
    expect(metadata.installationId, 'instalacion-real-existente');

    // Debe poder insertarse un Cliente con la forma nueva (sin razón
    // social/RFC, nombreComercial requerido) sin ningún error.
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Prueba S.A.'),
        );
    expect(cliente.nombreComercial, 'Prueba S.A.');

    await db.close();
  });

  test('migración 2 → 4 con Cliente/Contacto vacíos no falla y deja la forma nueva', () async {
    final schemaV2 = await verifier.schemaAt(2);
    schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV2.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Prueba S.A.'),
        );
    final contacto = await db.into(db.contacto).insertReturning(
          ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Juan Pérez', tipo: 'comercial'),
        );
    expect(contacto.tipo, 'comercial');

    await db.close();
  });

  test('migración 3 → 4 con Cliente/Contacto vacíos no falla y deja la forma nueva', () async {
    final schemaV3 = await verifier.schemaAt(3);
    schemaV3.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV3.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Prueba S.A.'),
        );
    expect(cliente.nombreComercial, 'Prueba S.A.');

    await db.close();
  });

  test('migración 2 → 4 falla explícitamente si Cliente ya tiene filas reales', () async {
    // Simula una instalación real (imposible hoy, pero la migración debe
    // protegerse igual) que ya tenía un Cliente capturado con la forma
    // anterior — la migración debe detenerse en vez de descartar sus
    // datos en silencio.
    final schemaV2 = await verifier.schemaAt(2);
    schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    schemaV2.rawDatabase.execute('''
      INSERT INTO cliente (
        id, codigo, razon_social, nombre_comercial, rfc, estatus,
        fecha_alta, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'cliente-existente', 'CLI-000001', 'Cliente Real S.A. de C.V.', 'Cliente Real',
        'CRE010101AA1', 'activo', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaV2.newConnection());

    await expectLater(verifier.migrateAndValidate(db, 4), throwsStateError);

    await db.close();
  });
}
