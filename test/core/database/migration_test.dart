import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/migrations/migrar_cuenta_por_cobrar_v14.dart';
import 'package:riseg_one/core/database/seed/seed_data.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_identidad_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/regularizar_articulo_serializado_usecase.dart';

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
const _currentSchemaVersion = 46;

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
      expect(codigosSecuencia, hasLength(21));

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
      expect(
        attachments.single.estado,
        'activo',
        reason: 'las filas existentes deben quedar activas por defecto',
      );

      // Desde la Etapa 5A, el dueño ya no es una columna de `attachment`
      // — el backfill de la migración debió moverlo a `EmpresaAttachment`.
      final empresaAttachments = await db.select(db.empresaAttachment).get();
      expect(empresaAttachments, hasLength(1));
      expect(empresaAttachments.single.attachmentId, attachments.single.id);
      expect(empresaAttachments.single.empresaId, 'empresa-real');

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
              originalFileName: 'recibo enero.pdf',
              storedFileName: 'f1e2d3.pdf',
              path: '/attachments/${documento.id}/reciboPdf/f1e2d3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
              categoria: const Value('reciboPdf'),
            ),
          );
      await db
          .into(db.documentoPorEmitirAttachment)
          .insert(
            DocumentoPorEmitirAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              documentoPorEmitirId: documento.id,
            ),
          );

      expect(adjunto.estado, 'activo');
      expect(adjunto.categoria, 'reciboPdf');

      await db.close();
    },
  );

  // Desde la Etapa 5A, `attachment` ya no tiene columnas de dueño ni un
  // `CHECK` de "arco exclusivo" — cada dueño vive en su propia tabla
  // puente (ver el doc comment de `attachment_table.dart`). La
  // exclusividad de "un Attachment pertenece a lo más a un dueño *dentro
  // de una misma tabla puente*" ahora la garantiza la llave primaria
  // (`attachmentId`) de esa tabla puente — lo que antes eran las
  // pruebas "rechaza más de un dueño"/"rechaza sin dueño" del arco.
  test(
    'rechaza una segunda fila de unión para el mismo Attachment en la misma tabla puente (PK única)',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db
          .into(db.cliente)
          .insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final pagoA = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: cliente.id,
              montoTotal: 100000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'efectivo',
            ),
          );
      final pagoB = await db
          .into(db.pago)
          .insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000002',
              clienteId: cliente.id,
              montoTotal: 100000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'efectivo',
            ),
          );
      final adjunto = await db
          .into(db.attachment)
          .insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-unico',
              originalFileName: 'a.pdf',
              storedFileName: 'x.pdf',
              path: '/x.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 100,
            ),
          );
      await db.into(db.pagoAttachment).insert(PagoAttachmentCompanion.insert(attachmentId: adjunto.id, pagoId: pagoA.id));

      expect(
        () => db
            .into(db.pagoAttachment)
            .insert(PagoAttachmentCompanion.insert(attachmentId: adjunto.id, pagoId: pagoB.id)),
        throwsA(anything),
      );

      await db.close();
    },
  );

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
      // Desde la Etapa 5A, el dueño ya no es una columna de `attachment`
      // — el backfill de la migración debió moverlo a `EmpresaAttachment`.
      final empresaAttachments = await db.select(db.empresaAttachment).get();
      expect(empresaAttachments, hasLength(1));
      expect(empresaAttachments.single.attachmentId, attachments.single.id);

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
    'acepta un comprobante de pago (Attachment unido vía PagoAttachment) tras la migración',
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
              categoria: const Value('comprobante'),
              originalFileName: 'comprobante.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${pago.id}/comprobante/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
            ),
          );
      await db
          .into(db.pagoAttachment)
          .insert(PagoAttachmentCompanion.insert(attachmentId: adjunto.id, pagoId: pago.id));

      expect(adjunto.categoria, 'comprobante');

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
      final empresaAttachments = await db.select(db.empresaAttachment).get();
      expect(empresaAttachments, hasLength(1));
      expect(empresaAttachments.single.attachmentId, attachments.single.id);

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
    'acepta un Complemento de pago con archivo adjunto (Attachment unido vía ComplementoPagoAttachment) tras la migración',
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
              categoria: const Value('pdf'),
              originalFileName: 'complemento.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${complemento.id}/pdf/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
            ),
          );
      await db
          .into(db.complementoPagoAttachment)
          .insert(
            ComplementoPagoAttachmentCompanion.insert(attachmentId: adjunto.id, complementoPagoId: complemento.id),
          );

      expect(complemento.estatus, 'registrado');

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
      final empresaAttachments = await db.select(db.empresaAttachment).get();
      expect(empresaAttachments, hasLength(1));
      expect(empresaAttachments.single.attachmentId, attachments.single.id);

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
    'acepta un Ingreso automático con comprobante adjunto (Attachment unido vía IngresoAttachment) tras la migración',
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
              categoria: const Value('comprobante'),
              originalFileName: 'comprobante.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${ingreso.id}/comprobante/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 54321,
            ),
          );
      await db
          .into(db.ingresoAttachment)
          .insert(IngresoAttachmentCompanion.insert(attachmentId: adjunto.id, ingresoId: ingreso.id));

      expect(ingreso.estatus, 'registrado');

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

  test(
    '18.json coincide con el esquema final de la Etapa 5A (Empleado/EmpleadoEvento, Direccion de 6 vías, Attachment angosto + tablas puente)',
    () async {
      final schema = await verifier.schemaAt(18);
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
          'empleado',
          'empleado_evento',
          'empresa_attachment',
          'cliente_attachment',
          'documento_por_emitir_attachment',
          'pago_attachment',
          'complemento_pago_attachment',
          'ingreso_attachment',
          'egreso_attachment',
          'empleado_attachment',
        ]),
      );

      final sqlEmpleado =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado'")
                  .single['sql']
              as String;
      expect(sqlEmpleado, contains('"codigo_empleado" TEXT NOT NULL UNIQUE'));
      expect(sqlEmpleado, contains('CHECK (anios_experiencia_seguridad >= 0)'));
      expect(
        sqlEmpleado,
        contains(
          'CHECK (meses_experiencia_adicionales IS NULL OR '
          '(meses_experiencia_adicionales >= 0 AND meses_experiencia_adicionales <= 11))',
        ),
      );

      final sqlDireccion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'direccion'")
                  .single['sql']
              as String;
      expect(sqlDireccion, contains('"empleado_id" TEXT NULL UNIQUE'));
      expect(sqlDireccion, contains('FOREIGN KEY (empleado_id) REFERENCES empleado (id) ON DELETE RESTRICT'));
      expect(
        sqlDireccion,
        contains(
          '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN entidad_fiscal_id IS NOT NULL THEN 1 ELSE 0 END + '
          'CASE WHEN empleado_id IS NOT NULL THEN 1 ELSE 0 END) = 1',
        ),
      );
      expect(sqlDireccion, contains("CHECK (empleado_id IS NULL OR tipo_direccion = 'domicilio')"));

      final sqlAttachment =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attachment'")
                  .single['sql']
              as String;
      expect(sqlAttachment, isNot(contains('empresa_id')), reason: 'Attachment ya no tiene columnas de dueño');
      expect(sqlAttachment, isNot(contains('CHECK')), reason: 'el arco exclusivo desapareció junto con las columnas');

      final sqlPagoAttachment =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pago_attachment'")
                  .single['sql']
              as String;
      expect(sqlPagoAttachment, contains('REFERENCES attachment (id) ON DELETE CASCADE'));
      expect(sqlPagoAttachment, contains('REFERENCES pago (id) ON DELETE CASCADE'));
      expect(sqlPagoAttachment, contains('PRIMARY KEY ("attachment_id")'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 17 → 18 conserva un Pago real y crea las tablas de Empleado vacías, Direccion con empleadoId en NULL (sin backfill)',
    () async {
      final schemaV17 = await verifier.schemaAt(17);
      final raw = schemaV17.rawDatabase;

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

      final db = AppDatabase(schemaV17.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final pagos = await db.select(db.pago).get();
      expect(pagos, hasLength(1), reason: 'ningún Pago real debe perderse en una migración aditiva');

      final empleados = await db.select(db.empleado).get();
      expect(empleados, isEmpty, reason: 'Empleado es tabla nueva en 5A, sin backfill');

      final direcciones = await db.select(db.direccion).get();
      for (final d in direcciones) {
        expect(d.empleadoId, isNull);
      }

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'acepta un Empleado con domicilio y documento adjunto (Direccion + EmpleadoAttachment) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );

      final domicilio = await db
          .into(db.direccion)
          .insertReturning(
            DireccionCompanion.insert(
              empleadoId: Value(empleado.id),
              tipoDireccion: 'domicilio',
              calle: 'Calle Real',
              numeroExterior: '10',
              colonia: 'Centro',
              municipioAlcaldia: 'Toluca',
              estado: 'Estado de México',
              codigoPostal: '50000',
            ),
          );
      expect(domicilio.empleadoId, empleado.id);

      final adjunto = await db
          .into(db.attachment)
          .insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-empleado',
              categoria: const Value('ine'),
              originalFileName: 'ine.pdf',
              storedFileName: 'x1y2z3.pdf',
              path: '/attachments/${empleado.id}/ine/x1y2z3.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 12345,
            ),
          );
      await db
          .into(db.empleadoAttachment)
          .insert(EmpleadoAttachmentCompanion.insert(attachmentId: adjunto.id, empleadoId: empleado.id));

      final documentos = await db.select(db.empleadoAttachment).get();
      expect(documentos, hasLength(1));
      expect(documentos.single.empleadoId, empleado.id);

      await db.close();
    },
  );

  test(
    'rechaza un Empleado con Puesto inexistente tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.into(db.empleado).insert(
              EmpleadoCompanion.insert(
                numeroEmpleado: 1,
                nombres: 'Juan',
                apellidoPaterno: 'Pérez',
                sexo: 'masculino',
                fechaNacimiento: DateTime(1990, 1, 1),
                curp: 'PEXJ900101HDFXXX01',
                rfc: 'PEXJ900101AB1',
                nss: '12345678901',
                estadoCivil: 'soltero',
                fechaIngreso: DateTime(2026, 1, 1),
                aniosExperienciaSeguridad: 3,
                puestoId: const Value('puesto-inexistente'),
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    'rechaza una segunda Direccion de tipo domicilio para el mismo Empleado tras la migración (empleadoId UNIQUE)',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      await db.into(db.direccion).insert(
            DireccionCompanion.insert(
              empleadoId: Value(empleado.id),
              tipoDireccion: 'domicilio',
              calle: 'Calle Real',
              numeroExterior: '10',
              colonia: 'Centro',
              municipioAlcaldia: 'Toluca',
              estado: 'Estado de México',
              codigoPostal: '50000',
            ),
          );

      expect(
        () => db.into(db.direccion).insert(
              DireccionCompanion.insert(
                empleadoId: Value(empleado.id),
                tipoDireccion: 'domicilio',
                calle: 'Otra calle',
                numeroExterior: '20',
                colonia: 'Centro',
                municipioAlcaldia: 'Toluca',
                estado: 'Estado de México',
                codigoPostal: '50000',
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '19.json coincide con el esquema final de la Etapa 5B (13 columnas nuevas nullable en Empleado, sin tablas nuevas)',
    () async {
      final schema = await verifier.schemaAt(19);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      // Sin tablas nuevas — 5B solo agrega columnas a Empleado.
      expect(tablas, contains('empleado'));
      expect(tablas, isNot(contains('empleado_evaluacion')), reason: 'sin tablas satélite, sin historial de evaluaciones');

      final columnasNuevas = [
        'fecha_evaluacion_psicologica',
        'resumen_psicologico',
        'observaciones_psicologico',
        'fecha_estudio_socioeconomico',
        'resumen_estudio_socioeconomico',
        'observaciones_estudio_socioeconomico',
        'fecha_antidoping',
        'resultado_amp',
        'resultado_bzd',
        'resultado_coc',
        'resultado_met',
        'resultado_opi',
        'observaciones_antidoping',
      ];
      final columnasEmpleado = schema.rawDatabase.select('PRAGMA table_info(empleado)').toList();
      for (final nombre in columnasNuevas) {
        final columna = columnasEmpleado.firstWhere(
          (c) => c['name'] == nombre,
          orElse: () => throw StateError('Falta la columna $nombre en empleado (19.json)'),
        );
        expect(columna['notnull'], 0, reason: '$nombre debe ser nullable');
      }

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 18 → 19 conserva un Empleado real y deja las 13 columnas nuevas en NULL (sin backfill)',
    () async {
      final schemaV18 = await verifier.schemaAt(18);
      final raw = schemaV18.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 'EMP-000001', 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV18.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleados = await db.select(db.empleado).get();
      expect(empleados, hasLength(1), reason: 'ningún Empleado real debe perderse en una migración aditiva');
      final empleado = empleados.single;
      expect(empleado.numeroEmpleado, 1);
      expect(empleado.fechaEvaluacionPsicologica, isNull);
      expect(empleado.resumenPsicologico, isNull);
      expect(empleado.fechaEstudioSocioeconomico, isNull);
      expect(empleado.fechaAntidoping, isNull);
      expect(empleado.resultadoAmp, isNull);
      expect(empleado.resultadoOpi, isNull);

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'acepta un Empleado con Perfil psicológico/Estudio socioeconómico/Antidoping capturados tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
              fechaEvaluacionPsicologica: const Value(null),
            ),
          );

      final actualizado = await (db.update(db.empleado)..where((t) => t.id.equals(empleado.id))).writeReturning(
        EmpleadoCompanion(
          fechaEvaluacionPsicologica: Value(DateTime(2026, 1, 15)),
          resumenPsicologico: const Value('Resumen'),
          fechaEstudioSocioeconomico: Value(DateTime(2026, 1, 20)),
          fechaAntidoping: Value(DateTime(2026, 1, 25)),
          resultadoAmp: const Value('negativo'),
          resultadoBzd: const Value('negativo'),
          resultadoCoc: const Value('positivo'),
          resultadoMet: const Value('noAplica'),
          resultadoOpi: const Value('noAplica'),
        ),
      );

      expect(actualizado.single.resultadoCoc, 'positivo');
      expect(actualizado.single.resultadoMet, 'noAplica');

      await db.close();
    },
  );

  test(
    '20.json coincide con el esquema final de la Etapa 5C (3 columnas de baja en Empleado + tabla nueva EmpleadoPeriodoLaboral)',
    () async {
      final schema = await verifier.schemaAt(20);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('empleado'));
      expect(tablas, contains('empleado_periodo_laboral'));

      final columnasEmpleado = schema.rawDatabase.select('PRAGMA table_info(empleado)').toList();
      for (final nombre in ['fecha_baja', 'motivo_baja', 'observaciones_baja']) {
        final columna = columnasEmpleado.firstWhere(
          (c) => c['name'] == nombre,
          orElse: () => throw StateError('Falta la columna $nombre en empleado (20.json)'),
        );
        expect(columna['notnull'], 0, reason: '$nombre debe ser nullable');
      }

      final sqlPeriodo =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado_periodo_laboral'")
                  .single['sql']
              as String;
      expect(sqlPeriodo, contains('"empleado_id" TEXT NOT NULL REFERENCES empleado (id) ON DELETE CASCADE'));
      expect(sqlPeriodo, contains('"fecha_ingreso" INTEGER NOT NULL'));
      expect(sqlPeriodo, contains('"fecha_baja" INTEGER NOT NULL'));
      expect(sqlPeriodo, contains('"motivo_baja" TEXT NOT NULL'));
      expect(sqlPeriodo, contains('CHECK (fecha_baja >= fecha_ingreso)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 19 → 20 conserva un Empleado real (incluso ya de baja, sin fechaBaja legado) y crea EmpleadoPeriodoLaboral vacía',
    () async {
      final schemaV19 = await verifier.schemaAt(19);
      final raw = schemaV19.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 'EMP-000001', 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');
      // Simula un Empleado que ya estaba de baja bajo el viejo
      // CambiarEstatusEmpleadoUseCase (previo a esta etapa) — nunca tuvo
      // fechaBaja/motivoBaja estructurados. La migración es puramente
      // aditiva y no hace backfill: debe sobrevivir con esos campos en
      // NULL, sin lanzar.
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-baja-legado', 'EMP-000002', 'Ana', 'García', 'femenino', 631152000, 'GAAA900101MDFXXX02',
        'GAAA900101AB2', '12345678902', 'soltera', 1735689600, 2, 'baja',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV19.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleados = await db.select(db.empleado).get();
      expect(empleados, hasLength(2), reason: 'ningún Empleado real debe perderse en una migración aditiva');

      final empleado = empleados.firstWhere((e) => e.id == 'empleado-real');
      expect(empleado.fechaBaja, isNull);
      expect(empleado.motivoBaja, isNull);
      expect(empleado.observacionesBaja, isNull);

      final legado = empleados.firstWhere((e) => e.id == 'empleado-baja-legado');
      expect(legado.estatus, 'baja');
      expect(legado.fechaBaja, isNull, reason: 'sin backfill — invariante de aplicación, no de BD');

      final periodos = await db.select(db.empleadoPeriodoLaboral).get();
      expect(periodos, isEmpty, reason: 'EmpleadoPeriodoLaboral es tabla nueva en 5C, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'acepta un ciclo completo de baja + reingreso (archiva el periodo cerrado) tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );

      await (db.update(db.empleado)..where((t) => t.id.equals(empleado.id))).write(
        EmpleadoCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(DateTime(2026, 6, 15)),
          motivoBaja: const Value('renuncia'),
        ),
      );

      await db.into(db.empleadoPeriodoLaboral).insert(
            EmpleadoPeriodoLaboralCompanion.insert(
              empleadoId: empleado.id,
              fechaIngreso: DateTime(2026, 1, 1),
              fechaBaja: DateTime(2026, 6, 15),
              motivoBaja: 'renuncia',
            ),
          );

      final periodos = await (db.select(db.empleadoPeriodoLaboral)..where((t) => t.empleadoId.equals(empleado.id))).get();
      expect(periodos, hasLength(1));
      expect(periodos.single.motivoBaja, 'renuncia');

      await db.close();
    },
  );

  test(
    'EmpleadoPeriodoLaboral rechaza fechaBaja anterior a fechaIngreso tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );

      expect(
        () => db.into(db.empleadoPeriodoLaboral).insert(
              EmpleadoPeriodoLaboralCompanion.insert(
                empleadoId: empleado.id,
                fechaIngreso: DateTime(2026, 6, 15),
                fechaBaja: DateTime(2026, 1, 1),
                motivoBaja: 'renuncia',
              ),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '21.json coincide con el esquema final de la Etapa 5D (tabla nueva AsignacionServicio + índice único parcial, codigoPostalFiscal en Empleado)',
    () async {
      final schema = await verifier.schemaAt(21);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('asignacion_servicio'));

      final columnaCp = schema.rawDatabase
          .select('PRAGMA table_info(empleado)')
          .firstWhere((c) => c['name'] == 'codigo_postal_fiscal', orElse: () => throw StateError('Falta codigo_postal_fiscal'));
      expect(columnaCp['notnull'], 0, reason: 'codigo_postal_fiscal debe ser nullable');

      final sqlAsignacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_servicio'")
                  .single['sql']
              as String;
      expect(sqlAsignacion, contains('"empleado_id" TEXT NOT NULL REFERENCES empleado (id)'));
      expect(sqlAsignacion, contains('"servicio_id" TEXT NOT NULL REFERENCES servicio (id)'));
      expect(sqlAsignacion, contains('"turno_id" TEXT NULL REFERENCES tipo_modalidad_turno (id)'));
      expect(sqlAsignacion, contains('"fecha_termino" INTEGER NULL'));
      expect(sqlAsignacion, contains('CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)'));

      final sqlIndice =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_asignacion_servicio_empleado_activa'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndice,
        'CREATE UNIQUE INDEX idx_asignacion_servicio_empleado_activa '
        'ON asignacion_servicio (empleado_id) WHERE fecha_termino IS NULL',
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 20 → 21 conserva un Empleado y Servicio reales y crea AsignacionServicio vacía',
    () async {
      final schemaV20 = await verifier.schemaAt(20);
      final raw = schemaV20.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 'EMP-000001', 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
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
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-real', 'SER-000001', 'cliente-real', 'Vigilancia Sportium Toluca', 'tipo-servicio-real',
        'activo', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV20.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleados = await db.select(db.empleado).get();
      expect(empleados, hasLength(1), reason: 'ningún Empleado real debe perderse en una migración aditiva');
      expect(empleados.single.codigoPostalFiscal, isNull);

      final servicios = await db.select(db.servicio).get();
      expect(servicios, hasLength(1), reason: 'ningún Servicio real debe perderse en una migración aditiva');

      final asignaciones = await db.select(db.asignacionServicio).get();
      expect(asignaciones, isEmpty, reason: 'AsignacionServicio es tabla nueva en 5D, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'el índice único parcial de AsignacionServicio rechaza una segunda asignación vigente para el mismo Empleado tras la migración',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      final cliente = await db
          .into(db.cliente)
          .insertReturning(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
      final servicioA = await db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Servicio A',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final servicioB = await db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000002',
              clienteId: cliente.id,
              nombre: 'Servicio B',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );

      await db.into(db.asignacionServicio).insert(
            AsignacionServicioCompanion.insert(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2026, 1, 1)),
          );

      expect(
        () => db.into(db.asignacionServicio).insert(
              AsignacionServicioCompanion.insert(empleadoId: empleado.id, servicioId: servicioB.id, fechaInicio: DateTime(2026, 2, 1)),
            ),
        throwsA(anything),
      );

      await db.close();
    },
  );

  test(
    '22.json coincide con el esquema final de la Etapa 5E (tabla nueva FichaTecnicaEmpleado)',
    () async {
      final schema = await verifier.schemaAt(22);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('ficha_tecnica_empleado'));

      final sqlFicha =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'ficha_tecnica_empleado'")
                  .single['sql']
              as String;
      expect(sqlFicha, contains('"folio" TEXT NOT NULL UNIQUE'));
      expect(sqlFicha, contains('"empleado_id" TEXT NOT NULL REFERENCES empleado (id)'));
      expect(sqlFicha, contains('"servicio_id" TEXT NULL REFERENCES servicio (id)'));
      expect(sqlFicha, contains('"attachment_id" TEXT NOT NULL REFERENCES attachment (id)'));
      expect(sqlFicha, contains('"campos_excluidos" TEXT NULL'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 21 → 22 conserva un Empleado real y crea FichaTecnicaEmpleado vacía',
    () async {
      final schemaV21 = await verifier.schemaAt(21);
      final raw = schemaV21.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 'EMP-000001', 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV21.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleados = await db.select(db.empleado).get();
      expect(empleados, hasLength(1), reason: 'ningún Empleado real debe perderse en una migración aditiva');

      final codigoFichaTecnica =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('ficha_tecnica'))).getSingleOrNull();
      expect(codigoFichaTecnica, isNotNull, reason: 'runSeed debe sembrar el contador de folio de ficha_tecnica');
      expect(codigoFichaTecnica!.prefijo, 'FICHA');

      final fichas = await db.select(db.fichaTecnicaEmpleado).get();
      expect(fichas, isEmpty, reason: 'FichaTecnicaEmpleado es tabla nueva en 5E, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    '23.json coincide con el esquema final de la Etapa 6A (numeroEmpleado + datos bancarios + '
    'condición administrativa en Empleado, catálogo Banco)',
    () async {
      final schema = await verifier.schemaAt(23);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('banco'));

      final sqlEmpleado =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado'")
                  .single['sql']
              as String;
      expect(sqlEmpleado, isNot(contains('codigo_empleado')));
      expect(sqlEmpleado, contains('"numero_empleado" INTEGER NOT NULL UNIQUE'));
      expect(sqlEmpleado, contains('"banco_id" TEXT NULL REFERENCES banco (id)'));
      expect(sqlEmpleado, contains('"numero_cuenta_tarjeta" TEXT NULL'));
      expect(sqlEmpleado, contains('"clabe" TEXT NULL'));
      expect(sqlEmpleado, contains('CHECK (sueldo_mensual_administrativo IS NULL OR sueldo_mensual_administrativo > 0)'));
      expect(sqlEmpleado, contains('CHECK (bono_mensual_administrativo IS NULL OR bono_mensual_administrativo >= 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 22 → 23 conserva Empleados reales, asigna numeroEmpleado consecutivo por orden de alta y siembra Banco',
    () async {
      final schemaV22 = await verifier.schemaAt(22);
      final raw = schemaV22.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      // Dos Empleados reales, insertados en orden inverso a su
      // `created_at` real — el backfill debe respetar `created_at`, no
      // el orden físico de inserción en esta migración.
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-2', 'EMP-000002', 'Ana', 'García', 'femenino', 631152000, 'GAGA900101MDFXXX02',
        'GAGA900101AB2', '10000000002', 'soltero', 1735689600, 2, 'activo',
        1700000100, 1700000100, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, codigo_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-1', 'EMP-000001', 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '10000000001', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV22.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleados = await db.select(db.empleado).get()
        ..sort((a, b) => a.numeroEmpleado.compareTo(b.numeroEmpleado));
      expect(empleados, hasLength(2), reason: 'ningún Empleado real debe perderse en una migración estructural');
      expect(empleados[0].id, 'empleado-1', reason: 'creado primero (created_at menor) → numeroEmpleado 1');
      expect(empleados[0].numeroEmpleado, 1);
      expect(empleados[1].id, 'empleado-2');
      expect(empleados[1].numeroEmpleado, 2);
      expect(empleados[0].bancoId, isNull);
      expect(empleados[0].sueldoMensualAdministrativo, isNull);

      final bancos = await db.select(db.banco).get();
      expect(bancos, isNotEmpty, reason: 'runSeed/seedBanco debe sembrar el catálogo Banco en la migración');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de sueldo/bono administrativo tras la migración: sueldo debe ser > 0, bono acepta 0',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final base = EmpleadoCompanion.insert(
        numeroEmpleado: 1,
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: 'masculino',
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: 'soltero',
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 0,
      );

      await expectLater(
        db.into(db.empleado).insert(base.copyWith(sueldoMensualAdministrativo: const Value(0))),
        throwsA(anything),
        reason: 'sueldo_mensual_administrativo = 0 debe rechazarse (debe ser > 0)',
      );

      final conBonoCero = await db.into(db.empleado).insertReturning(
            base.copyWith(bonoMensualAdministrativo: const Value(0)),
          );
      expect(conBonoCero.bonoMensualAdministrativo, 0, reason: 'bono_mensual_administrativo = 0 sí es válido');

      await db.close();
    },
  );

  test(
    '24.json coincide con el esquema final de la Etapa 6B (sueldo/bono de referencia en Servicio, '
    'tabla nueva AsignacionServicioSueldoVigencia)',
    () async {
      final schema = await verifier.schemaAt(24);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('asignacion_servicio_sueldo_vigencia'));

      final sqlServicio =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio'")
                  .single['sql']
              as String;
      expect(sqlServicio, contains('CHECK (sueldo_mensual_referencia_personal IS NULL OR sueldo_mensual_referencia_personal > 0)'));
      expect(sqlServicio, contains('CHECK (bono_mensual_referencia_personal IS NULL OR bono_mensual_referencia_personal >= 0)'));

      final sqlVigencia =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_servicio_sueldo_vigencia'",
                  )
                  .single['sql']
              as String;
      expect(sqlVigencia, contains('"asignacion_servicio_id" TEXT NOT NULL REFERENCES asignacion_servicio (id)'));
      expect(sqlVigencia, contains('CHECK (sueldo_mensual > 0)'));
      expect(sqlVigencia, contains('CHECK (bono_mensual >= 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 23 → 24 conserva un Servicio real (columnas nuevas en NULL) y crea AsignacionServicioSueldoVigencia vacía',
    () async {
      final schemaV23 = await verifier.schemaAt(23);
      final raw = schemaV23.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-real', 'SER-000001', 'cliente-real', 'Vigilancia Sportium Toluca', '${SeedIds.tipoServicioVigilanciaFija}',
        'activo', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV23.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final servicios = await db.select(db.servicio).get();
      expect(servicios, hasLength(1), reason: 'ningún Servicio real debe perderse en una migración estructural');
      expect(servicios.single.id, 'servicio-real');
      expect(servicios.single.sueldoMensualReferenciaPersonal, isNull);
      expect(servicios.single.bonoMensualReferenciaPersonal, isNull);

      final vigenciasSueldo = await db.select(db.asignacionServicioSueldoVigencia).get();
      expect(vigenciasSueldo, isEmpty, reason: 'AsignacionServicioSueldoVigencia es tabla nueva en 6B, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de sueldo/bono de referencia y de vigencia de sueldo tras la migración: sueldo debe ser > 0, bono acepta 0',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final baseServicio = ServicioCompanion.insert(
        codigo: 'SER-000001',
        clienteId: cliente.id,
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      );

      await expectLater(
        db.into(db.servicio).insert(baseServicio.copyWith(sueldoMensualReferenciaPersonal: const Value(0))),
        throwsA(anything),
        reason: 'sueldo_mensual_referencia_personal = 0 debe rechazarse (debe ser > 0)',
      );

      final servicio = await db.into(db.servicio).insertReturning(
            baseServicio.copyWith(
              sueldoMensualReferenciaPersonal: const Value(1500000),
              bonoMensualReferenciaPersonal: const Value(0),
            ),
          );
      expect(servicio.bonoMensualReferenciaPersonal, 0, reason: 'bono_mensual_referencia_personal = 0 sí es válido');

      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 0,
            ),
          );
      final asignacion = await db.into(db.asignacionServicio).insertReturning(
            AsignacionServicioCompanion.insert(
              empleadoId: empleado.id,
              servicioId: servicio.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final baseVigencia = AsignacionServicioSueldoVigenciaCompanion.insert(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1500000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );

      await expectLater(
        db.into(db.asignacionServicioSueldoVigencia).insert(baseVigencia.copyWith(sueldoMensual: const Value(0))),
        throwsA(anything),
        reason: 'sueldo_mensual = 0 debe rechazarse (debe ser > 0) en AsignacionServicioSueldoVigencia',
      );

      final vigencia = await db.into(db.asignacionServicioSueldoVigencia).insertReturning(
            baseVigencia.copyWith(bonoMensual: const Value(0)),
          );
      expect(vigencia.bonoMensual, 0, reason: 'bono_mensual = 0 sí es válido en AsignacionServicioSueldoVigencia');

      await db.close();
    },
  );

  test(
    '25.json coincide con el esquema final de la Etapa 6C (tablas nuevas Nomina, NominaEmpleado, '
    'NominaEmpleadoTramo, NominaEvento)',
    () async {
      final schema = await verifier.schemaAt(25);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['nomina', 'nomina_empleado', 'nomina_empleado_tramo', 'nomina_evento']));

      final sqlNomina =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'nomina'")
                  .single['sql']
              as String;
      expect(sqlNomina, contains('UNIQUE (anio, mes, tipo_periodo)'));
      expect(sqlNomina, contains('"folio" TEXT NOT NULL UNIQUE'));
      expect(sqlNomina, contains('CHECK (mes >= 1 AND mes <= 12)'));

      final sqlNominaEmpleado =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'nomina_empleado'")
                  .single['sql']
              as String;
      expect(sqlNominaEmpleado, contains('UNIQUE (nomina_id, empleado_id)'));
      expect(sqlNominaEmpleado, contains('CHECK (dias_pagables >= 0)'));
      expect(sqlNominaEmpleado, contains('CHECK (sueldo_mensual_utilizado > 0)'));
      // Deliberadamente sin CHECK monto_fiscal + monto_no_fiscal == total_a_pagar
      // (Resolución explícita de Marlon: debe poder existir una distribución
      // temporalmente pendiente de revisar sin que la escritura falle).
      expect(sqlNominaEmpleado, isNot(contains('monto_fiscal + monto_no_fiscal')));

      final sqlNominaEmpleadoTramo =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'nomina_empleado_tramo'")
                  .single['sql']
              as String;
      expect(sqlNominaEmpleadoTramo, contains('CHECK (dias_reales > 0)'));
      expect(sqlNominaEmpleadoTramo, contains('CHECK (sueldo_mensual > 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 24 → 25 conserva un Empleado/Servicio real y crea las 4 tablas de Nómina vacías, sembrando '
    'CodigoSecuencia(nomina)',
    () async {
      final schemaV24 = await verifier.schemaAt(24);
      final raw = schemaV24.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '10000000001', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV24.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleados = await db.select(db.empleado).get();
      expect(empleados, hasLength(1), reason: 'ningún Empleado real debe perderse en una migración puramente aditiva');
      expect(empleados.single.id, 'empleado-real');

      final nominas = await db.select(db.nomina).get();
      expect(nominas, isEmpty, reason: 'Nomina es tabla nueva en 6C, sin backfill');
      final renglones = await db.select(db.nominaEmpleado).get();
      expect(renglones, isEmpty);
      final tramos = await db.select(db.nominaEmpleadoTramo).get();
      expect(tramos, isEmpty);
      final eventos = await db.select(db.nominaEvento).get();
      expect(eventos, isEmpty);

      final codigoNomina =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('nomina'))).getSingleOrNull();
      expect(codigoNomina, isNotNull, reason: 'runSeed debe sembrar el contador de folio de nomina');
      expect(codigoNomina!.prefijo, 'NOM');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de Nomina/NominaEmpleado/NominaEmpleadoTramo tras la migración: unicidad de periodo, distribución '
    'pendiente permitida temporalmente, importe_tramo >= 0',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nomina = await db.into(db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: 'NOM-000001',
              anio: 2026,
              mes: 1,
              tipoPeriodo: 'primera',
              fechaInicioPeriodo: DateTime(2026, 1, 1),
              fechaFinPeriodo: DateTime(2026, 1, 15),
              fechaPagoOrdinaria: DateTime(2026, 1, 20),
            ),
          );

      await expectLater(
        db.into(db.nomina).insert(
              NominaCompanion.insert(
                folio: 'NOM-000002',
                anio: 2026,
                mes: 1,
                tipoPeriodo: 'primera',
                fechaInicioPeriodo: DateTime(2026, 1, 1),
                fechaFinPeriodo: DateTime(2026, 1, 15),
                fechaPagoOrdinaria: DateTime(2026, 1, 20),
              ),
            ),
        throwsA(anything),
        reason: 'una segunda Nómina para el mismo (anio, mes, tipo_periodo) debe rechazarse',
      );

      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 0,
            ),
          );

      final baseRenglon = NominaEmpleadoCompanion.insert(
        nominaId: nomina.id,
        empleadoId: empleado.id,
        numeroEmpleado: 1,
        nombreCompleto: 'Juan Pérez',
        fuenteSueldoUtilizada: 'administrativo',
        diasPagables: 15,
        sueldoMensualUtilizado: 1500000,
        sueldoQuincenalReferencia: 750000,
        pagoPorDia: 50000,
        importeBase: 750000,
        totalAPagar: 750000,
      );

      // Distribución temporalmente pendiente de revisar (fiscal + no fiscal
      // no suman el total) — debe poder escribirse sin fallar a nivel de
      // base de datos; el bloqueo real vive en `CerrarNominaUseCase`.
      final renglonPendiente = await db.into(db.nominaEmpleado).insertReturning(
            baseRenglon.copyWith(
              montoFiscal: const Value(100000),
              montoNoFiscal: const Value(0),
              distribucionPendienteRevision: const Value(true),
            ),
          );
      expect(renglonPendiente.distribucionPendienteRevision, isTrue);

      await expectLater(
        db.into(db.nominaEmpleadoTramo).insert(
              NominaEmpleadoTramoCompanion.insert(
                nominaEmpleadoId: renglonPendiente.id,
                fechaInicio: DateTime(2026, 1, 1),
                fechaFin: DateTime(2026, 1, 15),
                fuenteSueldo: 'administrativo',
                sueldoMensual: 1500000,
                bonoMensual: 0,
                diasReales: 15,
                importeTramo: -1,
              ),
            ),
        throwsA(anything),
        reason: 'importe_tramo negativo debe rechazarse',
      );

      await db.close();
    },
  );

  test(
    '26.json coincide con el esquema final de la Etapa 6D (tablas nuevas PagoNomina, AplicacionPagoNomina, '
    'PagoNominaEvento, PagoNominaAttachment)',
    () async {
      final schema = await verifier.schemaAt(26);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(['pago_nomina', 'aplicacion_pago_nomina', 'pago_nomina_evento', 'pago_nomina_attachment']),
      );

      final sqlPagoNomina =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pago_nomina'")
                  .single['sql']
              as String;
      expect(sqlPagoNomina, contains('"folio_pago_nomina" TEXT NOT NULL UNIQUE'));
      expect(sqlPagoNomina, contains('"egreso_id" TEXT NULL UNIQUE REFERENCES egreso (id)'));
      expect(sqlPagoNomina, contains('CHECK (monto_total > 0)'));

      final sqlAplicacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'aplicacion_pago_nomina'")
                  .single['sql']
              as String;
      expect(sqlAplicacion, contains('"nomina_empleado_id" TEXT NOT NULL REFERENCES nomina_empleado (id)'));
      expect(sqlAplicacion, contains('CHECK (monto > 0)'));
      expect(sqlAplicacion, contains('CHECK (saldo_despues = saldo_antes - monto)'));
      expect(sqlAplicacion, contains('CHECK (saldo_despues >= 0)'));

      // Confirma la dirección deliberada de la FK: PagoNomina (tabla
      // nueva) referencia a Egreso (tabla ya existente desde 4K.1) —
      // Egreso mismo no gana ninguna columna nueva en esta etapa.
      final sqlEgreso =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'egreso'")
                  .single['sql']
              as String;
      expect(sqlEgreso, isNot(contains('pago_nomina')));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 25 → 26 conserva una Nómina/NominaEmpleado real y crea las tablas de PagoNomina vacías, sembrando '
    'CodigoSecuencia(pago_nomina)',
    () async {
      final schemaV25 = await verifier.schemaAt(25);
      final raw = schemaV25.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-real', 'NOM-000001', 2026, 1, 'primera', 1735689600, 1736812800, 1737331200,
        'cerrada', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV25.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nominas = await db.select(db.nomina).get();
      expect(nominas, hasLength(1), reason: 'ninguna Nómina real debe perderse en una migración puramente aditiva');
      expect(nominas.single.id, 'nomina-real');

      final pagos = await db.select(db.pagoNomina).get();
      expect(pagos, isEmpty, reason: 'PagoNomina es tabla nueva en 6D, sin backfill');
      final aplicaciones = await db.select(db.aplicacionPagoNomina).get();
      expect(aplicaciones, isEmpty);
      final eventos = await db.select(db.pagoNominaEvento).get();
      expect(eventos, isEmpty);

      final codigoPagoNomina =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('pago_nomina'))).getSingleOrNull();
      expect(codigoPagoNomina, isNotNull, reason: 'runSeed debe sembrar el contador de folio de pago_nomina');
      expect(codigoPagoNomina!.prefijo, 'PAGN');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de PagoNomina/AplicacionPagoNomina tras la migración: monto_total > 0, saldo nunca negativo, '
    'la aritmética del saldo debe cuadrar exactamente',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nomina = await db.into(db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: 'NOM-000001',
              anio: 2026,
              mes: 1,
              tipoPeriodo: 'primera',
              fechaInicioPeriodo: DateTime(2026, 1, 1),
              fechaFinPeriodo: DateTime(2026, 1, 15),
              fechaPagoOrdinaria: DateTime(2026, 1, 20),
              estatus: const Value('cerrada'),
            ),
          );
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 0,
            ),
          );
      final renglon = await db.into(db.nominaEmpleado).insertReturning(
            NominaEmpleadoCompanion.insert(
              nominaId: nomina.id,
              empleadoId: empleado.id,
              numeroEmpleado: 1,
              nombreCompleto: 'Juan Pérez',
              fuenteSueldoUtilizada: 'administrativo',
              diasPagables: 15,
              sueldoMensualUtilizado: 1500000,
              sueldoQuincenalReferencia: 750000,
              pagoPorDia: 50000,
              importeBase: 750000,
              totalAPagar: 750000,
            ),
          );

      await expectLater(
        db.into(db.pagoNomina).insert(
              PagoNominaCompanion.insert(
                folioPagoNomina: 'PAGN-000001',
                nominaId: nomina.id,
                montoTotal: 0,
                fechaPago: DateTime(2026, 1, 20),
                formaPago: 'transferencia',
              ),
            ),
        throwsA(anything),
        reason: 'monto_total = 0 debe rechazarse (debe ser > 0)',
      );

      final pagoNomina = await db.into(db.pagoNomina).insertReturning(
            PagoNominaCompanion.insert(
              folioPagoNomina: 'PAGN-000001',
              nominaId: nomina.id,
              montoTotal: 750000,
              fechaPago: DateTime(2026, 1, 20),
              formaPago: 'transferencia',
            ),
          );

      final baseAplicacion = AplicacionPagoNominaCompanion.insert(
        pagoNominaId: pagoNomina.id,
        nominaEmpleadoId: renglon.id,
        monto: 750000,
        saldoAntes: 750000,
        saldoDespues: 0,
      );

      await expectLater(
        db.into(db.aplicacionPagoNomina).insert(baseAplicacion.copyWith(saldoDespues: const Value(1))),
        throwsA(anything),
        reason: 'saldo_despues debe cuadrar exactamente con saldo_antes - monto',
      );
      await expectLater(
        db.into(db.aplicacionPagoNomina).insert(
              baseAplicacion.copyWith(monto: const Value(800000), saldoAntes: const Value(750000), saldoDespues: const Value(-50000)),
            ),
        throwsA(anything),
        reason: 'saldo_despues nunca puede quedar negativo (nunca se sobrepaga un renglón)',
      );

      final aplicacion = await db.into(db.aplicacionPagoNomina).insertReturning(baseAplicacion);
      expect(aplicacion.saldoDespues, 0);

      await db.close();
    },
  );

  test(
    '27.json coincide con el esquema final de la Etapa 7A (tablas nuevas CategoriaArticulo, Articulo, '
    'ArticuloVariante, ArticuloUnidad, ArticuloUnidadTelefono, MovimientoInventario, MovimientoInventarioAttachment)',
    () async {
      final schema = await verifier.schemaAt(27);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll([
          'categoria_articulo',
          'articulo',
          'articulo_variante',
          'articulo_unidad',
          'articulo_unidad_telefono',
          'movimiento_inventario',
          'movimiento_inventario_attachment',
        ]),
      );

      final sqlArticulo =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo'")
                  .single['sql']
              as String;
      expect(sqlArticulo, contains('"folio" TEXT NOT NULL UNIQUE'));
      expect(sqlArticulo, contains('CHECK (costo_referencia IS NULL OR costo_referencia >= 0)'));

      final sqlVariante =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo_variante'")
                  .single['sql']
              as String;
      expect(sqlVariante, contains('UNIQUE (articulo_id, valor)'));

      final sqlMovimiento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'movimiento_inventario'")
                  .single['sql']
              as String;
      expect(sqlMovimiento, contains('CHECK (variante_id IS NULL OR unidad_id IS NULL)'));
      expect(sqlMovimiento, contains('CHECK (cantidad > 0)'));
      expect(sqlMovimiento, contains('CHECK (unidad_id IS NULL OR cantidad = 1)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 26 → 27 conserva una Nómina real y crea las tablas de Inventario vacías, sembrando '
    'CodigoSecuencia(articulo)/CodigoSecuencia(articulo_unidad)',
    () async {
      final schemaV26 = await verifier.schemaAt(26);
      final raw = schemaV26.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-real', 'NOM-000001', 2026, 1, 'primera', 1735689600, 1736812800, 1737331200,
        'cerrada', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV26.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nominas = await db.select(db.nomina).get();
      expect(nominas, hasLength(1), reason: 'ninguna Nómina real debe perderse en una migración puramente aditiva');

      final articulos = await db.select(db.articulo).get();
      expect(articulos, isEmpty, reason: 'Articulo es tabla nueva en 7A, sin backfill');
      final movimientos = await db.select(db.movimientoInventario).get();
      expect(movimientos, isEmpty);

      final codigoArticulo =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('articulo'))).getSingleOrNull();
      expect(codigoArticulo, isNotNull, reason: 'runSeed debe sembrar el contador de folio de articulo');
      expect(codigoArticulo!.prefijo, 'ART');

      final codigoUnidad =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('articulo_unidad'))).getSingleOrNull();
      expect(codigoUnidad, isNotNull);
      expect(codigoUnidad!.prefijo, 'UNI');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de Articulo/ArticuloVariante/MovimientoInventario tras la migración: costo >= 0, variante/unidad '
    'mutuamente excluyentes, cantidad siempre positiva',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Camisa'),
          );

      await expectLater(
        db.into(db.articulo).insert(
              ArticuloCompanion.insert(
                folio: 'ART-000001',
                categoriaId: categoria.id,
                nombre: 'Camisa RISEG',
                costoReferencia: const Value(-100),
              ),
            ),
        throwsA(anything),
        reason: 'costo_referencia negativo debe rechazarse',
      );

      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Camisa RISEG',
              manejaVariante: const Value(true),
            ),
          );
      final variante = await db.into(db.articuloVariante).insertReturning(
            ArticuloVarianteCompanion.insert(articuloId: articulo.id, valor: 'M'),
          );

      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(codigo: 'UNI-000001', articuloId: articulo.id, numeroSerie: 'SN-0001'),
          );

      await expectLater(
        db.into(db.movimientoInventario).insert(
              MovimientoInventarioCompanion.insert(
                articuloId: articulo.id,
                cantidad: 1,
                tipoMovimiento: 'entrada',
                fecha: DateTime(2026, 1, 1),
                varianteId: Value(variante.id),
                unidadId: Value(unidad.id),
              ),
            ),
        throwsA(anything),
        reason: 'variante_id y unidad_id nunca pueden venir poblados a la vez',
      );

      await expectLater(
        db.into(db.movimientoInventario).insert(
              MovimientoInventarioCompanion.insert(
                articuloId: articulo.id,
                cantidad: 2,
                tipoMovimiento: 'entrada',
                fecha: DateTime(2026, 1, 1),
                unidadId: Value(unidad.id),
              ),
            ),
        throwsA(anything),
        reason: 'un movimiento de unidad serializada siempre tiene cantidad = 1',
      );

      final movimiento = await db.into(db.movimientoInventario).insertReturning(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              cantidad: 20,
              tipoMovimiento: 'entrada',
              fecha: DateTime(2026, 1, 1),
              varianteId: Value(variante.id),
            ),
          );
      expect(movimiento.cantidad, 20);

      await db.close();
    },
  );

  test(
    '28.json coincide con el esquema final de la Etapa 7B (tablas nuevas Asignacion, DescuentoInventario, '
    'AsignacionAttachment + índice único parcial idx_asignacion_unidad_activa)',
    () async {
      final schema = await verifier.schemaAt(28);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['asignacion', 'descuento_inventario', 'asignacion_attachment']));

      final sqlAsignacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion'")
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains(
          'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
          '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        ),
      );
      expect(sqlAsignacion, contains('CHECK (variante_id IS NULL OR unidad_id IS NULL)'));
      expect(sqlAsignacion, contains('CHECK (unidad_id IS NULL OR cantidad = 1)'));
      expect(
        sqlAsignacion,
        contains(
          "CHECK ((estatus = 'activa' AND fecha_cierre IS NULL) OR "
          "(estatus != 'activa' AND fecha_cierre IS NOT NULL))",
        ),
      );
      expect(
        sqlAsignacion,
        contains("CHECK (atribuible_al_empleado IS NULL OR estatus = 'danada' OR estatus = 'perdida')"),
      );

      final sqlDescuento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'descuento_inventario'")
                  .single['sql']
              as String;
      expect(sqlDescuento, contains('CHECK (importe > 0)'));

      final sqlIndice =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_asignacion_unidad_activa'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndice,
        'CREATE UNIQUE INDEX idx_asignacion_unidad_activa '
        "ON asignacion (unidad_id) WHERE unidad_id IS NOT NULL AND estatus = 'activa'",
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 27 → 28 conserva una Nómina real y crea las tablas de Asignaciones vacías, sin nuevas '
    'entradas de CodigoSecuencia',
    () async {
      final schemaV27 = await verifier.schemaAt(27);
      final raw = schemaV27.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-real', 'NOM-000001', 2026, 1, 'primera', 1735689600, 1736812800, 1737331200,
        'cerrada', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV27.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nominas = await db.select(db.nomina).get();
      expect(nominas, hasLength(1), reason: 'ninguna Nómina real debe perderse en una migración puramente aditiva');

      final asignaciones = await db.select(db.asignacion).get();
      expect(asignaciones, isEmpty, reason: 'Asignacion es tabla nueva en 7B, sin backfill');
      final descuentos = await db.select(db.descuentoInventario).get();
      expect(descuentos, isEmpty);

      final codigosSecuencia = await db.select(db.codigoSecuencia).get();
      expect(
        codigosSecuencia,
        hasLength(21),
        reason: '7B no agrega ninguna entrada nueva de CodigoSecuencia (la migración corre hasta '
            '_currentSchemaVersion, así que sí incluye las de vehiculo/linea_telefonica/compra sembradas en 8A/9A/10)',
      );

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK y protección de unidad serializada tras la migración: empleado/servicio mutuamente excluyentes, '
    'cierre consistente con fecha_cierre, atribución solo en danada/perdida, importe de descuento positivo, '
    'índice único rechaza una segunda asignación activa sobre la misma unidad',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Radios'),
          );
      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Radio Motorola',
              manejaSerie: const Value(true),
            ),
          );
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(codigo: 'UNI-000001', articuloId: articulo.id, numeroSerie: 'SN-0001'),
          );

      final tipoServicio = await db.into(db.tipoServicio).insertReturning(
            TipoServicioCompanion.insert(id: 'tipo-servicio-real', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'),
          );
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final servicio = await db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: tipoServicio.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );

      final baseAsignacion = AsignacionCompanion.insert(
        articuloId: articulo.id,
        cantidad: 1,
        unidadId: const Value('placeholder'),
        empleadoId: Value(empleado.id),
        fechaEntrega: DateTime(2026, 1, 1),
      );

      await expectLater(
        db.into(db.asignacion).insert(
              baseAsignacion.copyWith(unidadId: Value(unidad.id), servicioId: Value(servicio.id)),
            ),
        throwsA(anything),
        reason: 'empleado_id y servicio_id nunca pueden venir poblados a la vez',
      );
      await expectLater(
        db.into(db.asignacion).insert(
              baseAsignacion.copyWith(unidadId: Value(unidad.id), empleadoId: const Value(null)),
            ),
        throwsA(anything),
        reason: 'exactamente uno de empleado_id/servicio_id debe venir poblado',
      );
      await expectLater(
        db.into(db.asignacion).insert(
              baseAsignacion.copyWith(unidadId: Value(unidad.id), estatus: const Value('devuelta')),
            ),
        throwsA(anything),
        reason: 'estatus != activa exige fecha_cierre poblada',
      );
      await expectLater(
        db.into(db.asignacion).insert(
              baseAsignacion.copyWith(unidadId: Value(unidad.id), atribuibleAlEmpleado: const Value(true)),
            ),
        throwsA(anything),
        reason: 'atribuible_al_empleado solo tiene sentido en danada/perdida',
      );

      final asignacion = await db.into(db.asignacion).insertReturning(
            baseAsignacion.copyWith(unidadId: Value(unidad.id)),
          );
      expect(asignacion.estatus, 'activa');

      await expectLater(
        db.into(db.asignacion).insert(
              AsignacionCompanion.insert(
                articuloId: articulo.id,
                cantidad: 1,
                unidadId: Value(unidad.id),
                empleadoId: Value(empleado.id),
                fechaEntrega: DateTime(2026, 1, 2),
              ),
            ),
        throwsA(anything),
        reason: 'idx_asignacion_unidad_activa rechaza una segunda asignación activa sobre la misma unidad',
      );

      await expectLater(
        db.into(db.descuentoInventario).insert(
              DescuentoInventarioCompanion.insert(
                asignacionId: asignacion.id,
                empleadoId: empleado.id,
                motivo: 'dano',
                importe: 0,
              ),
            ),
        throwsA(anything),
        reason: 'importe de un DescuentoInventario siempre debe ser positivo',
      );

      final descuento = await db.into(db.descuentoInventario).insertReturning(
            DescuentoInventarioCompanion.insert(
              asignacionId: asignacion.id,
              empleadoId: empleado.id,
              motivo: 'dano',
              importe: 150000,
            ),
          );
      expect(descuento.estatus, 'pendiente');

      await db.close();
    },
  );

  test(
    '29.json coincide con el esquema final de la Etapa 7C (AsignacionAttachment con llave primaria compuesta)',
    () async {
      final schema = await verifier.schemaAt(29);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();
      expect(tablas, contains('asignacion_attachment'));

      final sqlAsignacionAttachment =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_attachment'")
                  .single['sql']
              as String;
      expect(sqlAsignacionAttachment, contains('asignacion_id'));
      expect(
        sqlAsignacionAttachment,
        contains('PRIMARY KEY'),
        reason: 'la llave primaria debe seguir declarada explícitamente (ahora compuesta)',
      );

      schema.rawDatabase.dispose();
    },
  );

  test('migración 28 → 29 conserva una Asignacion real y recrea AsignacionAttachment vacía', () async {
    final schemaV28 = await verifier.schemaAt(28);
    final raw = schemaV28.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Radios', 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO articulo (
        id, folio, categoria_id, nombre, maneja_variante, maneja_serie,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'articulo-real', 'ART-000001', 'categoria-real', 'Radio Motorola', 0, 0,
        1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute('''
      INSERT INTO asignacion (
        id, articulo_id, cantidad, empleado_id, fecha_entrega, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'asignacion-real', 'articulo-real', 2, 'empleado-real', 1735689600, 'activa',
        1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaV28.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final asignaciones = await db.select(db.asignacion).get();
    expect(asignaciones, hasLength(1), reason: 'ninguna Asignacion real debe perderse en una migración puramente estructural');

    final asignacionAttachments = await db.select(db.asignacionAttachment).get();
    expect(asignacionAttachments, isEmpty, reason: 'AsignacionAttachment nunca tuvo filas — se recrea vacía');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty);

    final integridad =
        await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
    expect(integridad, ['ok']);

    await db.close();
  });

  test(
    'llave primaria compuesta de AsignacionAttachment: un mismo Attachment puede unirse a varias Asignaciones, '
    'pero no repetir el mismo par',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Radios'),
          );
      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(folio: 'ART-000001', categoriaId: categoria.id, nombre: 'Radio Motorola'),
          );
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      final asignacion1 = await db.into(db.asignacion).insertReturning(
            AsignacionCompanion.insert(articuloId: articulo.id, cantidad: 1, empleadoId: Value(empleado.id), fechaEntrega: DateTime(2026, 1, 1)),
          );
      final asignacion2 = await db.into(db.asignacion).insertReturning(
            AsignacionCompanion.insert(articuloId: articulo.id, cantidad: 1, empleadoId: Value(empleado.id), fechaEntrega: DateTime(2026, 1, 1)),
          );

      final attachment = await db.into(db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: 'attachment-resguardo',
              categoria: const Value('resguardo'),
              originalFileName: 'resguardo.pdf',
              storedFileName: 'uuid.pdf',
              path: 'C:/tmp/uuid.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 1024,
            ),
          );

      await db.into(db.asignacionAttachment).insert(
            AsignacionAttachmentCompanion.insert(attachmentId: attachment.id, asignacionId: asignacion1.id),
          );
      await db.into(db.asignacionAttachment).insert(
            AsignacionAttachmentCompanion.insert(attachmentId: attachment.id, asignacionId: asignacion2.id),
          );

      final filas = await db.select(db.asignacionAttachment).get();
      expect(filas, hasLength(2), reason: 'un mismo Attachment sí debe poder unirse a más de una Asignación');

      await expectLater(
        db.into(db.asignacionAttachment).insert(
              AsignacionAttachmentCompanion.insert(attachmentId: attachment.id, asignacionId: asignacion1.id),
            ),
        throwsA(anything),
        reason: 'el mismo par (attachment_id, asignacion_id) no puede repetirse',
      );

      await db.close();
    },
  );

  test(
    '30.json coincide con el esquema final de la Etapa 8A (tablas nuevas Vehiculo, VehiculoAttachment + '
    'índices únicos parciales idx_vehiculo_placas_unica/idx_vehiculo_vin_unico)',
    () async {
      final schema = await verifier.schemaAt(30);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['vehiculo', 'vehiculo_attachment']));

      final sqlVehiculo =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo'")
                  .single['sql']
              as String;
      expect(sqlVehiculo, contains('"codigo" TEXT NOT NULL UNIQUE'));
      expect(sqlVehiculo, contains('CHECK (costo_adquisicion IS NULL OR costo_adquisicion >= 0)'));
      expect(
        sqlVehiculo,
        contains(
          "CHECK ((estatus = 'baja' AND fecha_baja IS NOT NULL) OR "
          "(estatus != 'baja' AND fecha_baja IS NULL))",
        ),
      );

      final sqlIndicePlacas =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_vehiculo_placas_unica'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndicePlacas,
        'CREATE UNIQUE INDEX idx_vehiculo_placas_unica '
        'ON vehiculo (placas) WHERE placas IS NOT NULL',
      );

      final sqlIndiceVin =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_vehiculo_vin_unico'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndiceVin,
        'CREATE UNIQUE INDEX idx_vehiculo_vin_unico '
        'ON vehiculo (vin) WHERE vin IS NOT NULL',
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 29 → 30 conserva una Asignacion real y crea las tablas de Vehículos vacías, sembrando '
    'CodigoSecuencia(vehiculo)',
    () async {
      final schemaV29 = await verifier.schemaAt(29);
      final raw = schemaV29.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Radios', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo (
        id, folio, categoria_id, nombre, maneja_variante, maneja_serie, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'articulo-real', 'ART-000001', 'categoria-real', 'Radio Motorola', 0, 0, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss, estado_civil,
        fecha_ingreso, anios_experiencia_seguridad, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01', 'PEXJ900101AB1',
        '12345678901', 'soltero', 1735689600, 3, 'activo', 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO asignacion (
        id, articulo_id, cantidad, empleado_id, fecha_entrega, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'asignacion-real', 'articulo-real', 1, 'empleado-real', 1735689600, 'activa', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV29.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final asignaciones = await db.select(db.asignacion).get();
      expect(asignaciones, hasLength(1), reason: 'ninguna Asignacion real debe perderse en una migración puramente aditiva');

      final vehiculos = await db.select(db.vehiculo).get();
      expect(vehiculos, isEmpty, reason: 'Vehiculo es tabla nueva en 8A, sin backfill');
      final vehiculoAttachments = await db.select(db.vehiculoAttachment).get();
      expect(vehiculoAttachments, isEmpty);

      final codigoVehiculo =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('vehiculo'))).getSingleOrNull();
      expect(codigoVehiculo, isNotNull, reason: 'runSeed debe sembrar el contador de código de vehiculo');
      expect(codigoVehiculo!.prefijo, 'VEH');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de Vehiculo tras la migración: costo_adquisicion >= 0, fecha_baja consistente con estatus, '
    'placas/VIN únicos solo cuando se capturan',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final baseVehiculo = VehiculoCompanion.insert(
        codigo: 'VEH-000001',
        marca: 'BMW',
        modelo: '320i',
        tipoVehiculo: 'sedan',
      );

      await expectLater(
        db.into(db.vehiculo).insert(baseVehiculo.copyWith(costoAdquisicion: const Value(-100))),
        throwsA(anything),
        reason: 'costo_adquisicion negativo debe rechazarse',
      );
      await expectLater(
        db.into(db.vehiculo).insert(baseVehiculo.copyWith(estatus: const Value('baja'))),
        throwsA(anything),
        reason: 'estatus = baja exige fecha_baja poblada',
      );
      await expectLater(
        db.into(db.vehiculo).insert(baseVehiculo.copyWith(fechaBaja: Value(DateTime(2026, 1, 1)))),
        throwsA(anything),
        reason: 'fecha_baja poblada exige estatus = baja',
      );

      final vehiculo1 = await db.into(db.vehiculo).insertReturning(
            baseVehiculo.copyWith(codigo: const Value('VEH-000001'), placas: const Value('ABC-123'), vin: const Value('VIN-0001')),
          );
      expect(vehiculo1.estatus, 'disponible');

      // Dos vehículos sin placas/VIN capturados deben coexistir sin problema.
      await db.into(db.vehiculo).insertReturning(
            baseVehiculo.copyWith(codigo: const Value('VEH-000002')),
          );
      await db.into(db.vehiculo).insertReturning(
            baseVehiculo.copyWith(codigo: const Value('VEH-000003')),
          );

      await expectLater(
        db.into(db.vehiculo).insert(baseVehiculo.copyWith(codigo: const Value('VEH-000004'), placas: const Value('ABC-123'))),
        throwsA(anything),
        reason: 'idx_vehiculo_placas_unica rechaza placas duplicadas',
      );
      await expectLater(
        db.into(db.vehiculo).insert(baseVehiculo.copyWith(codigo: const Value('VEH-000005'), vin: const Value('VIN-0001'))),
        throwsA(anything),
        reason: 'idx_vehiculo_vin_unico rechaza VIN duplicado',
      );

      await db.close();
    },
  );

  test(
    '31.json coincide con el esquema final de la Etapa 8B (tablas nuevas AsignacionVehiculo, VehiculoKilometraje '
    '+ índice único parcial idx_asignacion_vehiculo_vigente)',
    () async {
      final schema = await verifier.schemaAt(31);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['asignacion_vehiculo', 'vehiculo_kilometraje']));

      final sqlAsignacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_vehiculo'")
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains(
          'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
          '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        ),
      );
      expect(sqlAsignacion, contains('CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)'));

      final sqlKilometraje =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo_kilometraje'")
                  .single['sql']
              as String;
      expect(sqlKilometraje, contains('CHECK (kilometraje >= 0)'));

      final sqlIndice =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_asignacion_vehiculo_vigente'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndice,
        'CREATE UNIQUE INDEX idx_asignacion_vehiculo_vigente '
        'ON asignacion_vehiculo (vehiculo_id) WHERE fecha_termino IS NULL',
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 30 → 31 conserva un Vehículo real y crea las tablas de Asignaciones/Kilometraje vacías',
    () async {
      final schemaV30 = await verifier.schemaAt(30);
      final raw = schemaV30.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO vehiculo (
        id, codigo, marca, modelo, tipo_vehiculo, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vehiculo-real', 'VEH-000001', 'BMW', '320i', 'sedan', 'disponible', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV30.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculos = await db.select(db.vehiculo).get();
      expect(vehiculos, hasLength(1), reason: 'ningún Vehículo real debe perderse en una migración puramente aditiva');

      final asignaciones = await db.select(db.asignacionVehiculo).get();
      expect(asignaciones, isEmpty, reason: 'AsignacionVehiculo es tabla nueva en 8B, sin backfill');
      final lecturas = await db.select(db.vehiculoKilometraje).get();
      expect(lecturas, isEmpty);

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de AsignacionVehiculo/VehiculoKilometraje tras la migración: empleado/servicio mutuamente '
    'excluyentes, fecha_termino >= fecha_inicio, kilometraje >= 0, índice único rechaza una segunda '
    'asignación vigente sobre el mismo Vehículo',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(codigo: 'VEH-000001', marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'),
          );
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      final tipoServicio = await db.into(db.tipoServicio).insertReturning(
            TipoServicioCompanion.insert(id: 'tipo-servicio-real', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'),
          );
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
          );
      final servicio = await db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium Toluca',
              tipoServicioId: tipoServicio.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );

      final baseAsignacion = AsignacionVehiculoCompanion.insert(
        vehiculoId: vehiculo.id,
        fechaInicio: DateTime(2026, 1, 1),
        empleadoId: const Value('placeholder'),
      );

      await expectLater(
        db.into(db.asignacionVehiculo).insert(
              baseAsignacion.copyWith(empleadoId: Value(empleado.id), servicioId: Value(servicio.id)),
            ),
        throwsA(anything),
        reason: 'empleado_id y servicio_id nunca pueden venir poblados a la vez',
      );
      await expectLater(
        db.into(db.asignacionVehiculo).insert(baseAsignacion.copyWith(empleadoId: const Value(null))),
        throwsA(anything),
        reason: 'exactamente uno de empleado_id/servicio_id debe venir poblado',
      );
      await expectLater(
        db.into(db.asignacionVehiculo).insert(
              baseAsignacion.copyWith(
                empleadoId: Value(empleado.id),
                fechaTermino: Value(DateTime(2025, 12, 1)),
              ),
            ),
        throwsA(anything),
        reason: 'fecha_termino no puede ser anterior a fecha_inicio',
      );

      final asignacion = await db.into(db.asignacionVehiculo).insertReturning(
            baseAsignacion.copyWith(empleadoId: Value(empleado.id)),
          );
      expect(asignacion.fechaTermino, isNull);

      await expectLater(
        db.into(db.asignacionVehiculo).insert(
              AsignacionVehiculoCompanion.insert(
                vehiculoId: vehiculo.id,
                empleadoId: const Value(null),
                servicioId: Value(servicio.id),
                fechaInicio: DateTime(2026, 1, 2),
              ),
            ),
        throwsA(anything),
        reason: 'idx_asignacion_vehiculo_vigente rechaza una segunda asignación vigente para el mismo Vehículo',
      );

      await expectLater(
        db.into(db.vehiculoKilometraje).insert(
              VehiculoKilometrajeCompanion.insert(
                vehiculoId: vehiculo.id,
                fecha: DateTime(2026, 1, 1),
                kilometraje: -1,
                origen: 'lecturaManual',
              ),
            ),
        throwsA(anything),
        reason: 'kilometraje nunca puede ser negativo',
      );

      final lectura = await db.into(db.vehiculoKilometraje).insertReturning(
            VehiculoKilometrajeCompanion.insert(
              vehiculoId: vehiculo.id,
              fecha: DateTime(2026, 1, 1),
              kilometraje: 15000,
              origen: 'lecturaManual',
            ),
          );
      expect(lectura.kilometraje, 15000);

      await db.close();
    },
  );

  test(
    '32.json coincide con el esquema final de la Etapa 8C (tablas nuevas VehiculoDocumento, '
    'VehiculoDocumentoAttachment, sin índices propios)',
    () async {
      final schema = await verifier.schemaAt(32);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['vehiculo_documento', 'vehiculo_documento_attachment']));

      final sqlDocumento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo_documento'")
                  .single['sql']
              as String;
      expect(
        sqlDocumento,
        contains(
          'CHECK (fecha_vencimiento IS NULL OR fecha_emision IS NULL OR fecha_vencimiento >= fecha_emision)',
        ),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 31 → 32 conserva un Vehículo real y crea la tabla VehiculoDocumento vacía',
    () async {
      final schemaV31 = await verifier.schemaAt(31);
      final raw = schemaV31.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO vehiculo (
        id, codigo, marca, modelo, tipo_vehiculo, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vehiculo-real', 'VEH-000001', 'BMW', '320i', 'sedan', 'disponible', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV31.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculos = await db.select(db.vehiculo).get();
      expect(vehiculos, hasLength(1), reason: 'ningún Vehículo real debe perderse en una migración puramente aditiva');

      final documentos = await db.select(db.vehiculoDocumento).get();
      expect(documentos, isEmpty, reason: 'VehiculoDocumento es tabla nueva en 8C, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de VehiculoDocumento tras la migración: fecha_vencimiento >= fecha_emision cuando ambas existen',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(codigo: 'VEH-000001', marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'),
          );

      await expectLater(
        db.into(db.vehiculoDocumento).insert(
              VehiculoDocumentoCompanion.insert(
                vehiculoId: vehiculo.id,
                tipo: 'seguro',
                fechaEmision: Value(DateTime(2026, 6, 1)),
                fechaVencimiento: Value(DateTime(2026, 1, 1)),
              ),
            ),
        throwsA(anything),
        reason: 'fecha_vencimiento no puede ser anterior a fecha_emision',
      );

      final documento = await db.into(db.vehiculoDocumento).insertReturning(
            VehiculoDocumentoCompanion.insert(
              vehiculoId: vehiculo.id,
              tipo: 'facturaCartaFactura',
            ),
          );
      expect(documento.fechaVencimiento, isNull, reason: 'documentos sin vencimiento (ej. factura) son válidos');

      await db.close();
    },
  );

  test(
    '33.json coincide con el esquema final de la Etapa 8D (tablas nuevas VehiculoMantenimiento, '
    'VehiculoMantenimientoAttachment, sin índices propios) — cierra funcionalmente el dominio Vehículos',
    () async {
      final schema = await verifier.schemaAt(33);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['vehiculo_mantenimiento', 'vehiculo_mantenimiento_attachment']));

      final sqlMantenimiento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo_mantenimiento'")
                  .single['sql']
              as String;
      expect(sqlMantenimiento, contains('CHECK (kilometraje IS NULL OR kilometraje >= 0)'));
      expect(sqlMantenimiento, contains('CHECK (costo IS NULL OR costo >= 0)'));
      expect(sqlMantenimiento, contains('CHECK (proximo_mantenimiento_kilometraje IS NULL OR proximo_mantenimiento_kilometraje >= 0)'));
      expect(sqlMantenimiento, contains('CHECK (proximo_mantenimiento_fecha IS NULL OR proximo_mantenimiento_fecha >= fecha)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 32 → 33 conserva un Vehículo real y crea la tabla VehiculoMantenimiento vacía',
    () async {
      final schemaV32 = await verifier.schemaAt(32);
      final raw = schemaV32.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO vehiculo (
        id, codigo, marca, modelo, tipo_vehiculo, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vehiculo-real', 'VEH-000001', 'BMW', '320i', 'sedan', 'disponible', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV32.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculos = await db.select(db.vehiculo).get();
      expect(vehiculos, hasLength(1), reason: 'ningún Vehículo real debe perderse en una migración puramente aditiva');

      final mantenimientos = await db.select(db.vehiculoMantenimiento).get();
      expect(mantenimientos, isEmpty, reason: 'VehiculoMantenimiento es tabla nueva en 8D, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de VehiculoMantenimiento tras la migración: kilometraje/costo/proximo_kilometraje >= 0, '
    'proximo_fecha >= fecha',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(codigo: 'VEH-000001', marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'),
          );
      final base = VehiculoMantenimientoCompanion.insert(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'preventivo',
        descripcion: 'Servicio',
      );

      await expectLater(
        db.into(db.vehiculoMantenimiento).insert(base.copyWith(kilometraje: const Value(-1))),
        throwsA(anything),
        reason: 'kilometraje nunca puede ser negativo',
      );
      await expectLater(
        db.into(db.vehiculoMantenimiento).insert(base.copyWith(costo: const Value(-1))),
        throwsA(anything),
        reason: 'costo nunca puede ser negativo',
      );
      await expectLater(
        db.into(db.vehiculoMantenimiento).insert(base.copyWith(proximoMantenimientoKilometraje: const Value(-1))),
        throwsA(anything),
        reason: 'proximo_mantenimiento_kilometraje nunca puede ser negativo',
      );
      await expectLater(
        db.into(db.vehiculoMantenimiento).insert(
              base.copyWith(proximoMantenimientoFecha: Value(DateTime(2026, 1, 5))),
            ),
        throwsA(anything),
        reason: 'proximo_mantenimiento_fecha no puede ser anterior a fecha',
      );

      final registro = await db.into(db.vehiculoMantenimiento).insertReturning(
            base.copyWith(proximoMantenimientoFecha: Value(DateTime(2026, 4, 10))),
          );
      expect(registro.proximoMantenimientoFecha, DateTime(2026, 4, 10));

      await db.close();
    },
  );

  test(
    '34.json coincide con el esquema final de la Etapa 9A (tablas nuevas LineaTelefonica, '
    'LineaTelefonicaPlan + índice único parcial idx_linea_telefonica_numero_unico) — funda el dominio Telefonía',
    () async {
      final schema = await verifier.schemaAt(34);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['linea_telefonica', 'linea_telefonica_plan']));

      final sqlLinea =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica'")
                  .single['sql']
              as String;
      expect(sqlLinea, contains('"codigo" TEXT NOT NULL UNIQUE'));
      expect(
        sqlLinea,
        contains(
          "CHECK ((estatus = 'baja' AND fecha_baja IS NOT NULL) OR "
          "(estatus != 'baja' AND fecha_baja IS NULL))",
        ),
      );

      final sqlIndiceNumero =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_linea_telefonica_numero_unico'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndiceNumero,
        'CREATE UNIQUE INDEX idx_linea_telefonica_numero_unico '
        'ON linea_telefonica (numero) WHERE numero IS NOT NULL',
      );

      final sqlPlan =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica_plan'")
                  .single['sql']
              as String;
      expect(sqlPlan, contains('CHECK (costo_mensual >= 0)'));
      expect(sqlPlan, contains('CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)'));
      expect(
        sqlPlan,
        contains('CHECK (fecha_fin_permanencia IS NULL OR fecha_fin_permanencia >= fecha_inicio_vigencia)'),
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 33 → 34 conserva un Vehículo real y crea las tablas de Telefonía vacías, sembrando '
    'CodigoSecuencia(linea_telefonica)',
    () async {
      final schemaV33 = await verifier.schemaAt(33);
      final raw = schemaV33.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO vehiculo (
        id, codigo, marca, modelo, tipo_vehiculo, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vehiculo-real', 'VEH-000001', 'BMW', '320i', 'sedan', 'disponible', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV33.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculos = await db.select(db.vehiculo).get();
      expect(vehiculos, hasLength(1), reason: 'ningún Vehículo real debe perderse en una migración puramente aditiva');

      final lineas = await db.select(db.lineaTelefonica).get();
      expect(lineas, isEmpty, reason: 'LineaTelefonica es tabla nueva en 9A, sin backfill');

      final codigoLinea = await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('linea_telefonica')))
          .getSingleOrNull();
      expect(codigoLinea, isNotNull, reason: 'runSeed debe sembrar el contador de código de linea_telefonica');
      expect(codigoLinea!.prefijo, 'TEL');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de LineaTelefonica tras la migración: fecha_baja consistente con estatus, '
    'número único solo cuando se captura',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final baseLinea = LineaTelefonicaCompanion.insert(codigo: 'TEL-000001', operador: 'telcel', modalidadSim: 'fisica');

      await expectLater(
        db.into(db.lineaTelefonica).insert(baseLinea.copyWith(estatus: const Value('baja'))),
        throwsA(anything),
        reason: 'estatus = baja exige fecha_baja poblada',
      );
      await expectLater(
        db.into(db.lineaTelefonica).insert(baseLinea.copyWith(fechaBaja: Value(DateTime(2026, 1, 1)))),
        throwsA(anything),
        reason: 'fecha_baja poblada exige estatus = baja',
      );

      await db.into(db.lineaTelefonica).insertReturning(
            baseLinea.copyWith(numero: const Value('7221234567')),
          );

      // Dos líneas sin número capturado deben coexistir sin problema.
      await db.into(db.lineaTelefonica).insertReturning(baseLinea.copyWith(codigo: const Value('TEL-000002')));
      await db.into(db.lineaTelefonica).insertReturning(baseLinea.copyWith(codigo: const Value('TEL-000003')));

      await expectLater(
        db.into(db.lineaTelefonica).insert(
              baseLinea.copyWith(codigo: const Value('TEL-000004'), numero: const Value('7221234567')),
            ),
        throwsA(anything),
        reason: 'idx_linea_telefonica_numero_unico rechaza número duplicado',
      );

      await db.close();
    },
  );

  test(
    '35.json coincide con el esquema final de la Etapa 9B (tablas nuevas AsignacionLineaTelefonica, '
    'LineaTelefonicaEquipo + índice único parcial idx_asignacion_linea_telefonica_vigente) — '
    'asignaciones y equipo asociado de Telefonía',
    () async {
      final schema = await verifier.schemaAt(35);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['asignacion_linea_telefonica', 'linea_telefonica_equipo']));

      final sqlAsignacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_linea_telefonica'")
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains(
          'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
          '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        ),
      );
      expect(sqlAsignacion, contains('CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)'));

      final sqlIndiceVigente =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_asignacion_linea_telefonica_vigente'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlIndiceVigente,
        'CREATE UNIQUE INDEX idx_asignacion_linea_telefonica_vigente '
        'ON asignacion_linea_telefonica (linea_telefonica_id) WHERE fecha_termino IS NULL',
      );

      final sqlEquipo =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica_equipo'")
                  .single['sql']
              as String;
      expect(sqlEquipo, contains('CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 34 → 35 conserva una LineaTelefonica real y crea las tablas de asignación/equipo vacías',
    () async {
      final schemaV34 = await verifier.schemaAt(34);
      final raw = schemaV34.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO linea_telefonica (
        id, codigo, numero, operador, modalidad_sim, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'linea-real', 'TEL-000001', '7221234567', 'telcel', 'fisica', 'activa', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV34.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final lineas = await db.select(db.lineaTelefonica).get();
      expect(lineas, hasLength(1), reason: 'ninguna LineaTelefonica real debe perderse en una migración puramente aditiva');
      expect(lineas.single.numero, '7221234567');

      final asignaciones = await db.select(db.asignacionLineaTelefonica).get();
      expect(asignaciones, isEmpty, reason: 'AsignacionLineaTelefonica es tabla nueva en 9B, sin backfill');
      final equipos = await db.select(db.lineaTelefonicaEquipo).get();
      expect(equipos, isEmpty, reason: 'LineaTelefonicaEquipo es tabla nueva en 9B, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK/índice único de AsignacionLineaTelefonica/LineaTelefonicaEquipo tras la migración: exactamente uno de '
    'empleado/servicio, fecha_termino/fecha_fin coherentes, una sola asignación vigente por línea',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final linea = await db.into(db.lineaTelefonica).insertReturning(
            LineaTelefonicaCompanion.insert(codigo: 'TEL-000001', operador: 'telcel', modalidadSim: 'fisica'),
          );
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );

      final baseAsignacion = AsignacionLineaTelefonicaCompanion.insert(
        lineaTelefonicaId: linea.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      await expectLater(
        db.into(db.asignacionLineaTelefonica).insert(baseAsignacion),
        throwsA(anything),
        reason: 'ni empleado ni servicio poblados debe rechazarse',
      );
      await expectLater(
        db.into(db.asignacionLineaTelefonica).insert(
              baseAsignacion.copyWith(empleadoId: Value(empleado.id), servicioId: Value('servicio-inexistente')),
            ),
        throwsA(anything),
        reason: 'empleado y servicio poblados a la vez debe rechazarse',
      );
      await expectLater(
        db.into(db.asignacionLineaTelefonica).insert(
              baseAsignacion.copyWith(empleadoId: Value(empleado.id), fechaTermino: Value(DateTime(2026, 1, 1))),
            ),
        throwsA(anything),
        reason: 'fecha_termino anterior a fecha_inicio debe rechazarse',
      );

      final asignacion = await db.into(db.asignacionLineaTelefonica).insertReturning(
            baseAsignacion.copyWith(empleadoId: Value(empleado.id)),
          );
      expect(asignacion.empleadoId, empleado.id);

      final empleado2 = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 2,
              nombres: 'Ana',
              apellidoPaterno: 'López',
              sexo: 'femenino',
              fechaNacimiento: DateTime(1992, 1, 1),
              curp: 'LOAA920101MDFXXX02',
              rfc: 'LOAA920101AB2',
              nss: '12345678902',
              estadoCivil: 'soltera',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 2,
            ),
          );
      await expectLater(
        db.into(db.asignacionLineaTelefonica).insert(
              AsignacionLineaTelefonicaCompanion.insert(
                lineaTelefonicaId: linea.id,
                fechaInicio: DateTime(2026, 2, 1),
                empleadoId: const Value('otro-empleado-no-usado'),
              ).copyWith(empleadoId: Value(empleado2.id)),
            ),
        throwsA(anything),
        reason: 'idx_asignacion_linea_telefonica_vigente rechaza una segunda asignación vigente para la misma línea',
      );

      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'),
          );
      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(folio: 'ART-000001', categoriaId: categoria.id, nombre: 'Smartphone', manejaSerie: const Value(true)),
          );
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(codigo: 'UNI-000001', articuloId: articulo.id, numeroSerie: 'SN-0001'),
          );

      final baseEquipo = LineaTelefonicaEquipoCompanion.insert(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
      );
      await expectLater(
        db.into(db.lineaTelefonicaEquipo).insert(baseEquipo.copyWith(fechaFin: Value(DateTime(2026, 1, 1)))),
        throwsA(anything),
        reason: 'fecha_fin anterior a fecha_inicio debe rechazarse',
      );

      final equipo = await db.into(db.lineaTelefonicaEquipo).insertReturning(baseEquipo);
      expect(equipo.unidadId, unidad.id);

      await db.close();
    },
  );

  test(
    '36.json coincide con el esquema final de la Etapa 9C (retira LineaTelefonicaPlan, tablas nuevas '
    'RecargaLineaTelefonica/RecargaLineaTelefonicaAttachment) — Telefonía confirmada como operación prepago',
    () async {
      final schema = await verifier.schemaAt(36);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['recarga_linea_telefonica', 'recarga_linea_telefonica_attachment']));
      expect(tablas, isNot(contains('linea_telefonica_plan')), reason: 'retirada por completo en 9C — operación prepago, sin planes');

      final sqlRecarga =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'recarga_linea_telefonica'")
                  .single['sql']
              as String;
      expect(sqlRecarga, contains('CHECK (importe > 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 35 → 36 retira LineaTelefonicaPlan (incluso con filas reales) y crea las tablas de Recarga vacías, '
    'conservando la LineaTelefonica real',
    () async {
      final schemaV35 = await verifier.schemaAt(35);
      final raw = schemaV35.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO linea_telefonica (
        id, codigo, numero, operador, modalidad_sim, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'linea-real', 'TEL-000001', '7221234567', 'telcel', 'fisica', 'activa', 1700000000, 1700000000, 'activo'
      );
    ''');
      // Fila real en LineaTelefonicaPlan (Etapa 9A, antes de confirmarse
      // que la operación es prepago) — debe perderse limpiamente al
      // eliminar la tabla, sin romper la migración.
      raw.execute('''
      INSERT INTO linea_telefonica_plan (
        id, linea_telefonica_id, nombre, costo_mensual, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'plan-real', 'linea-real', 'Plan 399', 39900, 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV35.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final lineas = await db.select(db.lineaTelefonica).get();
      expect(lineas, hasLength(1), reason: 'ninguna LineaTelefonica real debe perderse al retirar LineaTelefonicaPlan');
      expect(lineas.single.numero, '7221234567');

      final tablasRestantes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica_plan'")
          .get();
      expect(tablasRestantes, isEmpty, reason: 'linea_telefonica_plan debe desaparecer por completo, con o sin filas reales');

      final recargas = await db.select(db.recargaLineaTelefonica).get();
      expect(recargas, isEmpty, reason: 'RecargaLineaTelefonica es tabla nueva en 9C, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de RecargaLineaTelefonica tras la migración: importe siempre > 0',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final linea = await db.into(db.lineaTelefonica).insertReturning(
            LineaTelefonicaCompanion.insert(codigo: 'TEL-000001', operador: 'telcel', modalidadSim: 'fisica'),
          );
      final baseRecarga = RecargaLineaTelefonicaCompanion.insert(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 8, 5),
        importe: 20000,
      );

      await expectLater(
        db.into(db.recargaLineaTelefonica).insert(baseRecarga.copyWith(importe: const Value(0))),
        throwsA(anything),
        reason: 'importe = 0 debe rechazarse',
      );
      await expectLater(
        db.into(db.recargaLineaTelefonica).insert(baseRecarga.copyWith(importe: const Value(-100))),
        throwsA(anything),
        reason: 'importe negativo debe rechazarse',
      );

      final recarga = await db.into(db.recargaLineaTelefonica).insertReturning(baseRecarga);
      expect(recarga.importe, 20000);

      await db.close();
    },
  );

  test(
    '37.json coincide con el esquema final de la Etapa 10 (tablas nuevas Compra, CompraPartida, '
    'CompraPartidaMovimiento, CompraAttachment, CompraEvento) — funda el dominio Compras',
    () async {
      final schema = await verifier.schemaAt(37);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(
        tablas,
        containsAll(['compra', 'compra_partida', 'compra_partida_movimiento', 'compra_attachment', 'compra_evento']),
      );

      final sqlCompra =
          schema.rawDatabase.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra'").single['sql']
              as String;
      expect(sqlCompra, contains('"egreso_id" TEXT NULL UNIQUE REFERENCES egreso (id) ON DELETE RESTRICT'));

      final sqlPartida =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra_partida'")
                  .single['sql']
              as String;
      expect(sqlPartida, contains("CHECK (destino <> 'gastoDirecto' OR articulo_id IS NULL)"));
      expect(sqlPartida, contains("CHECK (destino <> 'inventario' OR articulo_id IS NOT NULL)"));
      expect(sqlPartida, contains('CHECK (cantidad > 0)'));
      expect(sqlPartida, contains('CHECK (costo_unitario >= 0)'));

      final sqlPuente =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra_partida_movimiento'")
                  .single['sql']
              as String;
      expect(sqlPuente, contains('PRIMARY KEY ("movimiento_inventario_id")'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 36 → 37 conserva un Vehículo real y crea las tablas de Compras vacías, sin tocar '
    'movimiento_inventario/articulo_unidad/egreso',
    () async {
      final schemaV36 = await verifier.schemaAt(36);
      final raw = schemaV36.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO vehiculo (
        id, codigo, marca, modelo, tipo_vehiculo, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vehiculo-real', 'VEH-000001', 'BMW', '320i', 'sedan', 'disponible', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV36.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculos = await db.select(db.vehiculo).get();
      expect(vehiculos, hasLength(1), reason: 'ningún Vehículo real debe perderse en una migración puramente aditiva');

      final compras = await db.select(db.compra).get();
      expect(compras, isEmpty, reason: 'Compra es tabla nueva en la Etapa 10, sin backfill');
      final partidas = await db.select(db.compraPartida).get();
      expect(partidas, isEmpty);

      final codigoCompra =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('compra'))).getSingleOrNull();
      expect(codigoCompra, isNotNull, reason: 'runSeed debe sembrar el contador de código de compra');
      expect(codigoCompra!.prefijo, 'COM');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'CHECK de CompraPartida tras la migración: destino/artículo coherentes, cantidad y costo válidos',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Uniformes'),
          );
      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(folio: 'ART-000001', categoriaId: categoria.id, nombre: 'Camisola CH'),
          );
      final egreso = await db.into(db.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: 'EGR-000001',
              monto: 180000,
              fecha: DateTime(2026, 8, 10),
              formaPago: 'tarjeta',
              concepto: 'Compra COM-000001',
            ),
          );
      final compra = await db.into(db.compra).insertReturning(
            CompraCompanion.insert(
              folioCompra: 'COM-000001',
              fecha: DateTime(2026, 8, 10),
              formaPago: 'tarjeta',
              egresoId: Value(egreso.id),
            ),
          );

      final basePartida = CompraPartidaCompanion.insert(
        compraId: compra.id,
        destino: 'inventario',
        cantidad: 10,
        costoUnitario: 18000,
        articuloId: Value(articulo.id),
      );

      await expectLater(
        db.into(db.compraPartida).insert(basePartida.copyWith(destino: const Value('gastoDirecto'))),
        throwsA(anything),
        reason: 'destino gastoDirecto con articulo_id poblado debe rechazarse',
      );
      await expectLater(
        db.into(db.compraPartida).insert(basePartida.copyWith(articuloId: const Value.absent(), destino: const Value('inventario'))),
        throwsA(anything),
        reason: 'destino inventario sin articulo_id debe rechazarse',
      );
      await expectLater(
        db.into(db.compraPartida).insert(basePartida.copyWith(cantidad: const Value(0))),
        throwsA(anything),
        reason: 'cantidad = 0 debe rechazarse',
      );
      await expectLater(
        db.into(db.compraPartida).insert(basePartida.copyWith(costoUnitario: const Value(-1))),
        throwsA(anything),
        reason: 'costo_unitario negativo debe rechazarse',
      );

      final partida = await db.into(db.compraPartida).insertReturning(basePartida);
      expect(partida.cantidad, 10);

      await expectLater(
        db.into(db.compra).insert(
              CompraCompanion.insert(
                folioCompra: 'COM-000002',
                fecha: DateTime(2026, 8, 11),
                formaPago: 'efectivo',
                egresoId: Value(egreso.id),
              ),
            ),
        throwsA(anything),
        reason: 'egreso_id debe ser único — un Egreso no puede pertenecer a dos Compras',
      );

      await db.close();
    },
  );

  test(
    '38.json coincide con el esquema final de la Etapa 11A (tablas nuevas Usuario, UsuarioEvento) — '
    'funda el dominio Usuarios',
    () async {
      final schema = await verifier.schemaAt(38);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['usuario', 'usuario_evento']));

      final sqlUsuario =
          schema.rawDatabase.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'usuario'").single['sql']
              as String;
      expect(sqlUsuario, contains('"nombre_usuario" TEXT NOT NULL UNIQUE'));
      expect(sqlUsuario, contains('"password_hash" TEXT NOT NULL'));
      expect(sqlUsuario, contains('"puesto_id" TEXT NULL REFERENCES puesto (id) ON DELETE RESTRICT'));
      expect(sqlUsuario, contains('"es_maestro" INTEGER NOT NULL DEFAULT 0 CHECK ("es_maestro" IN (0, 1))'));

      final sqlEvento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'usuario_evento'")
                  .single['sql']
              as String;
      expect(sqlEvento, contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 37 → 38 conserva una Compra real y crea las tablas de Usuarios vacías, sin backfill ni '
    'siembra de CodigoSecuencia (Usuario no tiene folio)',
    () async {
      final schemaV37 = await verifier.schemaAt(37);
      final raw = schemaV37.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO compra (
        id, folio_compra, fecha, forma_pago, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'compra-real', 'COM-000001', 1700000000, 'efectivo', 'registrada', 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV37.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final compras = await db.select(db.compra).get();
      expect(compras, hasLength(1), reason: 'ninguna Compra real debe perderse en una migración puramente aditiva');

      final usuarios = await db.select(db.usuario).get();
      expect(usuarios, isEmpty, reason: 'Usuario es tabla nueva en la Etapa 11A, sin backfill');
      final eventos = await db.select(db.usuarioEvento).get();
      expect(eventos, isEmpty);

      final codigoUsuario =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('usuario'))).getSingleOrNull();
      expect(codigoUsuario, isNull, reason: 'Usuario no tiene folio — nunca se siembra un CodigoSecuencia para él');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('UNIQUE de Usuario.nombreUsuario tras la migración', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'pbkdf2\$1\$AA==\$BB=='),
        );

    await expectLater(
      db.into(db.usuario).insert(
            UsuarioCompanion.insert(nombre: 'Otra Ana', nombreUsuario: 'ana', passwordHash: 'pbkdf2\$1\$CC==\$DD=='),
          ),
      throwsA(anything),
      reason: 'nombre_usuario debe ser único',
    );

    await db.close();
  });

  test(
    '39.json coincide con el esquema final de la Etapa 11B (tabla nueva PermisoUsuario) — '
    'permisos dinámicos por Usuario',
    () async {
      final schema = await verifier.schemaAt(39);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('permiso_usuario'));

      final sqlPermisoUsuario =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'permiso_usuario'")
                  .single['sql']
              as String;
      expect(sqlPermisoUsuario, contains('PRIMARY KEY ("usuario_id", "codigo")'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 38 → 39 conserva un Usuario real y crea PermisoUsuario vacía, sin backfill '
    '(el Maestro nunca recibe filas — sus permisos se calculan en memoria)',
    () async {
      final schemaV38 = await verifier.schemaAt(38);
      final raw = schemaV38.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO usuario (
        id, nombre, nombre_usuario, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'usuario-real', 'Ana Real', 'ana.real', 'pbkdf2\$1\$AA==\$BB==', 1, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV38.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final usuarios = await db.select(db.usuario).get();
      expect(usuarios, hasLength(1), reason: 'ningún Usuario real debe perderse en una migración puramente aditiva');

      final permisos = await db.select(db.permisoUsuario).get();
      expect(permisos, isEmpty, reason: 'PermisoUsuario es tabla nueva en la Etapa 11B, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('PermisoUsuario: llave primaria compuesta permite el mismo código en usuarios distintos '
      'pero rechaza repetir el mismo par', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final u1 = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'pbkdf2\$1\$AA==\$BB=='),
        );
    final u2 = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(nombre: 'Beto', nombreUsuario: 'beto', passwordHash: 'pbkdf2\$1\$CC==\$DD=='),
        );

    await db.into(db.permisoUsuario).insert(PermisoUsuarioCompanion.insert(usuarioId: u1.id, codigo: 'personal.ver'));
    // Mismo código, usuario distinto — permitido.
    await db.into(db.permisoUsuario).insert(PermisoUsuarioCompanion.insert(usuarioId: u2.id, codigo: 'personal.ver'));

    await expectLater(
      db.into(db.permisoUsuario).insert(PermisoUsuarioCompanion.insert(usuarioId: u1.id, codigo: 'personal.ver')),
      throwsA(anything),
      reason: 'el mismo par (usuario, código) no puede repetirse',
    );

    await db.close();
  });

  test(
    '40.json coincide con el esquema final de la Etapa 11D (actor_usuario_id en 15 tablas + '
    'EliminacionFisicaEvento) — la columna actor legacy permanece físicamente sin cambios',
    () async {
      final schema = await verifier.schemaAt(40);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, contains('eliminacion_fisica_evento'));

      final sqlEliminacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'eliminacion_fisica_evento'")
                  .single['sql']
              as String;
      expect(sqlEliminacion, contains('"tipo_entidad" TEXT NOT NULL'));
      expect(sqlEliminacion, contains('"entidad_id_original" TEXT NOT NULL'));
      expect(sqlEliminacion, contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'));
      expect(sqlEliminacion, contains('"motivo" TEXT NOT NULL'));
      expect(sqlEliminacion, contains('"snapshot_json" TEXT NOT NULL'));

      // Muestra representativa de las 15 tablas — no las 15, mismo
      // criterio que el resto de la suite de migraciones.
      for (final tabla in ['compra_evento', 'movimiento_inventario', 'recarga_linea_telefonica', 'vehiculo_documento']) {
        final sql =
            schema.rawDatabase.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [tabla]).single['sql']
                as String;
        expect(
          sql,
          contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'),
          reason: '$tabla debe tener actor_usuario_id tras la migración a 40',
        );
      }

      // La columna legacy `actor` permanece físicamente en las 12 tablas
      // donde ya existía — decisión explícita de Marlon (migración
      // aditiva, sin dropColumn).
      final sqlCompraEvento =
          schema.rawDatabase.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra_evento'").single['sql']
              as String;
      expect(sqlCompraEvento, contains('"actor" TEXT NULL'), reason: 'la columna legacy actor debe seguir existiendo físicamente');

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 39 → 40 conserva una Compra/CompraEvento real, agrega actor_usuario_id nullable '
    '(null en el histórico) y crea EliminacionFisicaEvento vacía, sin backfill',
    () async {
      final schemaV39 = await verifier.schemaAt(39);
      final raw = schemaV39.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO compra (
        id, folio_compra, fecha, forma_pago, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'compra-real', 'COM-000001', 1700000000, 'efectivo', 'registrada', 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO compra_evento (
        compra_id, fecha_hora, tipo_evento, actor
      ) VALUES (
        'compra-real', 1700000000, 'registrada', NULL
      );
    ''');

      final db = AppDatabase(schemaV39.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final compras = await db.select(db.compra).get();
      expect(compras, hasLength(1), reason: 'ninguna Compra real debe perderse en una migración puramente aditiva');

      final eventos = await db.select(db.compraEvento).get();
      expect(eventos, hasLength(1));
      expect(eventos.single.actorUsuarioId, isNull, reason: 'histórico anterior a 11D queda con actorUsuarioId = null');

      final eliminaciones = await db.select(db.eliminacionFisicaEvento).get();
      expect(eliminaciones, isEmpty, reason: 'EliminacionFisicaEvento es tabla nueva en la Etapa 11D, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('EliminacionFisicaEvento: actor_usuario_id sobrevive con SET NULL si el Usuario se elimina', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final usuario = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'pbkdf2\$1\$AA==\$BB==', esMaestro: const Value(true)),
        );

    await db.into(db.eliminacionFisicaEvento).insert(
          EliminacionFisicaEventoCompanion.insert(
            tipoEntidad: 'vehiculo',
            entidadIdOriginal: 'vehiculo-inexistente-ya-borrado',
            fechaHora: DateTime(2026, 1, 1),
            motivo: 'Error de captura — vehículo duplicado, nunca utilizado.',
            snapshotJson: '{"marca":"Nissan"}',
            actorUsuarioId: Value(usuario.id),
          ),
        );

    await db.delete(db.usuario).delete(usuario);

    final eventos = await db.select(db.eliminacionFisicaEvento).get();
    expect(eventos, hasLength(1), reason: 'el evento sobrevive aunque el Usuario que lo generó se elimine');
    expect(eventos.single.actorUsuarioId, isNull);

    await db.close();
  });

  test(
    '41.json coincide con el esquema final de la Etapa 9D (imei2 + actor_usuario_id en '
    'ArticuloUnidadTelefono/AsignacionLineaTelefonica/LineaTelefonicaEquipo + '
    'EquipoTelefonicoCredencial/EquipoTelefonicoEvento) — expediente del teléfono físico',
    () async {
      final schema = await verifier.schemaAt(41);
      final tablas =
          schema.rawDatabase
              .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
              )
              .map((row) => row['name'] as String)
              .toSet();

      expect(tablas, containsAll(['equipo_telefonico_credencial', 'equipo_telefonico_evento']));

      final sqlCredencial =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'equipo_telefonico_credencial'")
                  .single['sql']
              as String;
      expect(sqlCredencial, contains('"unidad_id" TEXT NOT NULL REFERENCES articulo_unidad (id) ON DELETE CASCADE'));
      expect(sqlCredencial, contains('PRIMARY KEY ("unidad_id")'));
      expect(sqlCredencial, contains('"correo" TEXT'));
      expect(sqlCredencial, contains('"contrasena_cifrada" TEXT'));
      expect(sqlCredencial, contains('"fecha_actualizacion_contrasena" INTEGER'));

      final sqlEvento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'equipo_telefonico_evento'")
                  .single['sql']
              as String;
      expect(sqlEvento, contains('"unidad_id" TEXT NOT NULL REFERENCES articulo_unidad (id) ON DELETE RESTRICT'));
      expect(sqlEvento, contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'));
      expect(sqlEvento, contains('"tipo_evento" TEXT NOT NULL'));

      final sqlTelefono =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo_unidad_telefono'")
                  .single['sql']
              as String;
      expect(sqlTelefono, contains('"imei2" TEXT'));

      for (final tabla in ['asignacion_linea_telefonica', 'linea_telefonica_equipo']) {
        final sql =
            schema.rawDatabase.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [tabla]).single['sql']
                as String;
        expect(
          sql,
          contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'),
          reason: '$tabla debe tener actor_usuario_id tras la migración a 41',
        );
      }

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 40 → 41 conserva una LineaTelefonica/AsignacionLineaTelefonica/ArticuloUnidadTelefono '
    'real, agrega imei2/actor_usuario_id nullable (null en el histórico) y crea '
    'EquipoTelefonicoCredencial/EquipoTelefonicoEvento vacías, sin backfill',
    () async {
      final schemaV40 = await verifier.schemaAt(40);
      final raw = schemaV40.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Teléfonos', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo (
        id, folio, categoria_id, nombre, maneja_variante, maneja_serie,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('articulo-real', 'ART-000001', 'categoria-real', 'Teléfono POCO C71', 0, 1, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo_unidad (
        id, codigo, articulo_id, numero_serie, marca, modelo, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('unidad-real', 'UNI-000001', 'articulo-real', 'SN-REAL-001', 'POCO', 'C71', 'disponible',
        1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo_unidad_telefono (unidad_id, imei, numero_telefonico)
      VALUES ('unidad-real', '123456789012345', '7291220187');
    ''');
      raw.execute('''
      INSERT INTO linea_telefonica (
        id, codigo, numero, operador, modalidad_sim, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('linea-real', 'TEL-000001', '7291220187', 'telcel', 'fisica', 'activa',
        1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO asignacion_linea_telefonica (
        id, linea_telefonica_id, empleado_id, fecha_inicio,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('asignacion-real', 'linea-real', 'empleado-real', 1700000000, 1700000000, 1700000000, 'activo');
    ''');

      final db = AppDatabase(schemaV40.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final unidades = await db.select(db.articuloUnidad).get();
      expect(unidades, hasLength(1), reason: 'ninguna ArticuloUnidad real debe perderse en una migración puramente aditiva');

      final telefonos = await db.select(db.articuloUnidadTelefono).get();
      expect(telefonos, hasLength(1));
      expect(telefonos.single.imei2, isNull, reason: 'imei2 es nuevo — no hay dato histórico que llenarlo');
      expect(telefonos.single.imei, '123456789012345', reason: 'el IMEI 1 existente se conserva intacto');

      final asignacionesLinea = await db.select(db.asignacionLineaTelefonica).get();
      expect(asignacionesLinea, hasLength(1));
      expect(asignacionesLinea.single.empleadoId, 'empleado-real', reason: 'la asignación real no debe perderse');
      expect(asignacionesLinea.single.actorUsuarioId, isNull, reason: 'histórico anterior a 9D queda con actorUsuarioId = null');

      final credenciales = await db.select(db.equipoTelefonicoCredencial).get();
      expect(credenciales, isEmpty, reason: 'EquipoTelefonicoCredencial es tabla nueva en la Etapa 9D, sin backfill');

      final eventos = await db.select(db.equipoTelefonicoEvento).get();
      expect(eventos, isEmpty, reason: 'EquipoTelefonicoEvento es tabla nueva en la Etapa 9D, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('EquipoTelefonicoCredencial se elimina en cascada si su ArticuloUnidad se elimina', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final categoria = await db
        .into(db.categoriaArticulo)
        .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(folio: 'ART-000001', categoriaId: categoria.id, nombre: 'Teléfono', manejaSerie: const Value(true)),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(codigo: 'UNI-000001', articuloId: articulo.id, numeroSerie: 'SN-001'),
        );
    await db.into(db.equipoTelefonicoCredencial).insert(
          EquipoTelefonicoCredencialCompanion.insert(unidadId: unidad.id, correo: const Value('equipo@riseg.mx')),
        );

    await db.delete(db.articuloUnidad).delete(unidad);

    final credenciales = await db.select(db.equipoTelefonicoCredencial).get();
    expect(credenciales, isEmpty, reason: 'ON DELETE CASCADE — la credencial no debe sobrevivir sin su unidad');

    await db.close();
  });

  test('EquipoTelefonicoEvento: actor_usuario_id sobrevive con SET NULL si el Usuario se elimina', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final categoria = await db
        .into(db.categoriaArticulo)
        .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(folio: 'ART-000001', categoriaId: categoria.id, nombre: 'Teléfono', manejaSerie: const Value(true)),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(codigo: 'UNI-000001', articuloId: articulo.id, numeroSerie: 'SN-001'),
        );
    final usuario = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'pbkdf2\$1\$AA==\$BB=='),
        );

    await db.into(db.equipoTelefonicoEvento).insert(
          EquipoTelefonicoEventoCompanion.insert(
            unidadId: unidad.id,
            fechaHora: DateTime(2026, 1, 1),
            tipoEvento: 'equipoConfigurado',
            actorUsuarioId: Value(usuario.id),
          ),
        );

    await db.delete(db.usuario).delete(usuario);

    final eventos = await db.select(db.equipoTelefonicoEvento).get();
    expect(eventos, hasLength(1), reason: 'el evento sobrevive aunque el Usuario que lo generó se elimine');
    expect(eventos.single.actorUsuarioId, isNull);

    await db.close();
  });

  test(
    '42.json coincide con el esquema final de la Etapa 9D (ajuste posterior: actor_usuario_id en '
    'Asignacion) — "cambiar responsable" del mismo bien, sin MovimientoInventario ni cambio de estatus',
    () async {
      final schema = await verifier.schemaAt(42);
      final sqlAsignacion =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion'")
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'),
        reason: 'Asignacion debe tener actor_usuario_id tras la migración a 42',
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 41 → 42 conserva una Asignacion real (activa, vigente) y agrega actor_usuario_id '
    'nullable (null en el histórico), sin tocar ninguna otra columna',
    () async {
      final schemaV41 = await verifier.schemaAt(41);
      final raw = schemaV41.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Uniformes', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo (
        id, folio, categoria_id, nombre, maneja_variante, maneja_serie,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('articulo-real', 'ART-000001', 'categoria-real', 'Camisa RISEG', 0, 0, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1735689600, 3, 'activo',
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO asignacion (
        id, articulo_id, cantidad, empleado_id, fecha_entrega, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('asignacion-real', 'articulo-real', 3, 'empleado-real', 1700000000, 'activa',
        1700000000, 1700000000, 'activo');
    ''');

      final db = AppDatabase(schemaV41.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final asignaciones = await db.select(db.asignacion).get();
      expect(asignaciones, hasLength(1), reason: 'ninguna Asignacion real debe perderse en una migración puramente aditiva');
      final asignacion = asignaciones.single;
      expect(asignacion.empleadoId, 'empleado-real');
      expect(asignacion.cantidad, 3);
      expect(asignacion.estatus, 'activa');
      expect(asignacion.actorUsuarioId, isNull, reason: 'histórico anterior a este ajuste queda con actorUsuarioId = null');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('cambiar responsable de una Asignacion real tras la migración: misma unidad, sin MovimientoInventario '
      'nuevo, estatus reasignada en la fila vieja', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final categoria = await db
        .into(db.categoriaArticulo)
        .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(folio: 'ART-000001', categoriaId: categoria.id, nombre: 'Teléfono', manejaSerie: const Value(true)),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(codigo: 'UNI-000001', articuloId: articulo.id, numeroSerie: 'SN-001'),
        );
    final empleadoA = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    final empleadoB = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 2,
            nombres: 'Ana',
            apellidoPaterno: 'García',
            sexo: 'femenino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'GAAX900101MDFXXX02',
            rfc: 'GAAX900101AB2',
            nss: '12345678902',
            estadoCivil: 'soltera',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );

    final asignacionRepo = AsignacionRepositoryImpl(db);
    final inicial = await asignacionRepo.crear(
      articuloId: articulo.id,
      unidadId: unidad.id,
      cantidad: 1,
      empleadoId: empleadoA.id,
      fechaEntrega: DateTime(2026, 1, 10),
    );
    final movimientosAntes = await db.select(db.movimientoInventario).get();

    final nueva = await asignacionRepo.cambiarResponsable(
      asignacionId: inicial.id,
      nuevoEmpleadoId: empleadoB.id,
      fecha: DateTime(2026, 2, 1),
    );

    expect(nueva.unidadId, unidad.id);
    expect(nueva.empleadoId, empleadoB.id);

    final anterior = await asignacionRepo.obtenerPorId(inicial.id);
    expect(anterior!.estatus, 'reasignada');

    final movimientosDespues = await db.select(db.movimientoInventario).get();
    expect(movimientosDespues.length, movimientosAntes.length, reason: 'sin MovimientoInventario nuevo');

    final unidadTrasCambio = await db.select(db.articuloUnidad).getSingle();
    expect(unidadTrasCambio.estatus, 'asignado', reason: 'nunca pasa por disponible');

    await db.close();
  });

  test(
    '43.json coincide con el esquema final de la Etapa 9D (segundo ajuste posterior: '
    'aplicacion_especializada en CategoriaArticulo)',
    () async {
      final schema = await verifier.schemaAt(43);
      final sqlCategoria =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'categoria_articulo'")
                  .single['sql']
              as String;
      expect(
        sqlCategoria,
        contains('"aplicacion_especializada" TEXT NULL'),
        reason: 'CategoriaArticulo debe tener aplicacion_especializada tras la migración a 43',
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 42 → 43 conserva una CategoriaArticulo real y agrega aplicacion_especializada '
    'nullable (null en el histórico), sin tocar ninguna otra columna',
    () async {
      final schemaV42 = await verifier.schemaAt(42);
      final raw = schemaV42.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Uniformes', 1700000000, 1700000000, 'activo');
    ''');

      final db = AppDatabase(schemaV42.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categorias = await db.select(db.categoriaArticulo).get();
      expect(categorias, hasLength(1), reason: 'ninguna CategoriaArticulo real debe perderse en una migración puramente aditiva');
      final categoria = categorias.single;
      expect(categoria.nombre, 'Uniformes');
      expect(categoria.aplicacionEspecializada, isNull, reason: 'histórico anterior a este ajuste queda genérico (null)');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'regularización de un Articulo mal configurado tras la migración: convierte cantidad en '
    'unidades, re-liga CompraPartidaMovimiento, no cambia existencia total',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos', aplicacionEspecializada: const Value('telefonia')));
      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(folio: 'ART-000002', categoriaId: categoria.id, nombre: 'SMARTPHONE'),
          );

      final inventarioRepo = InventarioRepositoryImpl(db);
      final movimiento = await inventarioRepo.registrarEntrada(
        articuloId: articulo.id,
        cantidad: 2,
        costoUnitario: 179400,
        fecha: DateTime(2026, 1, 5),
        observaciones: 'Compra COM-000001',
      );

      final articuloRepo = ArticuloRepositoryImpl(db);
      final regularizarUseCase = RegularizarArticuloSerializadoUseCase(
        articuloRepo,
        inventarioRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      );

      final resultado = await regularizarUseCase.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: [
          const DatosUnidadRegularizacionInput(numeroSerie: 'SN-REG-001'),
          const DatosUnidadRegularizacionInput(numeroSerie: 'SN-REG-002'),
        ],
      );

      expect(resultado, isA<RegularizarArticuloSerializadoExitoso>());
      final unidades = (resultado as RegularizarArticuloSerializadoExitoso).unidades;
      expect(unidades, hasLength(2));

      final articuloActualizado = await articuloRepo.obtenerPorId(articulo.id);
      expect(articuloActualizado!.manejaSerie, isTrue);

      final movimientos = await db.select(db.movimientoInventario).get();
      expect(movimientos, hasLength(2), reason: 'el movimiento original por cantidad se borra, quedan 2 nuevos de unidad');
      expect(movimientos.every((m) => m.unidadId != null && m.cantidad == 1), isTrue);

      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.total, 2, reason: 'la existencia total no cambia con la regularización');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      await db.close();
    },
  );

  test(
    '44.json coincide con el esquema final de la Etapa 9D (tercer ajuste posterior: tabla nueva '
    'ArticuloUnidadEvento) — corrección de identidad de unidad',
    () async {
      final schema = await verifier.schemaAt(44);
      final tablas = schema.rawDatabase
          .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(tablas, contains('articulo_unidad_evento'));

      final sqlEvento =
          schema.rawDatabase
                  .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo_unidad_evento'")
                  .single['sql']
              as String;
      expect(sqlEvento, contains('"unidad_id" TEXT NOT NULL REFERENCES articulo_unidad (id)'));
      expect(sqlEvento, contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'));
      expect(sqlEvento, contains('"tipo_evento" TEXT NOT NULL'));
      expect(sqlEvento, contains('"campo" TEXT NOT NULL'));
      expect(sqlEvento, contains('"valor_anterior" TEXT'));
      expect(sqlEvento, contains('"valor_nuevo" TEXT'));
      expect(sqlEvento, contains('"motivo" TEXT NOT NULL'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 43 → 44 conserva una ArticuloUnidad real y crea ArticuloUnidadEvento vacía',
    () async {
      final schemaV43 = await verifier.schemaAt(43);
      final raw = schemaV43.rawDatabase;

      raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Teléfonos', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo (
        id, folio, categoria_id, nombre, maneja_variante, maneja_serie,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('articulo-real', 'ART-000001', 'categoria-real', 'SMARTPHONE', 0, 1, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo_unidad (
        id, codigo, articulo_id, numero_serie, marca, modelo, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES ('unidad-real', 'UNI-000001', 'articulo-real', 'SN-REAL-001', 'Samsung', 'A15', 'disponible',
        1700000000, 1700000000, 'activo');
    ''');

      final db = AppDatabase(schemaV43.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final unidades = await db.select(db.articuloUnidad).get();
      expect(unidades, hasLength(1), reason: 'ninguna ArticuloUnidad real debe perderse en una migración puramente aditiva');
      expect(unidades.single.numeroSerie, 'SN-REAL-001');
      expect(unidades.single.id, 'unidad-real');
      expect(unidades.single.codigo, 'UNI-000001');

      final eventos = await db.select(db.articuloUnidadEvento).get();
      expect(eventos, isEmpty, reason: 'tabla nueva, sin backfill');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('45.json coincide con el esquema de la Bóveda de Accesos del Maestro (Etapa 14D: tablas nuevas '
      'BovedaCredencial/BovedaCredencialEvento)', () async {
    final schema = await verifier.schemaAt(45);
    final tablas = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(tablas, containsAll(['boveda_credencial', 'boveda_credencial_evento']));

    final sqlCredencial =
        schema.rawDatabase
                .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'boveda_credencial'")
                .single['sql']
            as String;
    expect(sqlCredencial, contains('"nombre" TEXT NOT NULL'));
    expect(sqlCredencial, contains('"tipo" TEXT NOT NULL'));
    expect(sqlCredencial, contains('"secreto_cifrado" TEXT'));
    expect(sqlCredencial, contains('"ciclo_vida_registro" TEXT NOT NULL'));

    final sqlEvento =
        schema.rawDatabase
                .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'boveda_credencial_evento'")
                .single['sql']
            as String;
    expect(sqlEvento, contains('"credencial_id" TEXT NOT NULL REFERENCES boveda_credencial (id) ON DELETE RESTRICT'));
    expect(sqlEvento, contains('"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL'));
    expect(sqlEvento, contains('"tipo_evento" TEXT NOT NULL'));

    schema.rawDatabase.dispose();
  });

  test('migración 44 → 45 conserva datos existentes y crea las tablas de la Bóveda vacías', () async {
    final schemaV44 = await verifier.schemaAt(44);
    final raw = schemaV44.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO usuario (
        id, nombre_usuario, nombre, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
      ) VALUES ('usuario-real', 'maestro', 'Maestro Real', 'hash', 1, 1700000000, 1700000000, 'activo');
    ''');

    final db = AppDatabase(schemaV44.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final usuarios = await db.select(db.usuario).get();
    expect(usuarios, hasLength(1), reason: 'ningún Usuario real debe perderse en una migración puramente aditiva');
    expect(usuarios.single.id, 'usuario-real');

    final credenciales = await db.select(db.bovedaCredencial).get();
    expect(credenciales, isEmpty, reason: 'tabla nueva, sin backfill');
    final eventos = await db.select(db.bovedaCredencialEvento).get();
    expect(eventos, isEmpty, reason: 'tabla nueva, sin backfill');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty);

    final integridad =
        await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
    expect(integridad, ['ok']);

    await db.close();
  });

  test('46.json coincide con el esquema de "Recuérdame en este equipo" (Etapa 15: tabla nueva '
      'SesionPersistente)', () async {
    final schema = await verifier.schemaAt(46);
    final tablas = schema.rawDatabase
        .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(tablas, contains('sesion_persistente'));

    final sql =
        schema.rawDatabase
                .select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sesion_persistente'")
                .single['sql']
            as String;
    expect(sql, contains('"usuario_id" TEXT NOT NULL REFERENCES usuario (id) ON DELETE CASCADE'));
    expect(sql, contains('"token_hash" TEXT NOT NULL UNIQUE'));
    expect(sql, contains('"created_at" INTEGER NOT NULL'));

    schema.rawDatabase.dispose();
  });

  test('migración 45 → 46 conserva datos existentes y crea SesionPersistente vacía', () async {
    final schemaV45 = await verifier.schemaAt(45);
    final raw = schemaV45.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO usuario (
        id, nombre_usuario, nombre, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
      ) VALUES ('usuario-real', 'maestro', 'Maestro Real', 'hash', 1, 1700000000, 1700000000, 'activo');
    ''');

    final db = AppDatabase(schemaV45.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final usuarios = await db.select(db.usuario).get();
    expect(usuarios, hasLength(1), reason: 'ningún Usuario real debe perderse en una migración puramente aditiva');

    final sesiones = await db.select(db.sesionPersistente).get();
    expect(sesiones, isEmpty, reason: 'tabla nueva, sin backfill');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violacionesFk, isEmpty);

    final integridad =
        await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
    expect(integridad, ['ok']);

    await db.close();
  });

  test(
    'corregir identidad de una ArticuloUnidad real tras la migración: número de serie y marca '
    'cambian, mismo id/código, evento de auditoría con valor anterior y nuevo',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(
              id: const Value('usuario-actor'),
              nombre: 'Usuario de prueba',
              nombreUsuario: 'usuario-prueba',
              passwordHash: 'x',
            ),
          );

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
      final articulo = await db.into(db.articulo).insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'SMARTPHONE',
              manejaSerie: const Value(true),
            ),
          );
      final inventarioRepo = InventarioRepositoryImpl(db);
      final unidad = await inventarioRepo.registrarEntradaUnidad(
        articuloId: articulo.id,
        codigo: 'UNI-000001',
        numeroSerie: 'SN-MAL-CAPTURADA',
        fecha: DateTime(2026, 1, 1),
      );

      final corregir = CorregirIdentidadUnidadUseCase(inventarioRepo);
      final resultado = await corregir.ejecutar(
        unidadId: unidad.id,
        motivo: 'Error de captura al dar de alta.',
        numeroSerie: 'SN-CORRECTA-001',
        marca: 'Samsung',
        actorUsuarioId: 'usuario-actor',
      );

      expect(resultado, isA<CorregirIdentidadUnidadExitoso>());
      final corregida = (resultado as CorregirIdentidadUnidadExitoso).unidad;
      expect(corregida.id, unidad.id, reason: 'mismo ArticuloUnidad.id');
      expect(corregida.codigo, 'UNI-000001', reason: 'mismo código');
      expect(corregida.numeroSerie, 'SN-CORRECTA-001');
      expect(corregida.marca, 'Samsung');

      final eventos = await inventarioRepo.listarEventosUnidad(unidad.id);
      expect(eventos, hasLength(2), reason: 'un evento por campo que cambió (numeroSerie y marca)');
      final eventoSerie = eventos.firstWhere((e) => e.campo == 'numeroSerie');
      expect(eventoSerie.valorAnterior, 'SN-MAL-CAPTURADA');
      expect(eventoSerie.valorNuevo, 'SN-CORRECTA-001');
      expect(eventoSerie.actorUsuarioId, 'usuario-actor');
      expect(eventoSerie.motivo, 'Error de captura al dar de alta.');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      await db.close();
    },
  );
}
