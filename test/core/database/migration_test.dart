import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_data.dart';

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
const _currentSchemaVersion = 5;

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

  test('migración 1 → 5 directa crea EntidadFiscal y Direccion ya con la forma nueva', () async {
    final schemaV1 = await verifier.schemaAt(1);
    schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, 5);

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
}
