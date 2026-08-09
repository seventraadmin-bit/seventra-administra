import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/migrations/migrar_cuenta_por_cobrar_v14.dart';
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
const _currentSchemaVersion = 17;

/// Verifica la migración real 1 → 2 sobre una base física construida
/// desde el snapshot de schemaVersion 1 (`drift_schemas/riseg_one/`) —
/// no una prueba manual de `onUpgrade`, sino la migración generada
/// corriendo contra el esquema histórico real.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    '1.json representa exactamente el schemaVersion 1 actual (solo AppMetadata)',
    () async {
      final schema = await verifier.schemaAt(1);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toList();

      expect(tablas, contains('app_metadata'));
      // Ninguna tabla de la Etapa 4A debe existir todavía en v1.
      expect(tablas, isNot(contains('empresa')));
      expect(tablas, isNot(contains('cliente')));
      schema.rawDatabase.dispose();
    },
  );

  test('2.json coincide con el esquema final de la Etapa 4A', () async {
    final schema = await verifier.schemaAt(2);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();

    expect(
      tablas,
      containsAll(<String>[
        'app_metadata',
        'codigo_secuencia',
        'tipo_sucursal',
        'industria',
        'tipo_servicio',
        'area',
        'direccion',
        'medio_contacto',
        'attachment',
        'horario',
        'horario_detalle',
        'empresa',
        'sucursal',
        'cliente',
        'contacto',
        'servicio',
        'ubicacion',
        'puesto',
      ]),
    );
    schema.rawDatabase.dispose();
  });

  test(
    'migración 1 → versión actual conserva AppMetadata original y aplica la siembra',
    () async {
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
    },
  );

  test(
    'runSeed es idempotente: llamarlo varias veces no duplica filas',
    () async {
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
      expect(codigosSecuencia, hasLength(12));

      await db.close();
    },
  );

  test(
    '3.json coincide con el esquema final de la Etapa 4D (mismas tablas que 2, sin cambios estructurales)',
    () async {
      final schema = await verifier.schemaAt(3);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
        ]),
      );
      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual siembra las Áreas ya con el formato definitivo',
    () async {
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
        'ARE-0001',
        'ARE-0002',
        'ARE-0003',
        'ARE-0004',
        'ARE-0005',
        'ARE-0006',
      });

      final codigoArea =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('area'))).getSingle();
      expect(codigoArea.prefijo, 'ARE');
      expect(codigoArea.digitos, 4);
      expect(codigoArea.contadorActual, 6);
      expect(codigoArea.reseteaAnualmente, isFalse);

      await db.close();
    },
  );

  test(
    'migración 2 → versión actual convierte los códigos alfabéticos de Área existentes sin duplicar filas',
    () async {
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
        (
          '00000000-0000-4000-8000-000000000303',
          'ADMINISTRACION',
          'Administración',
        ),
        ('00000000-0000-4000-8000-000000000304', 'DIRECCION', 'Dirección'),
        ('00000000-0000-4000-8000-000000000305', 'MONITOREO', 'Monitoreo'),
        (
          '00000000-0000-4000-8000-000000000306',
          'RECLUTAMIENTO',
          'Reclutamiento',
        ),
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
      expect(
        areas,
        hasLength(6),
        reason: 'la migración no debe duplicar filas',
      );
      expect(areas.map((a) => a.codigo).toSet(), {
        'ARE-0001',
        'ARE-0002',
        'ARE-0003',
        'ARE-0004',
        'ARE-0005',
        'ARE-0006',
      });
      // Nombre/descripción/estado se conservan intactos — la migración
      // solo tocó `codigo`.
      final operaciones = areas.firstWhere((a) => a.codigo == 'ARE-0001');
      expect(operaciones.nombre, 'Operaciones');
      expect(operaciones.activo, isTrue);

      final codigoArea =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('area'))).getSingle();
      expect(codigoArea.contadorActual, 6);

      await db.close();
    },
  );

  test(
    '4.json coincide con el esquema final de la Etapa 4E.1 (sin tablas nuevas)',
    () async {
      final schema = await verifier.schemaAt(4);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
        ]),
      );

      final columnasCliente =
          schema.rawDatabase
              .select('PRAGMA table_info(cliente)')
              .map((row) => row['name'] as String)
              .toSet();
      expect(columnasCliente, isNot(contains('razon_social')));
      expect(columnasCliente, isNot(contains('rfc')));
      expect(columnasCliente, contains('nombre_comercial'));
      expect(columnasCliente, contains('industria_id'));

      final columnasContacto =
          schema.rawDatabase
              .select('PRAGMA table_info(contacto)')
              .map((row) => row['name'] as String)
              .toSet();
      expect(columnasContacto, contains('tipo'));

      final indices =
          schema.rawDatabase
              .select("SELECT name FROM sqlite_master WHERE type = 'index'")
              .map((row) => row['name'] as String)
              .toSet();
      expect(indices, contains('idx_contacto_cliente_tipo_principal_activo'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual crea Cliente/Contacto ya con la forma nueva',
    () async {
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
      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Prueba S.A.',
            ),
          );
      expect(cliente.nombreComercial, 'Prueba S.A.');

      await db.close();
    },
  );

  test(
    'migración 2 → versión actual con Cliente/Contacto vacíos no falla y deja la forma nueva',
    () async {
      final schemaV2 = await verifier.schemaAt(2);
      schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV2.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Prueba S.A.',
            ),
          );
      final contacto = await db
          .into(db.contacto)
          .insertReturning(
            ContactoCompanion.insert(
              clienteId: cliente.id,
              nombre: 'Juan Pérez',
              tipo: 'comercial',
            ),
          );
      expect(contacto.tipo, 'comercial');

      await db.close();
    },
  );

  test(
    'migración 3 → versión actual con Cliente/Contacto vacíos no falla y deja la forma nueva',
    () async {
      final schemaV3 = await verifier.schemaAt(3);
      schemaV3.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV3.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Prueba S.A.',
            ),
          );
      expect(cliente.nombreComercial, 'Prueba S.A.');

      await db.close();
    },
  );

  test(
    'migración 2 → versión actual falla explícitamente si Cliente ya tiene filas reales',
    () async {
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

      await expectLater(
        verifier.migrateAndValidate(db, _currentSchemaVersion),
        throwsStateError,
      );

      await db.close();
    },
  );

  test('5.json coincide con el esquema final de la Etapa 4E.2', () async {
    final schema = await verifier.schemaAt(5);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();

    expect(
      tablas,
      containsAll(<String>[
        'app_metadata',
        'codigo_secuencia',
        'tipo_sucursal',
        'industria',
        'tipo_servicio',
        'area',
        'direccion',
        'medio_contacto',
        'attachment',
        'horario',
        'horario_detalle',
        'empresa',
        'sucursal',
        'cliente',
        'contacto',
        'servicio',
        'ubicacion',
        'puesto',
        'entidad_fiscal',
      ]),
    );

    final columnasDireccion =
        schema.rawDatabase
            .select('PRAGMA table_info(direccion)')
            .map((row) => row['name'] as String)
            .toSet();
    expect(columnasDireccion, contains('entidad_fiscal_id'));

    // Inventario completo del arco exclusivo — no solo que exista la
    // columna nueva, sino que el CHECK/FK reales sigan presentes tal
    // cual, leyendo el SQL de creación real de la tabla.
    final sqlDireccion =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'direccion'",
                )
                .single['sql']
            as String;
    expect(
      sqlDireccion,
      contains('FOREIGN KEY (empresa_id) REFERENCES empresa (id)'),
    );
    expect(
      sqlDireccion,
      contains('FOREIGN KEY (sucursal_id) REFERENCES sucursal (id)'),
    );
    expect(
      sqlDireccion,
      contains('FOREIGN KEY (cliente_id) REFERENCES cliente (id)'),
    );
    expect(
      sqlDireccion,
      contains('FOREIGN KEY (servicio_id) REFERENCES servicio (id)'),
    );
    expect(
      sqlDireccion,
      contains(
        'FOREIGN KEY (entidad_fiscal_id) REFERENCES entidad_fiscal (id)',
      ),
    );
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
    expect(
      sqlDireccion,
      contains("empresa_id IS NULL OR tipo_direccion = 'fiscal'"),
    );
    expect(
      sqlDireccion,
      contains("servicio_id IS NULL OR tipo_direccion = 'operativa'"),
    );
    expect(
      sqlDireccion,
      contains(
        "sucursal_id IS NULL OR tipo_direccion IN ('administrativa', 'operativa')",
      ),
    );
    expect(
      sqlDireccion,
      contains("entidad_fiscal_id IS NULL OR tipo_direccion = 'fiscal'"),
    );

    final indices =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'direccion'",
            )
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

  test(
    'migración 1 → versión actual crea EntidadFiscal y Direccion ya con la forma nueva',
    () async {
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

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Prueba S.A.',
            ),
          );
      final entidad = await db
          .into(db.entidadFiscal)
          .insertReturning(
            EntidadFiscalCompanion.insert(
              codigo: 'ENF-000001',
              clienteId: cliente.id,
              razonSocial: 'Prueba S.A. de C.V.',
              rfc: 'PRU010101AA1',
            ),
          );
      expect(entidad.cicloVidaRegistro, 'activo');

      await db.close();
    },
  );

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
    expect(
      direcciones,
      hasLength(2),
      reason: 'ninguna Dirección real debe perderse en la migración',
    );

    final direccionEmpresa = direcciones.firstWhere(
      (d) => d.empresaId == 'empresa-real',
    );
    expect(direccionEmpresa.calle, 'Av. Reforma');
    expect(direccionEmpresa.tipoDireccion, 'fiscal');
    expect(direccionEmpresa.entidadFiscalId, isNull);
    expect(direccionEmpresa.sucursalId, isNull);
    expect(direccionEmpresa.clienteId, isNull);
    expect(direccionEmpresa.servicioId, isNull);

    final direccionSucursal = direcciones.firstWhere(
      (d) => d.sucursalId == 'sucursal-real',
    );
    expect(direccionSucursal.calle, 'Av. Insurgentes');
    expect(direccionSucursal.tipoDireccion, 'administrativa');
    expect(direccionSucursal.entidadFiscalId, isNull);

    // Los mismos chequeos que exige la migración real, repetidos aquí
    // como aserción explícita (no solo confiar en que la migración no
    // haya lanzado — se verifica el estado final directamente).
    final violacionesFk =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(
      violacionesFk,
      isEmpty,
      reason: 'foreign_key_check debe quedar limpio tras la migración',
    );

    final integridad =
        await db
            .customSelect('PRAGMA integrity_check')
            .map((r) => r.data['integrity_check'] as String)
            .get();
    expect(integridad, [
      'ok',
    ], reason: 'integrity_check debe reportar "ok" tras la migración');

    await db.close();
  }

  test(
    'migración 2 → 5 conserva las Direcciones reales de Empresa y Sucursal',
    () async {
      await verificarDireccionesSobreviven(2);
    },
  );

  test(
    'migración 3 → 5 conserva las Direcciones reales de Empresa y Sucursal',
    () async {
      await verificarDireccionesSobreviven(3);
    },
  );

  test(
    'migración 4 → 5 conserva las Direcciones reales de Empresa y Sucursal',
    () async {
      await verificarDireccionesSobreviven(4);
    },
  );

  test(
    'migración 4 → 5 configura CodigoSecuencia(entidad_fiscal) y la primera Entidad fiscal obtiene ENF-0001',
    () async {
      final schemaV4 = await verifier.schemaAt(4);
      schemaV4.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV4.newConnection());
      await verifier.migrateAndValidate(db, 5);

      final codigoEntidadFiscal =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('entidad_fiscal'))).getSingle();
      expect(codigoEntidadFiscal.prefijo, 'ENF');
      expect(codigoEntidadFiscal.digitos, 4);
      expect(codigoEntidadFiscal.contadorActual, 0);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final generador = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final codigoResult = await generador.ejecutar('entidad_fiscal');
      final codigo = codigoResult.when(
        ok: (c) => c,
        failure: (f) => throw StateError(f.message),
      );
      expect(codigo, 'ENF-0001');

      await db
          .into(db.entidadFiscal)
          .insertReturning(
            EntidadFiscalCompanion.insert(
              codigo: codigo,
              clienteId: cliente.id,
              razonSocial: 'Sportium Club Uno',
              rfc: 'SCU010101AA1',
            ),
          );

      await db.close();
    },
  );

  test(
    'el arco exclusivo de Direccion rechaza cero dueños tras la migración',
    () async {
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
    },
  );

  test(
    'el arco exclusivo de Direccion rechaza más de un dueño tras la migración',
    () async {
      final schemaV4 = await verifier.schemaAt(4);
      final db = AppDatabase(schemaV4.newConnection());
      await verifier.migrateAndValidate(db, 5);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final entidad = await db
          .into(db.entidadFiscal)
          .insertReturning(
            EntidadFiscalCompanion.insert(
              codigo: 'ENF-0001',
              clienteId: cliente.id,
              razonSocial: 'Sportium',
              rfc: 'SPO010101AA1',
            ),
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
    },
  );

  test(
    'Direccion rechaza una Entidad fiscal con tipo distinto de fiscal tras la migración',
    () async {
      final schemaV4 = await verifier.schemaAt(4);
      final db = AppDatabase(schemaV4.newConnection());
      await verifier.migrateAndValidate(db, 5);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final entidad = await db
          .into(db.entidadFiscal)
          .insertReturning(
            EntidadFiscalCompanion.insert(
              codigo: 'ENF-0001',
              clienteId: cliente.id,
              razonSocial: 'Sportium',
              rfc: 'SPO010101AA1',
            ),
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
    },
  );

  test(
    '6.json coincide con el esquema final de la Etapa 4F.1 (Servicio con sucursalAdministrativaId nullable)',
    () async {
      final schema = await verifier.schemaAt(6);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      // Sin tablas nuevas — 4F.1 solo recrea Servicio, no agrega entidades.
      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
          'entidad_fiscal',
        ]),
      );

      final columnasServicio =
          schema.rawDatabase.select('PRAGMA table_info(servicio)').toList();
      final sucursalAdministrativaId = columnasServicio.firstWhere(
        (c) => c['name'] == 'sucursal_administrativa_id',
      );
      expect(
        sucursalAdministrativaId['notnull'],
        0,
        reason: 'debe volverse nullable en la Etapa 4F.1',
      );

      // Inventario completo: el resto de columnas/FKs/CHECK de Servicio
      // deben seguir presentes tal cual, leyendo el SQL de creación real.
      // Servicio declara sus FKs con el DSL tipado `.references()` (no
      // `customConstraints` como Direccion), así que Drift las renderiza
      // como `REFERENCES` en línea sobre la propia columna, no como una
      // cláusula `FOREIGN KEY (...) REFERENCES ...` separada.
      final sqlServicio =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlServicio,
        contains(
          '"cliente_id" TEXT NOT NULL REFERENCES cliente (id) ON DELETE RESTRICT',
        ),
      );
      expect(
        sqlServicio,
        contains(
          '"tipo_servicio_id" TEXT NOT NULL REFERENCES tipo_servicio (id)',
        ),
      );
      expect(
        sqlServicio,
        contains(
          '"sucursal_administrativa_id" TEXT NULL REFERENCES sucursal (id) ON DELETE RESTRICT',
        ),
      );
      expect(
        sqlServicio,
        contains(
          '"responsable_cliente_contacto_id" TEXT NULL REFERENCES contacto (id) ON DELETE RESTRICT',
        ),
      );
      expect(sqlServicio, contains('CHECK (elementos_autorizados >= 0)'));
      expect(
        sqlServicio,
        contains(
          'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
        ),
      );
      expect(sqlServicio, contains('"codigo" TEXT NOT NULL UNIQUE'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual crea Servicio ya con sucursalAdministrativaId nullable',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
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
    },
  );

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
  Future<void> verificarServicioYRelacionesSobreviven(
    int schemaVersionOrigen,
  ) async {
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
    expect(
      servicios,
      hasLength(1),
      reason: 'ningún Servicio real debe perderse en la migración',
    );
    final servicio = servicios.single;
    expect(servicio.id, 'servicio-real');
    expect(servicio.codigo, 'SER-000001');
    expect(servicio.nombre, 'Vigilancia Sportium Toluca');
    expect(
      servicio.sucursalAdministrativaId,
      'sucursal-real',
      reason: 'el valor existente se conserva, no se limpia',
    );
    expect(servicio.estatus, 'activo');

    final direcciones = await db.select(db.direccion).get();
    final direccionServicio = direcciones.where(
      (d) => d.servicioId == 'servicio-real',
    );
    expect(
      direccionServicio,
      hasLength(1),
      reason: 'la Dirección operativa del Servicio debe sobrevivir',
    );
    expect(direccionServicio.single.calle, 'Av. Toluca');

    final ubicaciones = await db.select(db.ubicacion).get();
    final raizServicio = ubicaciones.where(
      (u) => u.servicioId == 'servicio-real',
    );
    expect(
      raizServicio,
      hasLength(1),
      reason: 'la Ubicación raíz del Servicio debe sobrevivir, sin duplicarse',
    );
    expect(raizServicio.single.parentId, isNull);

    final horarios = await db.select(db.horario).get();
    final horarioServicio = horarios.where(
      (h) => h.servicioId == 'servicio-real',
    );
    expect(
      horarioServicio,
      hasLength(1),
      reason: 'el Horario del Servicio debe sobrevivir',
    );

    final violacionesFk =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(
      violacionesFk,
      isEmpty,
      reason: 'foreign_key_check debe quedar limpio tras la migración',
    );

    final integridad =
        await db
            .customSelect('PRAGMA integrity_check')
            .map((r) => r.data['integrity_check'] as String)
            .get();
    expect(integridad, [
      'ok',
    ], reason: 'integrity_check debe reportar "ok" tras la migración');

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
  test(
    'migración 2 → 6 con Servicio vacío completa sin error y permite crear uno nuevo',
    () async {
      final schemaV2 = await verifier.schemaAt(2);
      schemaV2.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV2.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
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
    },
  );

  test(
    'migración 3 → 6 con Servicio vacío completa sin error y permite crear uno nuevo',
    () async {
      final schemaV3 = await verifier.schemaAt(3);
      schemaV3.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV3.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
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
    },
  );

  test(
    'migración 4 → 6 conserva el Servicio real y sus relaciones (Dirección/Ubicación/Horario)',
    () async {
      await verificarServicioYRelacionesSobreviven(4);
    },
  );

  test(
    'migración 5 → 6 conserva el Servicio real y sus relaciones (Dirección/Ubicación/Horario)',
    () async {
      await verificarServicioYRelacionesSobreviven(5);
    },
  );

  test(
    'acepta un Servicio sin Sucursal administrativa tras la migración',
    () async {
      final schemaV5 = await verifier.schemaAt(5);
      final db = AppDatabase(schemaV5.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Construcciones Habitacionales',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
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
    },
  );

  test(
    'rechaza un Servicio con Cliente inexistente tras la migración',
    () async {
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
    },
  );

  test(
    'rechaza un Servicio con TipoServicio o Sucursal administrativa inexistentes tras la migración',
    () async {
      final schemaV5 = await verifier.schemaAt(5);
      final db = AppDatabase(schemaV5.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
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
    },
  );

  test(
    '7.json coincide con el esquema final de la Etapa 4F.2 (columnas nuevas de Servicio, todas nullable)',
    () async {
      final schema = await verifier.schemaAt(7);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      // Sin tablas nuevas — 4F.2 solo agrega columnas a Servicio.
      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
          'entidad_fiscal',
        ]),
      );

      final columnasServicio = await Future.wait(
        [
          'entidad_fiscal_id',
          'responsable_interno',
          'referencia_comercial',
          'referencia_contractual',
        ].map((nombre) async {
          final columnas = schema.rawDatabase.select(
            'PRAGMA table_info(servicio)',
          );
          return columnas.firstWhere((c) => c['name'] == nombre);
        }),
      );
      for (final columna in columnasServicio) {
        expect(
          columna['notnull'],
          0,
          reason: '${columna['name']} debe ser nullable',
        );
      }

      final sqlServicio =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlServicio,
        contains(
          '"entidad_fiscal_id" TEXT NULL REFERENCES entidad_fiscal (id) ON DELETE RESTRICT',
        ),
      );
      expect(sqlServicio, contains('"responsable_interno" TEXT NULL'));
      expect(sqlServicio, contains('"referencia_comercial" TEXT NULL'));
      expect(sqlServicio, contains('"referencia_contractual" TEXT NULL'));
      // Las columnas/FKs/CHECK ya existentes desde la Etapa 4F.1 siguen
      // intactas — una migración aditiva nunca debería tocarlas.
      expect(
        sqlServicio,
        contains(
          '"sucursal_administrativa_id" TEXT NULL REFERENCES sucursal (id) ON DELETE RESTRICT',
        ),
      );
      expect(sqlServicio, contains('CHECK (elementos_autorizados >= 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual crea Servicio ya con las columnas de la Etapa 4F.2',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
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
    },
  );

  test(
    'migración 6 → 7 conserva un Servicio real existente, con las columnas nuevas en NULL',
    () async {
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
      expect(
        servicios,
        hasLength(1),
        reason: 'ningún Servicio real debe perderse en una migración aditiva',
      );
      final servicio = servicios.single;
      expect(servicio.id, 'servicio-real');
      expect(servicio.entidadFiscalId, isNull);
      expect(servicio.responsableInterno, isNull);
      expect(servicio.referenciaComercial, isNull);
      expect(servicio.referenciaContractual, isNull);

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un Servicio con entidadFiscalId/responsableInterno/referencias tras la migración',
    () async {
      final schemaV6 = await verifier.schemaAt(6);
      final db = AppDatabase(schemaV6.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final entidad = await db
          .into(db.entidadFiscal)
          .insertReturning(
            EntidadFiscalCompanion.insert(
              codigo: 'ENF-0001',
              clienteId: cliente.id,
              razonSocial: 'Sportium SA de CV',
              rfc: 'SPO010101AA1',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
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
    },
  );

  test(
    'rechaza un Servicio con entidadFiscalId inexistente tras la migración',
    () async {
      final schemaV6 = await verifier.schemaAt(6);
      final db = AppDatabase(schemaV6.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
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
    },
  );

  test(
    '8.json coincide con el esquema final de la Etapa 4G.1 (catálogo + líneas comerciales, tablas nuevas)',
    () async {
      final schema = await verifier.schemaAt(8);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
          'entidad_fiscal',
          'tipo_modalidad_turno',
          'servicio_linea_comercial',
          'servicio_linea_comercial_vigencia',
        ]),
      );

      final sqlVigencia =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio_linea_comercial_vigencia'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlVigencia,
        contains('REFERENCES puesto (id) ON DELETE RESTRICT'),
      );
      expect(
        sqlVigencia,
        contains('REFERENCES tipo_modalidad_turno (id) ON DELETE RESTRICT'),
      );
      expect(
        sqlVigencia,
        contains('REFERENCES servicio_linea_comercial (id) ON DELETE RESTRICT'),
      );
      expect(sqlVigencia, contains('CHECK (cantidad_elementos > 0)'));
      expect(sqlVigencia, contains('CHECK (precio_unitario > 0)'));
      expect(
        sqlVigencia,
        contains(
          'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
        ),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual siembra las 7 modalidades de turno confirmadas',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final modalidades = await db.select(db.tipoModalidadTurno).get();
      expect(modalidades.map((m) => m.codigo).toSet(), {
        '24X24',
        '24X48',
        '12X12',
        'NOCTURNO',
        'DIURNO',
        'MIXTO',
        'PERSONALIZADO',
      });

      await db.close();
    },
  );

  test(
    'migración 7 → 8 conserva un Servicio real existente y crea las tablas de Configuración comercial vacías',
    () async {
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
      expect(
        servicios,
        hasLength(1),
        reason: 'ningún Servicio real debe perderse en una migración aditiva',
      );

      final lineas = await db.select(db.servicioLineaComercial).get();
      expect(lineas, isEmpty);
      final modalidades = await db.select(db.tipoModalidadTurno).get();
      expect(modalidades, hasLength(7));

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta una línea comercial con su primera vigencia tras la migración',
    () async {
      final schemaV7 = await verifier.schemaAt(7);
      final db = AppDatabase(schemaV7.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final puesto = await db
          .into(db.puesto)
          .insertReturning(
            PuestoCompanion.insert(
              codigo: 'PUE-0001',
              nombre: 'Guardia',
              areaId: SeedIds.areaOperaciones,
              tipo: 'operativo',
              nivelJerarquico: 5,
            ),
          );

      final linea = await db
          .into(db.servicioLineaComercial)
          .insertReturning(
            ServicioLineaComercialCompanion.insert(servicioId: servicio.id),
          );
      final vigencia = await db
          .into(db.servicioLineaComercialVigencia)
          .insertReturning(
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
    },
  );

  test(
    'rechaza una línea comercial con Puesto o modalidad de turno inexistentes tras la migración',
    () async {
      final schemaV7 = await verifier.schemaAt(7);
      final db = AppDatabase(schemaV7.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final linea = await db
          .into(db.servicioLineaComercial)
          .insertReturning(
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
    },
  );

  test(
    '9.json coincide con el esquema final de la Etapa 4H.1 (Configuración de cobro, tablas nuevas)',
    () async {
      final schema = await verifier.schemaAt(9);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
          'entidad_fiscal',
          'tipo_modalidad_turno',
          'servicio_linea_comercial',
          'servicio_linea_comercial_vigencia',
          'tipo_frecuencia_cobro',
          'configuracion_cobro',
          'configuracion_cobro_vigencia',
          'configuracion_cobro_correo',
        ]),
      );

      final sqlConfiguracionCobro =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'configuracion_cobro'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlConfiguracionCobro,
        contains(
          '"servicio_id" TEXT NOT NULL UNIQUE REFERENCES servicio (id) ON DELETE RESTRICT',
        ),
      );

      final sqlVigencia =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'configuracion_cobro_vigencia'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlVigencia,
        contains('REFERENCES configuracion_cobro (id) ON DELETE RESTRICT'),
      );
      expect(
        sqlVigencia,
        contains('REFERENCES tipo_frecuencia_cobro (id) ON DELETE RESTRICT'),
      );
      expect(
        sqlVigencia,
        contains('REFERENCES entidad_fiscal (id) ON DELETE RESTRICT'),
      );
      expect(
        sqlVigencia,
        contains('"entidad_fiscal_id" TEXT NULL'),
        reason: 'opcional — solo obligatoria para CFDI, validado en dominio',
      );
      expect(sqlVigencia, contains('"portal_contrasena" TEXT NULL'));
      expect(sqlVigencia, contains('"cuenta_bancaria" TEXT NULL'));
      expect(
        sqlVigencia,
        contains('CHECK (dia_inicio_periodo BETWEEN 1 AND 31)'),
      );
      expect(
        sqlVigencia,
        contains(
          'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
        ),
      );

      final sqlCorreo =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'configuracion_cobro_correo'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlCorreo,
        contains(
          'REFERENCES configuracion_cobro_vigencia (id) ON DELETE CASCADE',
        ),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual siembra la frecuencia de cobro Mensual',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final frecuencias = await db.select(db.tipoFrecuenciaCobro).get();
      expect(frecuencias.map((f) => f.codigo).toSet(), {'MENSUAL'});

      await db.close();
    },
  );

  test(
    'migración 8 → 9 conserva Servicio/líneas comerciales reales y crea las tablas de Configuración de cobro vacías',
    () async {
      final schemaV8 = await verifier.schemaAt(8);
      final raw = schemaV8.rawDatabase;

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
      raw.execute('''
      INSERT INTO servicio_linea_comercial (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('linea-real', 'servicio-real', 1700000000, 1700000000, 'activo');
    ''');

      final db = AppDatabase(schemaV8.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final servicios = await db.select(db.servicio).get();
      expect(
        servicios,
        hasLength(1),
        reason: 'ningún Servicio real debe perderse en una migración aditiva',
      );

      final lineas = await db.select(db.servicioLineaComercial).get();
      expect(
        lineas,
        hasLength(1),
        reason:
            'ninguna línea comercial real debe perderse en una migración aditiva',
      );

      final configuraciones = await db.select(db.configuracionCobro).get();
      expect(configuraciones, isEmpty);
      final frecuencias = await db.select(db.tipoFrecuenciaCobro).get();
      expect(frecuencias, hasLength(1));

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta una Configuración de cobro con su primera vigencia y un correo tras la migración',
    () async {
      final schemaV8 = await verifier.schemaAt(8);
      final db = AppDatabase(schemaV8.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );

      final configuracion = await db
          .into(db.configuracionCobro)
          .insertReturning(
            ConfiguracionCobroCompanion.insert(servicioId: servicio.id),
          );
      final vigencia = await db
          .into(db.configuracionCobroVigencia)
          .insertReturning(
            ConfiguracionCobroVigenciaCompanion.insert(
              configuracionCobroId: configuracion.id,
              tipoDocumento: 'reciboDePago',
              frecuenciaId: SeedIds.frecuenciaCobroMensual,
              diaInicioPeriodo: 1,
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              fechaInicioVigencia: DateTime(2026, 1, 1),
            ),
          );
      final correo = await db
          .into(db.configuracionCobroCorreo)
          .insertReturning(
            ConfiguracionCobroCorreoCompanion.insert(
              configuracionCobroVigenciaId: vigencia.id,
              correo: 'facturacion@sportium.mx',
            ),
          );
      expect(vigencia.diaInicioPeriodo, 1);
      expect(correo.correo, 'facturacion@sportium.mx');

      await db.close();
    },
  );

  test(
    'rechaza una Configuración de cobro con Servicio o Vigencia con frecuencia inexistente tras la migración',
    () async {
      final schemaV8 = await verifier.schemaAt(8);
      final db = AppDatabase(schemaV8.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
        VALUES ('configuracion-invalida', 'servicio-inexistente', 1700000000, 1700000000, 'activo');
      '''),
        throwsA(anything),
      );

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final configuracion = await db
          .into(db.configuracionCobro)
          .insertReturning(
            ConfiguracionCobroCompanion.insert(servicioId: servicio.id),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO configuracion_cobro_vigencia (
          id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo,
          agrupacion, metodo, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'vigencia-frecuencia-invalida', '${configuracion.id}', 'reciboDePago', 'frecuencia-inexistente', 1,
          'porServicio', 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '10.json coincide con el esquema final de la Etapa 4H.2 (reglas de evento, tabla nueva)',
    () async {
      final schema = await verifier.schemaAt(10);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
          'entidad_fiscal',
          'tipo_modalidad_turno',
          'servicio_linea_comercial',
          'servicio_linea_comercial_vigencia',
          'tipo_frecuencia_cobro',
          'configuracion_cobro',
          'configuracion_cobro_vigencia',
          'configuracion_cobro_correo',
          'configuracion_cobro_regla_evento',
        ]),
      );

      final sqlReglaEvento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'configuracion_cobro_regla_evento'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlReglaEvento,
        contains(
          'REFERENCES configuracion_cobro_vigencia (id) ON DELETE CASCADE',
        ),
      );
      expect(
        sqlReglaEvento,
        contains('UNIQUE (configuracion_cobro_vigencia_id, tipo_evento)'),
      );
      expect(
        sqlReglaEvento,
        contains('CHECK (dia_del_mes IS NULL OR dia_del_mes BETWEEN 1 AND 31)'),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 9 → 10 conserva una Configuración de cobro real y crea la tabla de reglas de evento vacía',
    () async {
      final schemaV9 = await verifier.schemaAt(9);
      final raw = schemaV9.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      // `schemaAt(9)` da un snapshot estructural puro, sin la siembra que
      // una instalación real ya habría aplicado en su propia migración
      // 8→9 — se inserta a mano para simular ese estado real.
      raw.execute('''
      INSERT INTO tipo_frecuencia_cobro (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.frecuenciaCobroMensual}', 'MENSUAL', 'Mensual', 1700000000, 1700000000);
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
      raw.execute('''
      INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('configuracion-real', 'servicio-real', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_vigencia (
        id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo,
        agrupacion, metodo, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-real', 'configuracion-real', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 1,
        'porServicio', 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV9.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final configuraciones = await db.select(db.configuracionCobro).get();
      expect(
        configuraciones,
        hasLength(1),
        reason:
            'ninguna Configuración de cobro real debe perderse en una migración aditiva',
      );

      final vigencias = await db.select(db.configuracionCobroVigencia).get();
      expect(vigencias, hasLength(1));

      final reglas = await db.select(db.configuracionCobroReglaEvento).get();
      expect(reglas, isEmpty);

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test('acepta una regla de evento válida tras la migración', () async {
    final schemaV8 = await verifier.schemaAt(8);
    final db = AppDatabase(schemaV8.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final cliente = await db
        .into(db.cliente)
        .insertReturning(
          ClienteCompanion.insert(
            codigo: 'CLI-000001',
            nombreComercial: 'Sportium',
          ),
        );
    final servicio = await db
        .into(db.servicio)
        .insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    final configuracion = await db
        .into(db.configuracionCobro)
        .insertReturning(
          ConfiguracionCobroCompanion.insert(servicioId: servicio.id),
        );
    final vigencia = await db
        .into(db.configuracionCobroVigencia)
        .insertReturning(
          ConfiguracionCobroVigenciaCompanion.insert(
            configuracionCobroId: configuracion.id,
            tipoDocumento: 'cfdi',
            frecuenciaId: SeedIds.frecuenciaCobroMensual,
            diaInicioPeriodo: 21,
            agrupacion: 'porEntidadFiscal',
            metodo: 'ppd',
            requiereComplemento: const Value(true),
            fechaInicioVigencia: DateTime(2026, 1, 21),
          ),
        );

    final regla = await db
        .into(db.configuracionCobroReglaEvento)
        .insertReturning(
          ConfiguracionCobroReglaEventoCompanion.insert(
            configuracionCobroVigenciaId: vigencia.id,
            tipoEvento: 'emision',
            tipoRegla: 'diaFijoDelMes',
            mesRelativo: const Value('siguiente'),
            diaDelMes: const Value(21),
          ),
        );
    expect(regla.tipoEvento, 'emision');
    expect(regla.diaDelMes, 21);

    await db.close();
  });

  test(
    'rechaza dos reglas de evento con el mismo tipoEvento en la misma vigencia tras la migración',
    () async {
      final schemaV8 = await verifier.schemaAt(8);
      final db = AppDatabase(schemaV8.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final configuracion = await db
          .into(db.configuracionCobro)
          .insertReturning(
            ConfiguracionCobroCompanion.insert(servicioId: servicio.id),
          );
      final vigencia = await db
          .into(db.configuracionCobroVigencia)
          .insertReturning(
            ConfiguracionCobroVigenciaCompanion.insert(
              configuracionCobroId: configuracion.id,
              tipoDocumento: 'reciboDePago',
              frecuenciaId: SeedIds.frecuenciaCobroMensual,
              diaInicioPeriodo: 1,
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              fechaInicioVigencia: DateTime(2026, 1, 1),
            ),
          );
      await db
          .into(db.configuracionCobroReglaEvento)
          .insert(
            ConfiguracionCobroReglaEventoCompanion.insert(
              configuracionCobroVigenciaId: vigencia.id,
              tipoEvento: 'pagoEsperado',
              tipoRegla: 'diaFijoDelMes',
              mesRelativo: const Value('actual'),
              diaDelMes: const Value(10),
            ),
          );

      expect(
        () => db
            .into(db.configuracionCobroReglaEvento)
            .insert(
              ConfiguracionCobroReglaEventoCompanion.insert(
                configuracionCobroVigenciaId: vigencia.id,
                tipoEvento: 'pagoEsperado',
                tipoRegla: 'diaFijoDelMes',
                mesRelativo: const Value('actual'),
                diaDelMes: const Value(20),
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza una regla de evento con vigencia inexistente tras la migración',
    () async {
      final schemaV8 = await verifier.schemaAt(8);
      final db = AppDatabase(schemaV8.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO configuracion_cobro_regla_evento (
          configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, mes_relativo, dia_del_mes
        ) VALUES (
          'vigencia-inexistente', 'emision', 'diaFijoDelMes', 'actual', 1
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '11.json coincide con el esquema final de la Etapa 4I.1 (Agenda de documentos por emitir, tablas nuevas)',
    () async {
      final schema = await verifier.schemaAt(11);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'app_metadata',
          'codigo_secuencia',
          'tipo_sucursal',
          'industria',
          'tipo_servicio',
          'area',
          'direccion',
          'medio_contacto',
          'attachment',
          'horario',
          'horario_detalle',
          'empresa',
          'sucursal',
          'cliente',
          'contacto',
          'servicio',
          'ubicacion',
          'puesto',
          'entidad_fiscal',
          'tipo_modalidad_turno',
          'servicio_linea_comercial',
          'servicio_linea_comercial_vigencia',
          'tipo_frecuencia_cobro',
          'configuracion_cobro',
          'configuracion_cobro_vigencia',
          'configuracion_cobro_correo',
          'configuracion_cobro_regla_evento',
          'documento_por_emitir',
          'documento_por_emitir_servicio',
          'documento_por_emitir_configuracion',
          'documento_por_emitir_linea',
          'documento_por_emitir_correo',
        ]),
      );

      final sqlDocumento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir'",
                  )
                  .single['sql']
              as String;
      expect(sqlDocumento, contains('"codigo" TEXT NOT NULL UNIQUE'));
      expect(sqlDocumento, contains('"generation_key" TEXT NOT NULL UNIQUE'));
      expect(
        sqlDocumento,
        contains('REFERENCES cliente (id) ON DELETE RESTRICT'),
      );
      expect(
        sqlDocumento,
        contains('REFERENCES entidad_fiscal (id) ON DELETE RESTRICT'),
      );
      expect(sqlDocumento, contains('CHECK (periodo_fin >= periodo_inicio)'));
      expect(sqlDocumento, contains('CHECK (importe_base_esperado >= 0)'));
      expect(sqlDocumento, contains('CHECK (importe_final_esperado >= 0)'));

      final sqlServicio =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir_servicio'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlServicio,
        contains('UNIQUE (documento_por_emitir_id, servicio_id)'),
      );

      final sqlConfiguracion =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir_configuracion'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlConfiguracion,
        contains('UNIQUE (documento_por_emitir_id, servicio_id)'),
      );
      expect(
        sqlConfiguracion,
        contains(
          'REFERENCES configuracion_cobro_vigencia (id) ON DELETE RESTRICT',
        ),
      );

      final sqlLinea =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir_linea'",
                  )
                  .single['sql']
              as String;
      expect(sqlLinea, contains('CHECK (cantidad_elementos > 0)'));
      expect(sqlLinea, contains('CHECK (subtotal_proporcional >= 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 1 → versión actual siembra CodigoSecuencia(documento_por_emitir)',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      schemaV1.rawDatabase.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');

      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final codigoDocumento =
          await (db.select(db.codigoSecuencia)..where(
            (t) => t.entityType.equals('documento_por_emitir'),
          )).getSingle();
      expect(codigoDocumento.prefijo, 'DOC');
      expect(codigoDocumento.digitos, 6);
      expect(codigoDocumento.contadorActual, 0);

      await db.close();
    },
  );

  test(
    'migración 10 → 11 conserva datos reales y crea las tablas de Agenda vacías',
    () async {
      final schemaV10 = await verifier.schemaAt(10);
      final raw = schemaV10.rawDatabase;

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

      final db = AppDatabase(schemaV10.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final servicios = await db.select(db.servicio).get();
      expect(
        servicios,
        hasLength(1),
        reason: 'ningún Servicio real debe perderse en una migración aditiva',
      );

      final documentos = await db.select(db.documentoPorEmitir).get();
      expect(documentos, isEmpty);

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un DocumentoPorEmitir completo (servicio, configuración y línea) tras la migración',
    () async {
      // Origen 7, no 8: el paso `to >= 8 && from <= 7` (que crea y siembra
      // TipoModalidadTurno) solo corre si `from <= 7` — partir de 8 deja
      // esa tabla ya creada pero vacía (el snapshot es estructural puro,
      // sin siembra), mismo gotcha ya documentado en 4G.1.
      final schemaV7 = await verifier.schemaAt(7);
      final db = AppDatabase(schemaV7.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final puesto = await db
          .into(db.puesto)
          .insertReturning(
            PuestoCompanion.insert(
              codigo: 'PUE-0001',
              nombre: 'Guardia',
              areaId: SeedIds.areaOperaciones,
              tipo: 'operativo',
              nivelJerarquico: 5,
            ),
          );
      final linea = await db
          .into(db.servicioLineaComercial)
          .insertReturning(
            ServicioLineaComercialCompanion.insert(servicioId: servicio.id),
          );
      final vigenciaLinea = await db
          .into(db.servicioLineaComercialVigencia)
          .insertReturning(
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
      final configuracion = await db
          .into(db.configuracionCobro)
          .insertReturning(
            ConfiguracionCobroCompanion.insert(servicioId: servicio.id),
          );
      final vigenciaCobro = await db
          .into(db.configuracionCobroVigencia)
          .insertReturning(
            ConfiguracionCobroVigenciaCompanion.insert(
              configuracionCobroId: configuracion.id,
              tipoDocumento: 'reciboDePago',
              frecuenciaId: SeedIds.frecuenciaCobroMensual,
              diaInicioPeriodo: 1,
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              fechaInicioVigencia: DateTime(2026, 1, 1),
            ),
          );

      final documento = await db
          .into(db.documentoPorEmitir)
          .insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey:
                  'porServicio|${cliente.id}||${servicio.id}|${vigenciaCobro.id}|2026-01-01|2026-01-31|reciboDePago',
              importeBaseEsperado: 3000000,
              importeFinalEsperado: 3000000,
            ),
          );
      await db
          .into(db.documentoPorEmitirServicio)
          .insertReturning(
            DocumentoPorEmitirServicioCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: servicio.id,
            ),
          );
      await db
          .into(db.documentoPorEmitirConfiguracion)
          .insertReturning(
            DocumentoPorEmitirConfiguracionCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: servicio.id,
              configuracionCobroVigenciaId: vigenciaCobro.id,
              fechaPagoEsperadoProgramada: const Value(null),
            ),
          );
      final documentoLinea = await db
          .into(db.documentoPorEmitirLinea)
          .insertReturning(
            DocumentoPorEmitirLineaCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: servicio.id,
              lineaComercialVigenciaId: vigenciaLinea.id,
              puestoNombre: 'Guardia',
              modalidadTurnoNombre: '24×24',
              cantidadElementos: 2,
              precioUnitario: 1500000,
              tratamientoIva: 'noAplica',
              diasAplicables: 31,
              subtotalProporcional: 3100000,
            ),
          );
      expect(documentoLinea.subtotalProporcional, 3100000);

      await db.close();
    },
  );

  test(
    'rechaza dos DocumentoPorEmitir con la misma generationKey tras la migración',
    () async {
      final schemaV10 = await verifier.schemaAt(10);
      final db = AppDatabase(schemaV10.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );

      await db
          .into(db.documentoPorEmitir)
          .insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'clave-repetida',
              importeBaseEsperado: 0,
              importeFinalEsperado: 0,
            ),
          );

      expect(
        () => db
            .into(db.documentoPorEmitir)
            .insertReturning(
              DocumentoPorEmitirCompanion.insert(
                codigo: 'DOC-000002',
                clienteId: cliente.id,
                tipoDocumento: 'reciboDePago',
                agrupacion: 'porServicio',
                metodo: 'noAplica',
                periodoInicio: DateTime(2026, 2, 1),
                periodoFin: DateTime(2026, 2, 28),
                generationKey: 'clave-repetida',
                importeBaseEsperado: 0,
                importeFinalEsperado: 0,
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza un DocumentoPorEmitirServicio con Servicio inexistente tras la migración',
    () async {
      final schemaV10 = await verifier.schemaAt(10);
      final db = AppDatabase(schemaV10.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final documento = await db
          .into(db.documentoPorEmitir)
          .insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'clave-unica',
              importeBaseEsperado: 0,
              importeFinalEsperado: 0,
            ),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO documento_por_emitir_servicio (documento_por_emitir_id, servicio_id)
        VALUES ('${documento.id}', 'servicio-inexistente');
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '12.json coincide con el esquema final de la Etapa 4I.2.1 (datos definitivos aditivos, historial y correos de envío)',
    () async {
      final schema = await verifier.schemaAt(12);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>[
          'documento_por_emitir',
          'documento_por_emitir_servicio',
          'documento_por_emitir_configuracion',
          'documento_por_emitir_linea',
          'documento_por_emitir_correo',
          'documento_por_emitir_correo_envio',
          'documento_por_emitir_evento',
        ]),
      );

      final sqlDocumento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir'",
                  )
                  .single['sql']
              as String;
      expect(sqlDocumento, contains('"folio_documento" TEXT'));
      expect(sqlDocumento, contains('"serie_fiscal" TEXT'));
      expect(sqlDocumento, contains('"folio_fiscal" TEXT'));
      expect(sqlDocumento, contains('"uuid" TEXT'));
      expect(sqlDocumento, contains('"fecha_emision_real" INTEGER'));
      expect(sqlDocumento, contains('"importe_emitido" INTEGER'));
      expect(sqlDocumento, contains('"fecha_envio" INTEGER'));
      expect(sqlDocumento, contains('"observaciones_emision" TEXT'));
      expect(sqlDocumento, contains('"observaciones_envio" TEXT'));
      expect(
        sqlDocumento,
        contains('CHECK (importe_emitido IS NULL OR importe_emitido >= 0)'),
      );

      final sqlEvento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir_evento'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlEvento,
        contains('REFERENCES documento_por_emitir (id) ON DELETE CASCADE'),
      );

      final sqlCorreoEnvio =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir_correo_envio'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlCorreoEnvio,
        contains('REFERENCES documento_por_emitir (id) ON DELETE CASCADE'),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 11 → 12 conserva un DocumentoPorEmitir real y crea las tablas de emisión/historial vacías',
    () async {
      final schemaV11 = await verifier.schemaAt(11);
      final raw = schemaV11.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO documento_por_emitir (
        id, codigo, cliente_id, tipo_documento, agrupacion, metodo, requiere_complemento,
        periodo_inicio, periodo_fin, generation_key, importe_base_esperado, importe_final_esperado,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'documento-real', 'DOC-000001', 'cliente-real', 'reciboDePago', 'porServicio', 'noAplica', 0,
        1735689600, 1738367999, 'clave-real', 0, 0,
        'pendiente', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV11.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final documentos = await db.select(db.documentoPorEmitir).get();
      expect(
        documentos,
        hasLength(1),
        reason:
            'ningún DocumentoPorEmitir real debe perderse en una migración aditiva',
      );
      expect(
        documentos.single.folioDocumento,
        isNull,
        reason: 'columnas nuevas nullable, nunca inventadas',
      );
      expect(documentos.single.importeEmitido, isNull);

      final eventos = await db.select(db.documentoPorEmitirEvento).get();
      expect(eventos, isEmpty);

      final correosEnvio =
          await db.select(db.documentoPorEmitirCorreoEnvio).get();
      expect(correosEnvio, isEmpty);

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un DocumentoPorEmitir con datos de emisión, envío y un evento de historial tras la migración',
    () async {
      final schemaV11 = await verifier.schemaAt(11);
      final db = AppDatabase(schemaV11.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final documento = await db
          .into(db.documentoPorEmitir)
          .insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: 'pue',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'clave-emitida',
              importeBaseEsperado: 3000000,
              importeFinalEsperado: 3000000,
              estatus: const Value('enviado'),
              folioDocumento: const Value('A-001'),
              serieFiscal: const Value('A'),
              folioFiscal: const Value('001'),
              uuid: const Value('11111111-1111-1111-1111-111111111111'),
              fechaEmisionReal: Value(DateTime(2026, 1, 5)),
              importeEmitido: const Value(3000000),
              fechaEnvio: Value(DateTime(2026, 1, 6)),
            ),
          );

      await db
          .into(db.documentoPorEmitirCorreoEnvio)
          .insertReturning(
            DocumentoPorEmitirCorreoEnvioCompanion.insert(
              documentoPorEmitirId: documento.id,
              correo: 'facturacion@sportium.mx',
            ),
          );
      final evento = await db
          .into(db.documentoPorEmitirEvento)
          .insertReturning(
            DocumentoPorEmitirEventoCompanion.insert(
              documentoPorEmitirId: documento.id,
              fechaHora: DateTime(2026, 1, 6),
              tipoEvento: 'envioRegistrado',
              estadoAnterior: const Value('emitido'),
              estadoNuevo: const Value('enviado'),
              datosRelevantes: const Value(
                '{"correosUtilizados":["facturacion@sportium.mx"]}',
              ),
            ),
          );

      expect(evento.tipoEvento, 'envioRegistrado');
      expect(documento.uuid, '11111111-1111-1111-1111-111111111111');

      await db.close();
    },
  );

  test(
    'rechaza un DocumentoPorEmitirEvento con DocumentoPorEmitir inexistente tras la migración',
    () async {
      final schemaV11 = await verifier.schemaAt(11);
      final db = AppDatabase(schemaV11.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO documento_por_emitir_evento (documento_por_emitir_id, fecha_hora, tipo_evento)
        VALUES ('documento-inexistente', 1700000000, 'creadoManual');
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '13.json coincide con el esquema final de la Etapa 4I.2.2 (Attachment con arco exclusivo de 3 vías)',
    () async {
      final schema = await verifier.schemaAt(13);

      final sqlAttachment =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attachment'",
                  )
                  .single['sql']
              as String;
      expect(sqlAttachment, contains('"documento_por_emitir_id" TEXT'));
      expect(sqlAttachment, contains('"categoria" TEXT'));
      expect(sqlAttachment, contains('"estado" TEXT'));
      expect(
        sqlAttachment,
        contains('REFERENCES documento_por_emitir (id) ON DELETE CASCADE'),
      );
      expect(sqlAttachment, contains('empresa_id IS NOT NULL'));
      expect(sqlAttachment, contains('documento_por_emitir_id IS NOT NULL'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 12 → 13 conserva un Attachment real de Empresa con las columnas nuevas en NULL/activo',
    () async {
      final schemaV12 = await verifier.schemaAt(12);
      final raw = schemaV12.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empresa (id, codigo, nombre_comercial, created_at, updated_at, ciclo_vida_registro)
      VALUES ('empresa-real', 'RSG-01', 'RISEG', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO attachment (
        id, empresa_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
      ) VALUES (
        'attachment-real', 'empresa-real', 'logo.png', 'a1b2c3.png', '/attachments/a1b2c3.png',
        'image/png', 12345, 1700000000
      );
    ''');

      final db = AppDatabase(schemaV12.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final attachments = await db.select(db.attachment).get();
      expect(
        attachments,
        hasLength(1),
        reason: 'ningún Attachment real debe perderse en una migración aditiva',
      );
      expect(attachments.single.documentoPorEmitirId, isNull);
      expect(attachments.single.categoria, isNull);
      expect(
        attachments.single.estado,
        'activo',
        reason: 'las filas existentes deben quedar activas por defecto',
      );

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un Attachment de DocumentoPorEmitir con categoría tras la migración',
    () async {
      final schemaV12 = await verifier.schemaAt(12);
      final db = AppDatabase(schemaV12.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final documento = await db
          .into(db.documentoPorEmitir)
          .insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'clave-adjunto',
              importeBaseEsperado: 0,
              importeFinalEsperado: 0,
            ),
          );

      final adjunto = await db
          .into(db.attachment)
          .insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-nuevo',
              documentoPorEmitirId: Value(documento.id),
              originalFileName: 'recibo enero.pdf',
              storedFileName: 'f1e2d3.pdf',
              path: '/attachments/${documento.id}/reciboPdf/f1e2d3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
              categoria: const Value('reciboPdf'),
            ),
          );

      expect(adjunto.estado, 'activo');
      expect(adjunto.categoria, 'reciboPdf');
      expect(adjunto.documentoPorEmitirId, documento.id);

      await db.close();
    },
  );

  test(
    'rechaza un Attachment con más de un dueño (arco exclusivo de 3 vías) tras la migración',
    () async {
      final schemaV12 = await verifier.schemaAt(12);
      final db = AppDatabase(schemaV12.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO attachment (
          id, cliente_id, documento_por_emitir_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
        ) VALUES (
          'attachment-doble-dueno', '${cliente.id}', 'documento-inexistente', 'a.pdf', 'x.pdf', '/x.pdf',
          'application/pdf', 100, 1700000000
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test('rechaza un Attachment sin ningún dueño tras la migración', () async {
    final schemaV12 = await verifier.schemaAt(12);
    final db = AppDatabase(schemaV12.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    expect(
      () => db.customStatement('''
        INSERT INTO attachment (id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at)
        VALUES ('attachment-sin-dueno', 'a.pdf', 'x.pdf', '/x.pdf', 'application/pdf', 100, 1700000000);
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test(
    '14.json coincide con el esquema final de la Etapa 4J.1 (CuentaPorCobrar + CuentaPorCobrarEvento)',
    () async {
      final schema = await verifier.schemaAt(14);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>['cuenta_por_cobrar', 'cuenta_por_cobrar_evento']),
      );

      final sqlCuenta =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'cuenta_por_cobrar'",
                  )
                  .single['sql']
              as String;
      // La Cuenta por cobrar nunca puede existir sin su DocumentoPorEmitir
      // (FK) y un DocumentoPorEmitir nunca puede tener más de una (UNIQUE)
      // — regla de integridad exigida tanto en dominio como en base de
      // datos (requisito explícito de Marlon en la aprobación de 4J.1).
      expect(
        sqlCuenta,
        contains(
          '"documento_por_emitir_id" TEXT NOT NULL UNIQUE REFERENCES documento_por_emitir (id)',
        ),
      );
      expect(sqlCuenta, contains('CHECK (saldo_original >= 0)'));
      expect(
        sqlCuenta,
        contains(
          'CHECK (saldo_pendiente >= 0 AND saldo_pendiente <= saldo_original)',
        ),
      );
      expect(sqlCuenta, contains('CHECK (importe_emitido >= 0)'));
      expect(sqlCuenta, contains('"moneda" TEXT NOT NULL DEFAULT \'MXN\''));
      expect(
        sqlCuenta,
        contains('"estatus" TEXT NOT NULL DEFAULT \'pendiente\''),
      );
      expect(sqlCuenta, contains('"fecha_vencimiento" INTEGER NULL'));

      final sqlEvento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'cuenta_por_cobrar_evento'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlEvento,
        contains('REFERENCES cuenta_por_cobrar (id) ON DELETE CASCADE'),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 13 → 14 no crea ninguna Cuenta por cobrar cuando no hay Documentos Procesados/Aceptados',
    () async {
      final schemaV13 = await verifier.schemaAt(13);
      final raw = schemaV13.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      // Documento real, pero todavía en `emitido` — no debe generar
      // ninguna Cuenta por cobrar (la Resolución A de Marlon solo aplica
      // en `procesadoAceptado`).
      raw.execute('''
      INSERT INTO documento_por_emitir (
        id, codigo, cliente_id, tipo_documento, agrupacion, metodo, requiere_complemento,
        periodo_inicio, periodo_fin, generation_key, importe_base_esperado, importe_final_esperado,
        estatus, folio_documento, fecha_emision_real, importe_emitido,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'documento-emitido', 'DOC-000001', 'cliente-real', 'reciboDePago', 'porServicio', 'noAplica', 0,
        1700000000, 1701000000, 'clave-emitido', 500000, 500000,
        'emitido', 'FOL-001', 1700500000, 500000,
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV13.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(
        cuentas,
        isEmpty,
        reason:
            'un documento en emitido (no procesadoAceptado) no genera Cuenta por cobrar',
      );

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      await db.close();
    },
  );

  test(
    'migración 13 → 14 hace backfill automático de la Cuenta por cobrar de un DocumentoPorEmitir ya Procesado/Aceptado '
    '(Resolución F de Marlon)',
    () async {
      final schemaV13 = await verifier.schemaAt(13);
      final raw = schemaV13.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO documento_por_emitir (
        id, codigo, cliente_id, tipo_documento, agrupacion, metodo, requiere_complemento,
        periodo_inicio, periodo_fin, fecha_pago_esperado_programada, generation_key,
        importe_base_esperado, importe_final_esperado,
        estatus, folio_documento, serie_fiscal, folio_fiscal, uuid, fecha_emision_real, importe_emitido,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'documento-aceptado', 'DOC-000002', 'cliente-real', 'cfdi', 'porServicio', 'pue', 0,
        1700000000, 1701000000, 1701500000, 'clave-aceptado',
        620000, 620000,
        'procesadoAceptado', 'A-001', 'A', '001', '11111111-1111-1111-1111-111111111111', 1700500000, 620000,
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV13.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(
        cuentas,
        hasLength(1),
        reason: 'el backfill debe generar exactamente una Cuenta por cobrar',
      );
      final cuenta = cuentas.single;
      expect(cuenta.documentoPorEmitirId, 'documento-aceptado');
      expect(cuenta.clienteId, 'cliente-real');
      expect(cuenta.tipoDocumento, 'cfdi');
      expect(cuenta.metodo, 'pue');
      expect(cuenta.folioDocumento, 'A-001');
      expect(cuenta.serieFiscal, 'A');
      expect(cuenta.folioFiscal, '001');
      expect(cuenta.uuid, '11111111-1111-1111-1111-111111111111');
      expect(cuenta.importeEmitido, 620000);
      expect(cuenta.saldoOriginal, 620000);
      expect(cuenta.saldoPendiente, 620000);
      expect(cuenta.moneda, 'MXN');
      expect(cuenta.estatus, 'pendiente');
      expect(
        cuenta.fechaVencimiento,
        DateTime.fromMillisecondsSinceEpoch(1701500000 * 1000),
      );

      final eventos = await db.select(db.cuentaPorCobrarEvento).get();
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'creada');
      expect(eventos.single.observacion, contains('backfill'));

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras el backfill',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras el backfill');

      await db.close();
    },
  );

  test(
    'migración 13 → 14 no duplica la Cuenta por cobrar de un DocumentoPorEmitir que ya tenía una',
    () async {
      final schemaV13 = await verifier.schemaAt(13);
      final raw = schemaV13.rawDatabase;

      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO documento_por_emitir (
        id, codigo, cliente_id, tipo_documento, agrupacion, metodo, requiere_complemento,
        periodo_inicio, periodo_fin, generation_key, importe_base_esperado, importe_final_esperado,
        estatus, folio_documento, fecha_emision_real, importe_emitido,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'documento-aceptado', 'DOC-000003', 'cliente-real', 'reciboDePago', 'porServicio', 'noAplica', 0,
        1700000000, 1701000000, 'clave-ya-tenia', 500000, 500000,
        'procesadoAceptado', 'REC-001', 1700500000, 500000,
        1700000000, 1700000000, 'activo'
      );
    ''');
      // Nota: en la práctica esto no puede ocurrir en schemaVersion 13
      // (la tabla `cuenta_por_cobrar` no existe todavía) — esta prueba
      // simula la migración corriendo dos veces sobre la misma base
      // (el escenario real de idempotencia que la comprobación
      // `yaExiste` en `migrarCuentaPorCobrarV14` protege).

      final db = AppDatabase(schemaV13.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // Ejecutar el backfill una segunda vez a mano no debe duplicar
      // nada — mismo criterio de idempotencia que `runSeed`.
      await migrarCuentaPorCobrarV14(db);
      await migrarCuentaPorCobrarV14(db);

      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(
        cuentas,
        hasLength(1),
        reason:
            'correr el backfill varias veces no debe duplicar la Cuenta por cobrar',
      );

      await db.close();
    },
  );

  test(
    'rechaza una Cuenta por cobrar con DocumentoPorEmitir inexistente tras la migración',
    () async {
      final schemaV13 = await verifier.schemaAt(13);
      final db = AppDatabase(schemaV13.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO cuenta_por_cobrar (
          id, documento_por_emitir_id, cliente_id, tipo_documento, metodo,
          fecha_emision_real, importe_emitido, saldo_original, saldo_pendiente,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'cxc-huerfana', 'documento-inexistente', 'cliente-cualquiera', 'reciboDePago', 'noAplica',
          1700000000, 500000, 500000, 500000,
          1700000000, 1700000000, 'activo'
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza una segunda Cuenta por cobrar para el mismo DocumentoPorEmitir tras la migración (UNIQUE)',
    () async {
      final schemaV13 = await verifier.schemaAt(13);
      final db = AppDatabase(schemaV13.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final documento = await db
          .into(db.documentoPorEmitir)
          .insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'clave-unica-cxc',
              importeBaseEsperado: 500000,
              importeFinalEsperado: 500000,
              estatus: const Value('procesadoAceptado'),
              fechaEmisionReal: Value(DateTime(2026, 1, 5)),
              importeEmitido: const Value(500000),
            ),
          );
      await db
          .into(db.cuentaPorCobrar)
          .insert(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: documento.id,
              clienteId: cliente.id,
              tipoDocumento: 'reciboDePago',
              metodo: 'noAplica',
              fechaEmisionReal: DateTime(2026, 1, 5),
              importeEmitido: 500000,
              saldoOriginal: 500000,
              saldoPendiente: 500000,
            ),
          );

      expect(
        () => db
            .into(db.cuentaPorCobrar)
            .insert(
              CuentaPorCobrarCompanion.insert(
                documentoPorEmitirId: documento.id,
                clienteId: cliente.id,
                tipoDocumento: 'reciboDePago',
                metodo: 'noAplica',
                fechaEmisionReal: DateTime(2026, 1, 5),
                importeEmitido: 500000,
                saldoOriginal: 500000,
                saldoPendiente: 500000,
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '15.json coincide con el esquema final de la Etapa 4J.2 (Pago/AplicacionPago/PagoEvento, Attachment de 4 vías)',
    () async {
      final schema = await verifier.schemaAt(15);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>['pago', 'aplicacion_pago', 'pago_evento']),
      );

      final sqlPago =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pago'",
                  )
                  .single['sql']
              as String;
      expect(sqlPago, contains('"folio_pago" TEXT NOT NULL UNIQUE'));
      expect(
        sqlPago,
        contains(
          '"cliente_id" TEXT NOT NULL REFERENCES cliente (id) ON DELETE RESTRICT',
        ),
      );
      expect(sqlPago, contains('CHECK (monto_total > 0)'));
      expect(
        sqlPago,
        contains(
          'CHECK (monto_aplicado >= 0 AND monto_aplicado <= monto_total)',
        ),
      );

      final sqlAplicacion =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'aplicacion_pago'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlAplicacion,
        contains(
          '"pago_id" TEXT NOT NULL REFERENCES pago (id) ON DELETE RESTRICT',
        ),
      );
      expect(
        sqlAplicacion,
        contains(
          '"cuenta_por_cobrar_id" TEXT NOT NULL REFERENCES cuenta_por_cobrar (id) ON DELETE RESTRICT',
        ),
      );
      expect(sqlAplicacion, contains('CHECK (monto > 0)'));
      expect(
        sqlAplicacion,
        contains('CHECK (saldo_despues = saldo_antes - monto)'),
      );
      expect(sqlAplicacion, contains('CHECK (saldo_despues >= 0)'));

      final sqlPagoEvento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pago_evento'",
                  )
                  .single['sql']
              as String;
      expect(sqlPagoEvento, contains('REFERENCES pago (id) ON DELETE CASCADE'));

      final sqlAttachment =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attachment'",
                  )
                  .single['sql']
              as String;
      expect(sqlAttachment, contains('"pago_id" TEXT NULL'));
      expect(
        sqlAttachment,
        contains(
          'FOREIGN KEY (pago_id) REFERENCES pago (id) ON DELETE CASCADE',
        ),
      );
      expect(
        sqlAttachment,
        contains(
          '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN documento_por_emitir_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN pago_id IS NOT NULL THEN 1 ELSE 0 END) = 1',
        ),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 13 → 15 conserva una Cuenta por cobrar real y crea las tablas de Pago vacías (sin backfill)',
    () async {
      final schemaV13 = await verifier.schemaAt(13);
      final raw = schemaV13.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO documento_por_emitir (
        id, codigo, cliente_id, tipo_documento, agrupacion, metodo, requiere_complemento,
        periodo_inicio, periodo_fin, generation_key, importe_base_esperado, importe_final_esperado,
        estatus, folio_documento, fecha_emision_real, importe_emitido,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'documento-real', 'DOC-000001', 'cliente-real', 'reciboDePago', 'porServicio', 'noAplica', 0,
        1700000000, 1701000000, 'clave-real', 500000, 500000,
        'procesadoAceptado', 'FOL-001', 1700500000, 500000,
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV13.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cuentas = await db.select(db.cuentaPorCobrar).get();
      expect(
        cuentas,
        hasLength(1),
        reason:
            'el backfill de 4J.1 debe seguir corriendo normalmente hasta 15',
      );

      final pagos = await db.select(db.pago).get();
      expect(
        pagos,
        isEmpty,
        reason:
            'Pago es tabla nueva en 4J.2, sin backfill — nunca existió el concepto antes',
      );

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'migración 12 → 15 conserva un Attachment real de Empresa y agrega pagoId en NULL',
    () async {
      final schemaV12 = await verifier.schemaAt(12);
      final raw = schemaV12.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empresa (id, codigo, nombre_comercial, created_at, updated_at, ciclo_vida_registro)
      VALUES ('empresa-real', 'RSG-01', 'RISEG', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO attachment (
        id, empresa_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
      ) VALUES (
        'attachment-real', 'empresa-real', 'logo.png', 'a1b2c3.png', '/attachments/a1b2c3.png',
        'image/png', 12345, 1700000000
      );
    ''');

      final db = AppDatabase(schemaV12.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final attachments = await db.select(db.attachment).get();
      expect(
        attachments,
        hasLength(1),
        reason: 'ningún Attachment real debe perderse en una migración aditiva',
      );
      expect(attachments.single.pagoId, isNull);
      expect(attachments.single.empresaId, 'empresa-real');

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un comprobante de pago (Attachment con pagoId) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );

      final adjunto = await db
          .into(db.attachment)
          .insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-comprobante',
              pagoId: Value(pago.id),
              categoria: const Value('comprobante'),
              originalFileName: 'comprobante.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${pago.id}/comprobante/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
            ),
          );

      expect(adjunto.pagoId, pago.id);
      expect(adjunto.categoria, 'comprobante');

      await db.close();
    },
  );

  test(
    'rechaza un Attachment con pagoId y otro dueño a la vez (arco de 4 vías) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO attachment (
          id, cliente_id, pago_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
        ) VALUES (
          'attachment-doble-dueno', '${cliente.id}', '${pago.id}', 'a.pdf', 'x.pdf', '/x.pdf',
          'application/pdf', 100, 1700000000
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test('rechaza un Pago con Cliente inexistente tras la migración', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    expect(
      () => db.customStatement('''
        INSERT INTO pago (
          id, folio_pago, cliente_id, monto_total, fecha_pago, forma_pago,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'pago-invalido', 'PAG-000001', 'cliente-inexistente', 500000, 1700000000, 'transferencia',
          1700000000, 1700000000, 'activo'
        );
      '''),
      throwsA(anything),
    );

    await db.close();
  });

  test(
    'rechaza una AplicacionPago con Pago o CuentaPorCobrar inexistentes tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO aplicacion_pago (
          id, pago_id, cuenta_por_cobrar_id, monto, saldo_antes, saldo_despues,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'aplicacion-invalida', '${pago.id}', 'cuenta-inexistente', 500000, 500000, 0,
          1700000000, 1700000000, 'activo'
        );
      '''),
        throwsA(anything),
      );

      expect(
        () => db.customStatement('''
        INSERT INTO aplicacion_pago (
          id, pago_id, cuenta_por_cobrar_id, monto, saldo_antes, saldo_despues,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'aplicacion-invalida-2', 'pago-inexistente', 'cuenta-inexistente', 500000, 500000, 0,
          1700000000, 1700000000, 'activo'
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '16.json coincide con el esquema final de la Etapa 4J.3 (ComplementoPago/ComplementoPagoEvento, Attachment de 5 vías)',
    () async {
      final schema = await verifier.schemaAt(16);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>['complemento_pago', 'complemento_pago_evento']),
      );

      final sqlComplemento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'complemento_pago'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlComplemento,
        contains(
          '"pago_id" TEXT NOT NULL UNIQUE REFERENCES pago (id) ON DELETE RESTRICT',
        ),
      );
      expect(sqlComplemento, contains('"uuid" TEXT NOT NULL UNIQUE'));
      expect(sqlComplemento, contains('CHECK (monto_total > 0)'));

      final sqlComplementoEvento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'complemento_pago_evento'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlComplementoEvento,
        contains('REFERENCES complemento_pago (id) ON DELETE CASCADE'),
      );

      final sqlAttachment =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attachment'",
                  )
                  .single['sql']
              as String;
      expect(sqlAttachment, contains('"complemento_pago_id" TEXT NULL'));
      expect(
        sqlAttachment,
        contains(
          'FOREIGN KEY (complemento_pago_id) REFERENCES complemento_pago (id) ON DELETE CASCADE',
        ),
      );
      expect(
        sqlAttachment,
        contains(
          '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN documento_por_emitir_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN pago_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN complemento_pago_id IS NOT NULL THEN 1 ELSE 0 END) = 1',
        ),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 15 → 16 conserva un Pago real y crea las tablas de Complemento vacías (sin backfill)',
    () async {
      final schemaV15 = await verifier.schemaAt(15);
      final raw = schemaV15.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO pago (
        id, folio_pago, cliente_id, monto_total, monto_aplicado, fecha_pago, forma_pago,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'pago-real', 'PAG-000001', 'cliente-real', 500000, 500000, 1700000000, 'transferencia',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV15.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final pagos = await db.select(db.pago).get();
      expect(
        pagos,
        hasLength(1),
        reason: 'ningún Pago real debe perderse en una migración aditiva',
      );

      final complementos = await db.select(db.complementoPago).get();
      expect(
        complementos,
        isEmpty,
        reason: 'ComplementoPago es tabla nueva en 4J.3, sin backfill',
      );

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'migración 12 → 16 conserva un Attachment real de Empresa y agrega complementoPagoId en NULL',
    () async {
      final schemaV12 = await verifier.schemaAt(12);
      final raw = schemaV12.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empresa (id, codigo, nombre_comercial, created_at, updated_at, ciclo_vida_registro)
      VALUES ('empresa-real', 'RSG-01', 'RISEG', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO attachment (
        id, empresa_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
      ) VALUES (
        'attachment-real', 'empresa-real', 'logo.png', 'a1b2c3.png', '/attachments/a1b2c3.png',
        'image/png', 12345, 1700000000
      );
    ''');

      final db = AppDatabase(schemaV12.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final attachments = await db.select(db.attachment).get();
      expect(
        attachments,
        hasLength(1),
        reason: 'ningún Attachment real debe perderse en una migración aditiva',
      );
      expect(attachments.single.complementoPagoId, isNull);
      expect(attachments.single.empresaId, 'empresa-real');

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un Complemento de pago con archivo adjunto (Attachment con complementoPagoId) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      final complemento = await db
          .into(db.complementoPago)
          .insertReturning(
            ComplementoPagoCompanion.insert(
              pagoId: pago.id,
              uuid: '22222222-2222-2222-2222-222222222222',
              fechaTimbrado: DateTime(2026, 1, 21),
              montoTotal: 500000,
            ),
          );

      final adjunto = await db
          .into(db.attachment)
          .insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-complemento',
              complementoPagoId: Value(complemento.id),
              categoria: const Value('pdf'),
              originalFileName: 'complemento.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${complemento.id}/pdf/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
            ),
          );

      expect(adjunto.complementoPagoId, complemento.id);
      expect(complemento.estatus, 'registrado');

      await db.close();
    },
  );

  test(
    'rechaza un Attachment con complementoPagoId y otro dueño a la vez (arco de 5 vías) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      final complemento = await db
          .into(db.complementoPago)
          .insertReturning(
            ComplementoPagoCompanion.insert(
              pagoId: pago.id,
              uuid: '22222222-2222-2222-2222-222222222222',
              fechaTimbrado: DateTime(2026, 1, 21),
              montoTotal: 500000,
            ),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO attachment (
          id, cliente_id, complemento_pago_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
        ) VALUES (
          'attachment-doble-dueno', '${cliente.id}', '${complemento.id}', 'a.pdf', 'x.pdf', '/x.pdf',
          'application/pdf', 100, 1700000000
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza un ComplementoPago con Pago inexistente tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO complemento_pago (
          id, pago_id, uuid, fecha_timbrado, monto_total,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'complemento-invalido', 'pago-inexistente', '22222222-2222-2222-2222-222222222222', 1700000000, 500000,
          1700000000, 1700000000, 'activo'
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza un segundo ComplementoPago para el mismo Pago tras la migración (relación 1:1)',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      await db
          .into(db.complementoPago)
          .insert(
            ComplementoPagoCompanion.insert(
              pagoId: pago.id,
              uuid: '22222222-2222-2222-2222-222222222222',
              fechaTimbrado: DateTime(2026, 1, 21),
              montoTotal: 500000,
            ),
          );

      expect(
        () => db
            .into(db.complementoPago)
            .insert(
              ComplementoPagoCompanion.insert(
                pagoId: pago.id,
                uuid: '33333333-3333-3333-3333-333333333333',
                fechaTimbrado: DateTime(2026, 1, 22),
                montoTotal: 500000,
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza dos ComplementoPago con el mismo UUID tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final pagoA = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      final pagoB = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000002',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      await db
          .into(db.complementoPago)
          .insert(
            ComplementoPagoCompanion.insert(
              pagoId: pagoA.id,
              uuid: '22222222-2222-2222-2222-222222222222',
              fechaTimbrado: DateTime(2026, 1, 21),
              montoTotal: 500000,
            ),
          );

      expect(
        () => db
            .into(db.complementoPago)
            .insert(
              ComplementoPagoCompanion.insert(
                pagoId: pagoB.id,
                uuid: '22222222-2222-2222-2222-222222222222',
                fechaTimbrado: DateTime(2026, 1, 21),
                montoTotal: 500000,
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '17.json coincide con el esquema final de la Etapa 4K.1 (CategoriaFinanciera/Ingreso/Egreso, Attachment de 7 vías)',
    () async {
      final schema = await verifier.schemaAt(17);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(<String>['categoria_financiera', 'ingreso', 'ingreso_evento', 'egreso', 'egreso_evento']),
      );

      final sqlIngreso =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'ingreso'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIngreso,
        contains('"pago_id" TEXT NULL UNIQUE REFERENCES pago (id) ON DELETE RESTRICT'),
      );
      expect(sqlIngreso, contains('"folio_ingreso" TEXT NOT NULL UNIQUE'));
      expect(sqlIngreso, contains('CHECK (monto > 0)'));

      final sqlEgreso =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'egreso'",
                  )
                  .single['sql']
              as String;
      expect(sqlEgreso, contains('"folio_egreso" TEXT NOT NULL UNIQUE'));
      expect(sqlEgreso, contains('CHECK (monto > 0)'));

      final sqlAttachment =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attachment'",
                  )
                  .single['sql']
              as String;
      expect(sqlAttachment, contains('"ingreso_id" TEXT NULL'));
      expect(sqlAttachment, contains('"egreso_id" TEXT NULL'));
      expect(
        sqlAttachment,
        contains(
          'FOREIGN KEY (ingreso_id) REFERENCES ingreso (id) ON DELETE CASCADE',
        ),
      );
      expect(
        sqlAttachment,
        contains(
          'FOREIGN KEY (egreso_id) REFERENCES egreso (id) ON DELETE CASCADE',
        ),
      );
      expect(
        sqlAttachment,
        contains(
          '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN documento_por_emitir_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN pago_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN complemento_pago_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN ingreso_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN egreso_id IS NOT NULL THEN 1 ELSE 0 END) = 1',
        ),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 16 → 17 conserva un Pago real y crea las tablas de Ingreso/Egreso vacías (sin backfill)',
    () async {
      final schemaV16 = await verifier.schemaAt(16);
      final raw = schemaV16.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO pago (
        id, folio_pago, cliente_id, monto_total, monto_aplicado, fecha_pago, forma_pago,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'pago-real', 'PAG-000001', 'cliente-real', 500000, 500000, 1700000000, 'transferencia',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV16.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final pagos = await db.select(db.pago).get();
      expect(
        pagos,
        hasLength(1),
        reason: 'ningún Pago real debe perderse en una migración aditiva',
      );

      final ingresos = await db.select(db.ingreso).get();
      expect(ingresos, isEmpty, reason: 'Ingreso es tabla nueva en 4K.1, sin backfill automático del Pago existente');

      final egresos = await db.select(db.egreso).get();
      expect(egresos, isEmpty);

      final categorias = await db.select(db.categoriaFinanciera).get();
      expect(categorias, isEmpty, reason: 'el catálogo de CategoriaFinanciera nace vacío (Resolución de Marlon)');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'migración 12 → 17 conserva un Attachment real de Empresa y agrega ingresoId/egresoId en NULL',
    () async {
      final schemaV12 = await verifier.schemaAt(12);
      final raw = schemaV12.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empresa (id, codigo, nombre_comercial, created_at, updated_at, ciclo_vida_registro)
      VALUES ('empresa-real', 'RSG-01', 'RISEG', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO attachment (
        id, empresa_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
      ) VALUES (
        'attachment-real', 'empresa-real', 'logo.png', 'a1b2c3.png', '/attachments/a1b2c3.png',
        'image/png', 12345, 1700000000
      );
    ''');

      final db = AppDatabase(schemaV12.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final attachments = await db.select(db.attachment).get();
      expect(
        attachments,
        hasLength(1),
        reason: 'ningún Attachment real debe perderse en una migración aditiva',
      );
      expect(attachments.single.ingresoId, isNull);
      expect(attachments.single.egresoId, isNull);
      expect(attachments.single.empresaId, 'empresa-real');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la migración',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(integridad, [
        'ok',
      ], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'acepta un Ingreso automático con comprobante adjunto (Attachment con ingresoId) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      final ingreso = await db
          .into(db.ingreso)
          .insertReturning(
            IngresoCompanion.insert(
              pagoId: Value(pago.id),
              folioIngreso: 'ING-000001',
              monto: 500000,
              fecha: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
              concepto: 'Pago PAG-000001',
            ),
          );

      final adjunto = await db
          .into(db.attachment)
          .insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-ingreso',
              ingresoId: Value(ingreso.id),
              categoria: const Value('comprobante'),
              originalFileName: 'comprobante.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${ingreso.id}/comprobante/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
            ),
          );

      expect(adjunto.ingresoId, ingreso.id);
      expect(ingreso.estatus, 'registrado');

      await db.close();
    },
  );

  test(
    'rechaza un Attachment con ingresoId y otro dueño a la vez (arco de 7 vías) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final ingreso = await db
          .into(db.ingreso)
          .insertReturning(
            IngresoCompanion.insert(
              folioIngreso: 'ING-000001',
              monto: 100000,
              fecha: DateTime(2026, 1, 20),
              formaPago: 'efectivo',
              concepto: 'Ingreso manual',
            ),
          );

      expect(
        () => db.customStatement('''
        INSERT INTO attachment (
          id, cliente_id, ingreso_id, original_file_name, stored_file_name, path, mime_type, size_bytes, created_at
        ) VALUES (
          'attachment-doble-dueno', '${cliente.id}', '${ingreso.id}', 'a.pdf', 'x.pdf', '/x.pdf',
          'application/pdf', 100, 1700000000
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza un Ingreso con Pago inexistente tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO ingreso (
          id, pago_id, folio_ingreso, monto, fecha, forma_pago, concepto, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'ingreso-invalido', 'pago-inexistente', 'ING-000001', 100000, 1700000000, 'efectivo', 'Concepto', 'registrado',
          1700000000, 1700000000, 'activo'
        );
      '''),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza un segundo Ingreso para el mismo Pago tras la migración (pagoId UNIQUE)',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final pago = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 500000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );
      await db
          .into(db.ingreso)
          .insert(
            IngresoCompanion.insert(
              pagoId: Value(pago.id),
              folioIngreso: 'ING-000001',
              monto: 500000,
              fecha: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
              concepto: 'Pago PAG-000001',
            ),
          );

      expect(
        () => db
            .into(db.ingreso)
            .insert(
              IngresoCompanion.insert(
                pagoId: Value(pago.id),
                folioIngreso: 'ING-000002',
                monto: 500000,
                fecha: DateTime(2026, 1, 20),
                formaPago: 'transferencia',
                concepto: 'Duplicado',
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );
}
