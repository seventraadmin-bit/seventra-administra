import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_data.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';

import '../../generated_migrations/schema.dart';

/// `AppDatabase.schemaVersion` actual — único lugar que hay que tocar
/// cuando suba. Las pruebas que empiezan en `schemaAt(1)` y dependen de
/// `_createEtapa4ATables` (el camino `from == 1` de `onUpgrade`)
/// **deben** apuntar aquí, nunca a un número de versión intermedio
/// fijo: `_createEtapa4ATables` siempre construye con la forma *actual*
/// de las clases Dart, sin importar el objetivo nominal que
/// `SchemaVerifier.migrateAndValidate` reciba — apuntar a una versión
/// vieja (p. ej. 4, cuando la actual ya es 5) produce una comparación
/// de esquema que no puede coincidir nunca. Ya mordió dos veces
/// (Etapas 4E.1 y 4E.2); de aquí en adelante, súbelo junto con
/// `schemaVersion` en el mismo cambio.
const _currentSchemaVersion = 8;

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
    // actual — no puede validarse contra un objetivo intermedio fijo
    // porque `_createEtapa4ATables` siempre crea las tablas con la
    // forma *actual* de sus clases Dart, sin importar el objetivo
    // nominal de la migración (ver `_currentSchemaVersion`).
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

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
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

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
    expect(codigosSecuencia, hasLength(8));

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
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

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
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

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

  test('migración 1 → versión actual crea Cliente/Contacto ya con la forma nueva', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

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

  test('migración 2 → versión actual con Cliente/Contacto vacíos no falla y deja la forma nueva', () async {
    final schemaV2 = await verifier.schemaAt(2);
    schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV2.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Prueba S.A.'),
        );
    final contacto = await db.into(db.contacto).insertReturning(
          ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Juan Pérez', tipo: 'comercial'),
        );
    expect(contacto.tipo, 'comercial');

    await db.close();
  });

  test('migración 3 → versión actual con Cliente/Contacto vacíos no falla y deja la forma nueva', () async {
    final schemaV3 = await verifier.schemaAt(3);
    schemaV3.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV3.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Prueba S.A.'),
        );
    expect(cliente.nombreComercial, 'Prueba S.A.');

    await db.close();
  });

  test('migración 2 → versión actual falla explícitamente si Cliente ya tiene filas reales', () async {
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

    await expectLater(verifier.migrateAndValidate(db, _currentSchemaVersion), throwsStateError);

    await db.close();
  });

  test('5.json coincide con el esquema final de la Etapa 4E.2', () async {
    final schema = await verifier.schemaAt(5);
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
        'contacto', 'servicio', 'ubicacion', 'puesto', 'entidad_fiscal',
      ]),
    );

    final columnasDireccion = schema.rawDatabase
        .select('PRAGMA table_info(direccion)')
        .map((row) => row['name'] as String)
        .toSet();
    expect(columnasDireccion, contains('entidad_fiscal_id'));

    // Inventario completo del arco exclusivo — no solo que exista la
    // columna nueva, sino que el CHECK/FK reales sigan presentes tal
    // cual, leyendo el SQL de creación real de la tabla.
    final sqlDireccion = schema.rawDatabase
        .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'direccion'")
        .single['sql'] as String;
    expect(sqlDireccion, contains('FOREIGN KEY (empresa_id) REFERENCES empresa (id)'));
    expect(sqlDireccion, contains('FOREIGN KEY (sucursal_id) REFERENCES sucursal (id)'));
    expect(sqlDireccion, contains('FOREIGN KEY (cliente_id) REFERENCES cliente (id)'));
    expect(sqlDireccion, contains('FOREIGN KEY (servicio_id) REFERENCES servicio (id)'));
    expect(sqlDireccion, contains('FOREIGN KEY (entidad_fiscal_id) REFERENCES entidad_fiscal (id)'));
    expect(
      sqlDireccion,
      contains(
        'CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
        'CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END + '
        'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
        'CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END + '
        'CASE WHEN entidad_fiscal_id IS NOT NULL THEN 1 ELSE 0 END',
      ),
    );
    expect(sqlDireccion, contains("empresa_id IS NULL OR tipo_direccion = 'fiscal'"));
    expect(sqlDireccion, contains("servicio_id IS NULL OR tipo_direccion = 'operativa'"));
    expect(sqlDireccion, contains("sucursal_id IS NULL OR tipo_direccion IN ('administrativa', 'operativa')"));
    expect(sqlDireccion, contains("entidad_fiscal_id IS NULL OR tipo_direccion = 'fiscal'"));

    final indices = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'direccion'")
        .map((row) => row['name'] as String)
        .toSet();
    // Los dos índices explícitos ya existentes deben seguir presentes —
    // ninguno depende de entidadFiscalId, pero se pierden si la
    // migración recrea la tabla sin volver a crearlos.
    expect(indices, contains('idx_direccion_cliente_tipo_principal'));
    expect(indices, contains('idx_direccion_cliente'));
    // empresa_id/sucursal_id/servicio_id/entidad_fiscal_id son únicos
    // vía UNIQUE inline (parte del CREATE TABLE, sin índice nombrado
    // propio) — se confirma en el texto del CREATE TABLE mismo.
    expect(sqlDireccion, contains('"empresa_id" TEXT NULL UNIQUE'));
    expect(sqlDireccion, contains('"sucursal_id" TEXT NULL UNIQUE'));
    expect(sqlDireccion, contains('"servicio_id" TEXT NULL UNIQUE'));
    expect(sqlDireccion, contains('"entidad_fiscal_id" TEXT NULL UNIQUE'));

    schema.rawDatabase.dispose();
  });

  test('migración 1 → versión actual crea EntidadFiscal y Direccion ya con la forma nueva', () async {
    // Retargeted de un literal `5` a `_currentSchemaVersion`: el camino
    // `from == 1` (`_createEtapa4ATables`) siempre construye con la
    // forma *actual* de las clases Dart (ver la nota de
    // `_currentSchemaVersion` al inicio del archivo) — apuntar a un
    // número fijo se rompió en cuanto `Servicio.sucursalAdministrativaId`
    // cambió de forma en la Etapa 4F.1, exactamente la clase de bug que
    // ya mordió dos veces antes.
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Prueba S.A.'),
        );
    final entidad = await db.into(db.entidadFiscal).insertReturning(
          EntidadFiscalCompanion.insert(
            codigo: 'ENF-000001',
            clienteId: cliente.id,
            razonSocial: 'Prueba S.A. de C.V.',
            rfc: 'PRU010101AA1',
          ),
        );
    expect(entidad.cicloVidaRegistro, 'activo');

    await db.close();
  });

  /// Simula una instalación real llegada a [schemaVersionOrigen] con
  /// Direcciones reales de Empresa y Sucursal ya capturadas (como
  /// tendría la base real tras las Etapas 4B/4C) y confirma que la
  /// migración a 5 las conserva exactas — no solo en conteo, también en
  /// contenido — y dispara los mismos `foreign_key_check`/
  /// `integrity_check` que exige la migración real.
  Future<void> verificarDireccionesSobreviven(int schemaVersionOrigen) async {
    final schemaOrigen = await verifier.schemaAt(schemaVersionOrigen);
    schemaOrigen.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    schemaOrigen.rawDatabase.execute('''
      INSERT INTO empresa (id, codigo, nombre_comercial, created_at, updated_at, ciclo_vida_registro)
      VALUES ('empresa-real', 'RSG-01', 'Seguridad Privada RISEG', 1700000000, 1700000000, 'activo');
    ''');
    schemaOrigen.rawDatabase.execute('''
      INSERT INTO tipo_sucursal (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-sucursal-fijo', 'BASE_OPERATIVA', 'Base Operativa', 1700000000, 1700000000);
    ''');
    schemaOrigen.rawDatabase.execute('''
      INSERT INTO sucursal (id, codigo, nombre, tipo_sucursal_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('sucursal-real', 'SUC-0001', 'Sucursal Norte', 'tipo-sucursal-fijo', 1700000000, 1700000000, 'activo');
    ''');
    schemaOrigen.rawDatabase.execute('''
      INSERT INTO direccion (
        id, empresa_id, tipo_direccion, es_principal, calle, numero_exterior, colonia,
        municipio_alcaldia, estado, codigo_postal, pais, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'direccion-empresa', 'empresa-real', 'fiscal', 1, 'Av. Reforma', '100', 'Juárez',
        'Cuauhtémoc', 'CDMX', '06600', 'México', 1700000000, 1700000000, 'activo'
      );
    ''');
    schemaOrigen.rawDatabase.execute('''
      INSERT INTO direccion (
        id, sucursal_id, tipo_direccion, es_principal, calle, numero_exterior, colonia,
        municipio_alcaldia, estado, codigo_postal, pais, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'direccion-sucursal', 'sucursal-real', 'administrativa', 1, 'Av. Insurgentes', '200', 'Roma',
        'Cuauhtémoc', 'CDMX', '06700', 'México', 1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaOrigen.newConnection());
    await verifier.migrateAndValidate(db, 5);

    final direcciones = await db.select(db.direccion).get();
    expect(direcciones, hasLength(2), reason: 'ninguna Dirección real debe perderse en la migración');

    final direccionEmpresa = direcciones.firstWhere((d) => d.empresaId == 'empresa-real');
    expect(direccionEmpresa.calle, 'Av. Reforma');
    expect(direccionEmpresa.tipoDireccion, 'fiscal');
    expect(direccionEmpresa.entidadFiscalId, isNull);
    expect(direccionEmpresa.sucursalId, isNull);
    expect(direccionEmpresa.clienteId, isNull);
    expect(direccionEmpresa.servicioId, isNull);

    final direccionSucursal = direcciones.firstWhere((d) => d.sucursalId == 'sucursal-real');
    expect(direccionSucursal.calle, 'Av. Insurgentes');
    expect(direccionSucursal.tipoDireccion, 'administrativa');
    expect(direccionSucursal.entidadFiscalId, isNull);

    // Los mismos chequeos que exige la migración real, repetidos aquí
    // como aserción explícita (no solo confiar en que la migración no
    // haya lanzado — se verifica el estado final directamente).
    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

    final integridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

    await db.close();
  }

  test('migración 2 → 5 conserva las Direcciones reales de Empresa y Sucursal', () async {
    await verificarDireccionesSobreviven(2);
  });

  test('migración 3 → 5 conserva las Direcciones reales de Empresa y Sucursal', () async {
    await verificarDireccionesSobreviven(3);
  });

  test('migración 4 → 5 conserva las Direcciones reales de Empresa y Sucursal', () async {
    await verificarDireccionesSobreviven(4);
  });

  test('migración 4 → 5 configura CodigoSecuencia(entidad_fiscal) y la primera Entidad fiscal obtiene ENF-0001', () async {
    final schemaV4 = await verifier.schemaAt(4);
    schemaV4.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV4.newConnection());
    await verifier.migrateAndValidate(db, 5);

    final codigoEntidadFiscal =
        await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('entidad_fiscal'))).getSingle();
    expect(codigoEntidadFiscal.prefijo, 'ENF');
    expect(codigoEntidadFiscal.digitos, 4);
    expect(codigoEntidadFiscal.contadorActual, 0);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final generador = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final codigoResult = await generador.ejecutar('entidad_fiscal');
    final codigo = codigoResult.when(ok: (c) => c, failure: (f) => throw StateError(f.message));
    expect(codigo, 'ENF-0001');

    await db.into(db.entidadFiscal).insertReturning(
          EntidadFiscalCompanion.insert(codigo: codigo, clienteId: cliente.id, razonSocial: 'Sportium Club Uno', rfc: 'SCU010101AA1'),
        );

    await db.close();
  });

  test('el arco exclusivo de Direccion rechaza cero dueños tras la migración', () async {
    final schemaV4 = await verifier.schemaAt(4);
    final db = AppDatabase(schemaV4.newConnection());
    await verifier.migrateAndValidate(db, 5);

    expect(
      () => db.customStatement('''
        INSERT INTO direccion (
          id, tipo_direccion, es_principal, calle, numero_exterior, colonia,
          municipio_alcaldia, estado, codigo_postal, pais, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'direccion-sin-dueno', 'otra', 1, 'Calle', '1', 'Colonia',
          'Municipio', 'Estado', '00000', 'México', 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test('el arco exclusivo de Direccion rechaza más de un dueño tras la migración', () async {
    final schemaV4 = await verifier.schemaAt(4);
    final db = AppDatabase(schemaV4.newConnection());
    await verifier.migrateAndValidate(db, 5);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final entidad = await db.into(db.entidadFiscal).insertReturning(
          EntidadFiscalCompanion.insert(codigo: 'ENF-0001', clienteId: cliente.id, razonSocial: 'Sportium', rfc: 'SPO010101AA1'),
        );

    expect(
      () => db.customStatement('''
        INSERT INTO direccion (
          id, cliente_id, entidad_fiscal_id, tipo_direccion, es_principal, calle, numero_exterior, colonia,
          municipio_alcaldia, estado, codigo_postal, pais, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'direccion-dos-duenos', '${cliente.id}', '${entidad.id}', 'fiscal', 1, 'Calle', '1', 'Colonia',
          'Municipio', 'Estado', '00000', 'México', 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test('Direccion rechaza una Entidad fiscal con tipo distinto de fiscal tras la migración', () async {
    final schemaV4 = await verifier.schemaAt(4);
    final db = AppDatabase(schemaV4.newConnection());
    await verifier.migrateAndValidate(db, 5);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final entidad = await db.into(db.entidadFiscal).insertReturning(
          EntidadFiscalCompanion.insert(codigo: 'ENF-0001', clienteId: cliente.id, razonSocial: 'Sportium', rfc: 'SPO010101AA1'),
        );

    expect(
      () => db.customStatement('''
        INSERT INTO direccion (
          id, entidad_fiscal_id, tipo_direccion, es_principal, calle, numero_exterior, colonia,
          municipio_alcaldia, estado, codigo_postal, pais, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'direccion-tipo-incorrecto', '${entidad.id}', 'otra', 1, 'Calle', '1', 'Colonia',
          'Municipio', 'Estado', '00000', 'México', 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test('6.json coincide con el esquema final de la Etapa 4F.1 (Servicio con sucursalAdministrativaId nullable)', () async {
    final schema = await verifier.schemaAt(6);
    final tablas = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toSet();

    // Sin tablas nuevas — 4F.1 solo recrea Servicio, no agrega entidades.
    expect(
      tablas,
      containsAll(<String>[
        'app_metadata', 'codigo_secuencia', 'tipo_sucursal', 'industria',
        'tipo_servicio', 'area', 'direccion', 'medio_contacto', 'attachment',
        'horario', 'horario_detalle', 'empresa', 'sucursal', 'cliente',
        'contacto', 'servicio', 'ubicacion', 'puesto', 'entidad_fiscal',
      ]),
    );

    final columnasServicio = schema.rawDatabase
        .select('PRAGMA table_info(servicio)')
        .toList();
    final sucursalAdministrativaId =
        columnasServicio.firstWhere((c) => c['name'] == 'sucursal_administrativa_id');
    expect(sucursalAdministrativaId['notnull'], 0, reason: 'debe volverse nullable en la Etapa 4F.1');

    // Inventario completo: el resto de columnas/FKs/CHECK de Servicio
    // deben seguir presentes tal cual, leyendo el SQL de creación real.
    // Servicio declara sus FKs con el DSL tipado `.references()` (no
    // `customConstraints` como Direccion), así que Drift las renderiza
    // como `REFERENCES` en línea sobre la propia columna, no como una
    // cláusula `FOREIGN KEY (...) REFERENCES ...` separada.
    final sqlServicio = schema.rawDatabase
        .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio'")
        .single['sql'] as String;
    expect(sqlServicio, contains('"cliente_id" TEXT NOT NULL REFERENCES cliente (id) ON DELETE RESTRICT'));
    expect(sqlServicio, contains('"tipo_servicio_id" TEXT NOT NULL REFERENCES tipo_servicio (id)'));
    expect(sqlServicio, contains('"sucursal_administrativa_id" TEXT NULL REFERENCES sucursal (id) ON DELETE RESTRICT'));
    expect(
      sqlServicio,
      contains('"responsable_cliente_contacto_id" TEXT NULL REFERENCES contacto (id) ON DELETE RESTRICT'),
    );
    expect(sqlServicio, contains('CHECK (elementos_autorizados >= 0)'));
    expect(sqlServicio, contains('CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)'));
    expect(sqlServicio, contains('"codigo" TEXT NOT NULL UNIQUE'));

    schema.rawDatabase.dispose();
  });

  test('migración 1 → versión actual crea Servicio ya con sucursalAdministrativaId nullable', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    expect(servicio.sucursalAdministrativaId, isNull);

    await db.close();
  });

  /// Simula una instalación real llegada a [schemaVersionOrigen] con un
  /// Servicio real ya capturado (incluyendo Sucursal administrativa, tal
  /// como exigía la forma anterior) y con Dirección/Ubicación raíz/
  /// Horario reales enganchados a él — confirma que la migración a 6 los
  /// conserva exactos, no solo en conteo, y dispara los mismos
  /// `foreign_key_check`/`integrity_check` que exige la migración real.
  ///
  /// Solo se invoca con origen 4 o 5 (Cliente ya en su forma final desde
  /// la Etapa 4E.1) — un Cliente real en origen 2 o 3 ya es rechazado
  /// antes, por `migrarClienteContactoV4`, sin relación con Servicio
  /// (ver la prueba "migración 2 → versión actual falla explícitamente
  /// si Cliente ya tiene filas reales").
  Future<void> verificarServicioYRelacionesSobreviven(int schemaVersionOrigen) async {
    final schemaOrigen = await verifier.schemaAt(schemaVersionOrigen);
    final raw = schemaOrigen.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');

    raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-real', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO tipo_sucursal (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-sucursal-real', 'BASE_OPERATIVA', 'Base Operativa', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO sucursal (id, codigo, nombre, tipo_sucursal_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('sucursal-real', 'SUC-0001', 'Sucursal Norte', 'tipo-sucursal-real', 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, sucursal_administrativa_id,
        estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-real', 'SER-000001', 'cliente-real', 'Vigilancia Sportium Toluca', 'tipo-servicio-real',
        'sucursal-real', 'activo', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute('''
      INSERT INTO direccion (
        id, servicio_id, tipo_direccion, es_principal, calle, numero_exterior, colonia,
        municipio_alcaldia, estado, codigo_postal, pais, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'direccion-servicio', 'servicio-real', 'operativa', 1, 'Av. Toluca', '50', 'Centro',
        'Toluca', 'Estado de México', '50000', 'México', 1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute('''
      INSERT INTO ubicacion (id, codigo, nombre, tipo_ubicacion, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('ubicacion-raiz-servicio', 'UBI-000001', 'Vigilancia Sportium Toluca', 'servicio', 'servicio-real', 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO horario (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('horario-servicio', 'servicio-real', 1700000000, 1700000000, 'activo');
    ''');

    final db = AppDatabase(schemaOrigen.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final servicios = await db.select(db.servicio).get();
    expect(servicios, hasLength(1), reason: 'ningún Servicio real debe perderse en la migración');
    final servicio = servicios.single;
    expect(servicio.id, 'servicio-real');
    expect(servicio.codigo, 'SER-000001');
    expect(servicio.nombre, 'Vigilancia Sportium Toluca');
    expect(servicio.sucursalAdministrativaId, 'sucursal-real', reason: 'el valor existente se conserva, no se limpia');
    expect(servicio.estatus, 'activo');

    final direcciones = await db.select(db.direccion).get();
    final direccionServicio = direcciones.where((d) => d.servicioId == 'servicio-real');
    expect(direccionServicio, hasLength(1), reason: 'la Dirección operativa del Servicio debe sobrevivir');
    expect(direccionServicio.single.calle, 'Av. Toluca');

    final ubicaciones = await db.select(db.ubicacion).get();
    final raizServicio = ubicaciones.where((u) => u.servicioId == 'servicio-real');
    expect(raizServicio, hasLength(1), reason: 'la Ubicación raíz del Servicio debe sobrevivir, sin duplicarse');
    expect(raizServicio.single.parentId, isNull);

    final horarios = await db.select(db.horario).get();
    final horarioServicio = horarios.where((h) => h.servicioId == 'servicio-real');
    expect(horarioServicio, hasLength(1), reason: 'el Horario del Servicio debe sobrevivir');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

    final integridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

    await db.close();
  }

  // Nota: no se prueba "Servicio real sobrevive" desde el origen 2 o 3
  // con datos reales — un Servicio real exige un Cliente real (FK), y
  // `migrarClienteContactoV4` ya rechaza explícitamente cualquier
  // Cliente no vacío en esos orígenes (ver la prueba "migración 2 →
  // versión actual falla explícitamente si Cliente ya tiene filas
  // reales" más arriba). Una instalación real en 2/3 con un Servicio
  // real ya habría sido bloqueada por esa migración anterior, sin
  // relación con la de Servicio — probar lo contrario aquí probaría un
  // escenario que no puede ocurrir. Se cubre en cambio la ruta vacía.
  test('migración 2 → 6 con Servicio vacío completa sin error y permite crear uno nuevo', () async {
    final schemaV2 = await verifier.schemaAt(2);
    schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV2.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    expect(servicio.sucursalAdministrativaId, isNull);

    await db.close();
  });

  test('migración 3 → 6 con Servicio vacío completa sin error y permite crear uno nuevo', () async {
    final schemaV3 = await verifier.schemaAt(3);
    schemaV3.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV3.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    expect(servicio.sucursalAdministrativaId, isNull);

    await db.close();
  });

  test('migración 4 → 6 conserva el Servicio real y sus relaciones (Dirección/Ubicación/Horario)', () async {
    await verificarServicioYRelacionesSobreviven(4);
  });

  test('migración 5 → 6 conserva el Servicio real y sus relaciones (Dirección/Ubicación/Horario)', () async {
    await verificarServicioYRelacionesSobreviven(5);
  });

  test('acepta un Servicio sin Sucursal administrativa tras la migración', () async {
    final schemaV5 = await verifier.schemaAt(5);
    final db = AppDatabase(schemaV5.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Construcciones Habitacionales'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Mirabilia',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    expect(servicio.sucursalAdministrativaId, isNull);

    await db.close();
  });

  test('rechaza un Servicio con Cliente inexistente tras la migración', () async {
    final schemaV5 = await verifier.schemaAt(5);
    final db = AppDatabase(schemaV5.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    expect(
      () => db.customStatement('''
        INSERT INTO servicio (
          id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'servicio-invalido', 'SER-000001', 'cliente-inexistente', 'Servicio inválido',
          '${SeedIds.tipoServicioVigilanciaFija}', 'cotizado', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test('rechaza un Servicio con TipoServicio o Sucursal administrativa inexistentes tras la migración', () async {
    final schemaV5 = await verifier.schemaAt(5);
    final db = AppDatabase(schemaV5.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );

    expect(
      () => db.customStatement('''
        INSERT INTO servicio (
          id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'servicio-tipo-invalido', 'SER-000001', '${cliente.id}', 'Servicio inválido',
          'tipo-servicio-inexistente', 'cotizado', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    expect(
      () => db.customStatement('''
        INSERT INTO servicio (
          id, codigo, cliente_id, nombre, tipo_servicio_id, sucursal_administrativa_id, estatus, fecha_inicio,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'servicio-sucursal-invalida', 'SER-000002', '${cliente.id}', 'Servicio inválido',
          '${SeedIds.tipoServicioVigilanciaFija}', 'sucursal-inexistente', 'cotizado', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test('7.json coincide con el esquema final de la Etapa 4F.2 (columnas nuevas de Servicio, todas nullable)', () async {
    final schema = await verifier.schemaAt(7);
    final tablas = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toSet();

    // Sin tablas nuevas — 4F.2 solo agrega columnas a Servicio.
    expect(
      tablas,
      containsAll(<String>[
        'app_metadata', 'codigo_secuencia', 'tipo_sucursal', 'industria',
        'tipo_servicio', 'area', 'direccion', 'medio_contacto', 'attachment',
        'horario', 'horario_detalle', 'empresa', 'sucursal', 'cliente',
        'contacto', 'servicio', 'ubicacion', 'puesto', 'entidad_fiscal',
      ]),
    );

    final columnasServicio = await Future.wait(
      ['entidad_fiscal_id', 'responsable_interno', 'referencia_comercial', 'referencia_contractual'].map(
        (nombre) async {
          final columnas = schema.rawDatabase.select('PRAGMA table_info(servicio)');
          return columnas.firstWhere((c) => c['name'] == nombre);
        },
      ),
    );
    for (final columna in columnasServicio) {
      expect(columna['notnull'], 0, reason: '${columna['name']} debe ser nullable');
    }

    final sqlServicio = schema.rawDatabase
        .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio'")
        .single['sql'] as String;
    expect(sqlServicio, contains('"entidad_fiscal_id" TEXT NULL REFERENCES entidad_fiscal (id) ON DELETE RESTRICT'));
    expect(sqlServicio, contains('"responsable_interno" TEXT NULL'));
    expect(sqlServicio, contains('"referencia_comercial" TEXT NULL'));
    expect(sqlServicio, contains('"referencia_contractual" TEXT NULL'));
    // Las columnas/FKs/CHECK ya existentes desde la Etapa 4F.1 siguen
    // intactas — una migración aditiva nunca debería tocarlas.
    expect(sqlServicio, contains('"sucursal_administrativa_id" TEXT NULL REFERENCES sucursal (id) ON DELETE RESTRICT'));
    expect(sqlServicio, contains('CHECK (elementos_autorizados >= 0)'));

    schema.rawDatabase.dispose();
  });

  test('migración 1 → versión actual crea Servicio ya con las columnas de la Etapa 4F.2', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    expect(servicio.entidadFiscalId, isNull);
    expect(servicio.responsableInterno, isNull);
    expect(servicio.referenciaComercial, isNull);
    expect(servicio.referenciaContractual, isNull);

    await db.close();
  });

  test('migración 6 → 7 conserva un Servicio real existente, con las columnas nuevas en NULL', () async {
    final schemaV6 = await verifier.schemaAt(6);
    final raw = schemaV6.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-real', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-real', 'SER-000001', 'cliente-real', 'Vigilancia Sportium Toluca', 'tipo-servicio-real',
        'activo', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaV6.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final servicios = await db.select(db.servicio).get();
    expect(servicios, hasLength(1), reason: 'ningún Servicio real debe perderse en una migración aditiva');
    final servicio = servicios.single;
    expect(servicio.id, 'servicio-real');
    expect(servicio.entidadFiscalId, isNull);
    expect(servicio.responsableInterno, isNull);
    expect(servicio.referenciaComercial, isNull);
    expect(servicio.referenciaContractual, isNull);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

    final integridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

    await db.close();
  });

  test('acepta un Servicio con entidadFiscalId/responsableInterno/referencias tras la migración', () async {
    final schemaV6 = await verifier.schemaAt(6);
    final db = AppDatabase(schemaV6.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final entidad = await db.into(db.entidadFiscal).insertReturning(
          EntidadFiscalCompanion.insert(
            codigo: 'ENF-0001',
            clienteId: cliente.id,
            razonSocial: 'Sportium SA de CV',
            rfc: 'SPO010101AA1',
          ),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
            entidadFiscalId: Value(entidad.id),
            responsableInterno: const Value('Juan Pérez'),
            referenciaComercial: const Value('COT-2026-001'),
            referenciaContractual: const Value('CTR-2026-001'),
          ),
        );
    expect(servicio.entidadFiscalId, entidad.id);
    expect(servicio.responsableInterno, 'Juan Pérez');
    expect(servicio.referenciaComercial, 'COT-2026-001');
    expect(servicio.referenciaContractual, 'CTR-2026-001');

    await db.close();
  });

  test('rechaza un Servicio con entidadFiscalId inexistente tras la migración', () async {
    final schemaV6 = await verifier.schemaAt(6);
    final db = AppDatabase(schemaV6.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );

    expect(
      () => db.customStatement('''
        INSERT INTO servicio (
          id, codigo, cliente_id, nombre, tipo_servicio_id, entidad_fiscal_id, estatus, fecha_inicio,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'servicio-entidad-invalida', 'SER-000001', '${cliente.id}', 'Servicio inválido',
          '${SeedIds.tipoServicioVigilanciaFija}', 'entidad-fiscal-inexistente', 'cotizado', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test('8.json coincide con el esquema final de la Etapa 4G.1 (catálogo + líneas comerciales, tablas nuevas)', () async {
    final schema = await verifier.schemaAt(8);
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
        'contacto', 'servicio', 'ubicacion', 'puesto', 'entidad_fiscal',
        'tipo_modalidad_turno', 'servicio_linea_comercial', 'servicio_linea_comercial_vigencia',
      ]),
    );

    final sqlVigencia = schema.rawDatabase
        .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio_linea_comercial_vigencia'")
        .single['sql'] as String;
    expect(sqlVigencia, contains('REFERENCES puesto (id) ON DELETE RESTRICT'));
    expect(sqlVigencia, contains('REFERENCES tipo_modalidad_turno (id) ON DELETE RESTRICT'));
    expect(sqlVigencia, contains('REFERENCES servicio_linea_comercial (id) ON DELETE RESTRICT'));
    expect(sqlVigencia, contains('CHECK (cantidad_elementos > 0)'));
    expect(sqlVigencia, contains('CHECK (precio_unitario > 0)'));
    expect(sqlVigencia, contains('CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)'));

    schema.rawDatabase.dispose();
  });

  test('migración 1 → versión actual siembra las 7 modalidades de turno confirmadas', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final modalidades = await db.select(db.tipoModalidadTurno).get();
    expect(
      modalidades.map((m) => m.codigo).toSet(),
      {'24X24', '24X48', '12X12', 'NOCTURNO', 'DIURNO', 'MIXTO', 'PERSONALIZADO'},
    );

    await db.close();
  });

  test('migración 7 → 8 conserva un Servicio real existente y crea las tablas de Configuración comercial vacías', () async {
    final schemaV7 = await verifier.schemaAt(7);
    final raw = schemaV7.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-real', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-real', 'SER-000001', 'cliente-real', 'Vigilancia Sportium Toluca', 'tipo-servicio-real',
        'activo', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaV7.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final servicios = await db.select(db.servicio).get();
    expect(servicios, hasLength(1), reason: 'ningún Servicio real debe perderse en una migración aditiva');

    final lineas = await db.select(db.servicioLineaComercial).get();
    expect(lineas, isEmpty);
    final modalidades = await db.select(db.tipoModalidadTurno).get();
    expect(modalidades, hasLength(7));

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

    final integridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

    await db.close();
  });

  test('acepta una línea comercial con su primera vigencia tras la migración', () async {
    final schemaV7 = await verifier.schemaAt(7);
    final db = AppDatabase(schemaV7.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    final puesto = await db.into(db.puesto).insertReturning(
          PuestoCompanion.insert(
            codigo: 'PUE-0001',
            nombre: 'Guardia',
            areaId: SeedIds.areaOperaciones,
            tipo: 'operativo',
            nivelJerarquico: 5,
          ),
        );

    final linea = await db.into(db.servicioLineaComercial).insertReturning(
          ServicioLineaComercialCompanion.insert(servicioId: servicio.id),
        );
    final vigencia = await db.into(db.servicioLineaComercialVigencia).insertReturning(
          ServicioLineaComercialVigenciaCompanion.insert(
            lineaComercialId: linea.id,
            puestoId: puesto.id,
            modalidadTurnoId: SeedIds.modalidadTurno24x24,
            cantidadElementos: 2,
            precioUnitario: 1500000,
            tratamientoIva: 'noAplica',
            fechaInicioVigencia: DateTime(2026, 1, 1),
          ),
        );
    expect(vigencia.cantidadElementos, 2);
    expect(vigencia.precioUnitario, 1500000);

    await db.close();
  });

  test('rechaza una línea comercial con Puesto o modalidad de turno inexistentes tras la migración', () async {
    final schemaV7 = await verifier.schemaAt(7);
    final db = AppDatabase(schemaV7.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    final linea = await db.into(db.servicioLineaComercial).insertReturning(
          ServicioLineaComercialCompanion.insert(servicioId: servicio.id),
        );

    expect(
      () => db.customStatement('''
        INSERT INTO servicio_linea_comercial_vigencia (
          id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
          tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'vigencia-puesto-invalido', '${linea.id}', 'puesto-inexistente', '${SeedIds.modalidadTurno24x24}',
          2, 1500000, 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    expect(
      () => db.customStatement('''
        INSERT INTO servicio_linea_comercial_vigencia (
          id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
          tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'vigencia-turno-invalido', '${linea.id}', '${SeedIds.areaOperaciones}', 'modalidad-inexistente',
          2, 1500000, 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });
}
