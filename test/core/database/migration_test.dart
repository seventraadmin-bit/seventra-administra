// Nota (Etapa 15, verificada al cerrar ClientePortal): los archivos
// `riseg_one.sqlite.bak-<etapa>-<timestamp>` de
// `AppData/Roaming/RISEG/RISEG ONE/RISEGONE-dev/` NO son fixtures
// confiables de versiones históricas reales — se verificó abriendo el
// más reciente (etiquetado "horario-v51") en modo solo lectura:
// `PRAGMA user_version` reportó 4 y ni siquiera existe la tabla
// `configuracion_cobro_vigencia` (existe desde la Etapa 4H.1). Además,
// todos esos archivos pesan exactamente lo mismo sin importar la
// etapa, señal de que nunca acumularon datos reales. Nunca usar esos
// `.bak-*` como snapshot de prueba — el patrón correcto para "datos
// reales" en este archivo es `SchemaVerifier.schemaAt(N)` + `INSERT`
// manual de una fila representativa (ver los tests "... conserva una
// fila real" de más abajo), nunca un `.sqlite` de esa carpeta.
import 'package:drift/drift.dart' show Migrator, OrderingTerm, Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/migrations/migrar_vinculo_usuario_empleado_v92.dart';
import 'package:riseg_one/core/database/migrations/migrar_cuenta_por_cobrar_v14.dart';
import 'package:riseg_one/core/database/migrations/migrar_correccion_cuenta_por_cobrar_v74.dart';
import 'package:riseg_one/core/database/migrations/migrar_egreso_origen_tarjeta_v76.dart';
import 'package:riseg_one/core/database/migrations/migrar_correccion_pago_deuda_v77.dart';
import 'package:riseg_one/core/database/migrations/migrar_conciliacion_baja_v83.dart';
import 'package:riseg_one/core/database/migrations/migrar_pendiente_recuperacion_v82.dart';
import 'package:riseg_one/core/database/migrations/migrar_telefonia_trazabilidad_v81.dart';
import 'package:riseg_one/core/database/migrations/migrar_vehiculos_origen_financiero_v80.dart';
import 'package:riseg_one/core/database/migrations/migrar_permisos_granulares_v71.dart';
import 'package:riseg_one/core/database/seed/seed_data.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_fechas_cobro_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_identidad_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/regularizar_articulo_serializado_usecase.dart';

import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/core/database/migrations/migrar_trazabilidad_comercial_v84.dart';
import '../../generated_migrations/schema.dart';

/// `AppDatabase.schemaVersion` actual — único lugar de ESTE archivo que
/// hay que tocar cuando suba, y ya no depende de que alguien se acuerde:
/// la primera prueba de `main()` falla si se queda atrás (ver "La versión
/// de esquema está sincronizada en los tres lugares"). Las pruebas que empiezan en `schemaAt(1)` y dependen de
/// `_createEtapa4ATables` (el camino `from == 1` de `onUpgrade`)
/// **deben** apuntar aquí, nunca a un número de versión intermedio
/// fijo: `_createEtapa4ATables` siempre construye con la forma *actual*
/// de las clases Dart, sin importar el objetivo nominal que
/// `SchemaVerifier.migrateAndValidate` reciba — apuntar a una versión
/// vieja (p. ej. 4, cuando la actual ya es 5) produce una comparación
/// de esquema que no puede coincidir nunca. Ya mordió dos veces
/// (Etapas 4E.1 y 4E.2); de aquí en adelante, súbelo junto con
/// `schemaVersion` en el mismo cambio.
const _currentSchemaVersion = 93;

/// `AlmacenClaveCifrado` en memoria — la migración a `schemaVersion` 52
/// cifra contraseñas de portal legadas con `CredentialCipher`, y el
/// almacén real (`AlmacenClaveSeguraWindows`) usa canales de
/// plataforma que no responden bajo `flutter test` (mismo motivo que
/// `boveda_usecases_test.dart`).
class _AlmacenClaveCifradoEnMemoria implements AlmacenClaveCifrado {
  String? _clave;

  @override
  Future<String?> leer() async => _clave;

  @override
  Future<void> escribir(String valor) async => _clave = valor;
}

/// Verifica la migración real 1 → 2 sobre una base física construida
/// desde el snapshot de schemaVersion 1 (`drift_schemas/riseg_one/`) —
/// no una prueba manual de `onUpgrade`, sino la migración generada
/// corriendo contra el esquema histórico real.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // Guardrail (añadido al cerrar la Etapa 4D).
  //
  // Subir `schemaVersion` obliga a tocar TRES sitios, y hasta ahora los tres
  // dependían de que alguien se acordara. En 4D no ocurrió: la aplicación
  // pasó a 93 mientras este archivo seguía validando contra la referencia de
  // la 92. No falló nada, y ese es justo el problema —
  // `migrateAndValidate` migra la base a su última versión y la compara
  // contra la referencia que se le pide, pero `ValidationOptions` trae
  // `validateDropped: false`, así que una tabla nueva que la referencia no
  // conoce es invisible. Las 168 comprobaciones de más abajo seguían en
  // verde sin comprobar la forma real del esquema.
  //
  // Esta prueba convierte ese desfase silencioso en un fallo inmediato.
  test('La versión de esquema está sincronizada en los tres lugares', () {
    final versionDeLaAplicacion = AppDatabase(NativeDatabase.memory()).schemaVersion;

    expect(
      _currentSchemaVersion,
      versionDeLaAplicacion,
      reason:
          'AppDatabase.schemaVersion es $versionDeLaAplicacion y este archivo valida contra '
          '$_currentSchemaVersion. Sube `_currentSchemaVersion` a $versionDeLaAplicacion; si no, las '
          '168 llamadas a migrateAndValidate de abajo comparan contra un esquema viejo y pasan sin '
          'comprobar nada de la versión nueva.',
    );

    expect(
      GeneratedHelper.versions.last,
      versionDeLaAplicacion,
      reason:
          'No existe snapshot de la versión $versionDeLaAplicacion en test/generated_migrations/. '
          'Hay que generar schema_v$versionDeLaAplicacion.dart desde su JSON de drift_schemas/ y '
          'añadirlo a mano a schema.dart (import + case + entrada en versions). NO ejecutes '
          '`drift_dev schema generate` sobre test/generated_migrations: borraría los cases '
          'históricos que no tienen JSON (79-83 y 87-90).',
    );
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
      // Etapa 5B.3: esta base no traía ninguna Empresa, así que la que
      // ve aquí la acaba de crear la siembra — con el código neutral.
      expect(empresas.single.codigo, 'EMP-01');

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
      expect(
        codigosSecuencia,
        hasLength(30), // +1: folio TRF de transferencias (v91)
        reason:
            'incluye las 2 sembradas en 57 (descuentoProgramadoPrestamo/Botas), la de 60 (entrega), la de 61 '
            '(deuda), la de 63 (cuenta_financiera), la de 65 (tiempoExtra), la de 83 '
            '(descuentoProgramadoResguardo, obligaciones nacidas de una conciliación de baja) y la de 87 '
            '(servicioEventual, folios EVT)',
      );

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
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

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
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

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
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

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
    'migración 1 → versión actual siembra las 8 modalidades de turno confirmadas',
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
        '12X24',
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
      expect(modalidades, hasLength(8));

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
    'migración 9 → actual conserva una Configuración de cobro real y crea la tabla de etapas de cobro vacía '
    '(Etapa 15: configuracion_cobro_regla_evento fue reemplazada por configuracion_cobro_etapa)',
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

      final etapas = await db.select(db.configuracionCobroEtapa).get();
      expect(etapas, isEmpty);

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
    'acepta una etapa de cobro válida tras la migración (Etapa 15)',
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
              tipoDocumento: 'cfdi',
              frecuenciaId: SeedIds.frecuenciaCobroMensual,
              diaInicioPeriodo: 21,
              agrupacion: 'porEntidadFiscal',
              metodo: 'ppd',
              requiereComplemento: const Value(true),
              fechaInicioVigencia: DateTime(2026, 1, 21),
            ),
          );

      final etapa = await db
          .into(db.configuracionCobroEtapa)
          .insertReturning(
            ConfiguracionCobroEtapaCompanion.insert(
              id: 'etapa-emision-real',
              configuracionCobroVigenciaId: vigencia.id,
              tipoSistema: const Value('emision'),
              orden: 0,
              tipoRegla: const Value('diaFijoDelMes'),
              mesRelativo: const Value('siguiente'),
              diaDelMes: const Value(21),
            ),
          );
      expect(etapa.tipoSistema, 'emision');
      expect(etapa.diaDelMes, 21);

      await db.close();
    },
  );

  test(
    'rechaza dos etapas de cobro con el mismo tipoSistema en la misma vigencia tras la migración (Etapa 15)',
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
          .into(db.configuracionCobroEtapa)
          .insert(
            ConfiguracionCobroEtapaCompanion.insert(
              id: 'etapa-pago-1',
              configuracionCobroVigenciaId: vigencia.id,
              tipoSistema: const Value('pagoEsperado'),
              orden: 2,
              tipoRegla: const Value('diaFijoDelMes'),
              mesRelativo: const Value('actual'),
              diaDelMes: const Value(10),
            ),
          );

      expect(
        () => db
            .into(db.configuracionCobroEtapa)
            .insert(
              ConfiguracionCobroEtapaCompanion.insert(
                id: 'etapa-pago-2',
                configuracionCobroVigenciaId: vigencia.id,
                tipoSistema: const Value('pagoEsperado'),
                orden: 2,
                tipoRegla: const Value('diaFijoDelMes'),
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
    'rechaza una etapa de cobro con vigencia inexistente tras la migración (Etapa 15)',
    () async {
      final schemaV8 = await verifier.schemaAt(8);
      final db = AppDatabase(schemaV8.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      expect(
        () => db.customStatement('''
        INSERT INTO configuracion_cobro_etapa (
          id, configuracion_cobro_vigencia_id, tipo_sistema, orden, tipo_regla, mes_relativo, dia_del_mes
        ) VALUES (
          'etapa-huerfana', 'vigencia-inexistente', 'emision', 0, 'diaFijoDelMes', 'actual', 1
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
              clienteId: Value(cliente.id),
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
              clienteId: Value(cliente.id),
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
      await db
          .into(db.pagoAttachment)
          .insert(
            PagoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              pagoId: pagoA.id,
            ),
          );

      expect(
        () => db
            .into(db.pagoAttachment)
            .insert(
              PagoAttachmentCompanion.insert(
                attachmentId: adjunto.id,
                pagoId: pagoB.id,
              ),
            ),
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
              documentoPorEmitirId: Value(documento.id),
              clienteId: Value(cliente.id),
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
                documentoPorEmitirId: Value(documento.id),
                clienteId: Value(cliente.id),
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
              clienteId: Value(cliente.id),
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
          .insert(
            PagoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              pagoId: pago.id,
            ),
          );

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
              clienteId: Value(cliente.id),
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
              clienteId: Value(cliente.id),
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
            ComplementoPagoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              complementoPagoId: complemento.id,
            ),
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
              clienteId: Value(cliente.id),
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
              clienteId: Value(cliente.id),
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
              clienteId: Value(cliente.id),
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
        containsAll(<String>[
          'categoria_financiera',
          'ingreso',
          'ingreso_evento',
          'egreso',
          'egreso_evento',
        ]),
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
        contains(
          '"pago_id" TEXT NULL UNIQUE REFERENCES pago (id) ON DELETE RESTRICT',
        ),
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
      expect(
        ingresos,
        isEmpty,
        reason:
            'Ingreso es tabla nueva en 4K.1, sin backfill automático del Pago existente',
      );

      final egresos = await db.select(db.egreso).get();
      expect(egresos, isEmpty);

      final categorias = await db.select(db.categoriaFinanciera).get();
      expect(
        categorias,
        isEmpty,
        reason:
            'el catálogo de CategoriaFinanciera nace vacío (Resolución de Marlon)',
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
    'acepta un Ingreso automático con comprobante adjunto (Attachment unido vía IngresoAttachment) tras la migración',
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
              clienteId: Value(cliente.id),
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
          .insert(
            IngresoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              ingresoId: ingreso.id,
            ),
          );

      expect(ingreso.estatus, 'registrado');

      await db.close();
    },
  );

  test('rechaza un Ingreso con Pago inexistente tras la migración', () async {
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
  });

  test(
    'rechaza un segundo Ingreso para el mismo Pago tras la migración (pagoId UNIQUE)',
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
              clienteId: Value(cliente.id),
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado'",
                  )
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'direccion'",
                  )
                  .single['sql']
              as String;
      expect(sqlDireccion, contains('"empleado_id" TEXT NULL UNIQUE'));
      expect(
        sqlDireccion,
        contains(
          'FOREIGN KEY (empleado_id) REFERENCES empleado (id) ON DELETE RESTRICT',
        ),
      );
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
      expect(
        sqlDireccion,
        contains("CHECK (empleado_id IS NULL OR tipo_direccion = 'domicilio')"),
      );

      final sqlAttachment =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attachment'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlAttachment,
        isNot(contains('empresa_id')),
        reason: 'Attachment ya no tiene columnas de dueño',
      );
      expect(
        sqlAttachment,
        isNot(contains('CHECK')),
        reason: 'el arco exclusivo desapareció junto con las columnas',
      );

      final sqlPagoAttachment =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pago_attachment'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlPagoAttachment,
        contains('REFERENCES attachment (id) ON DELETE CASCADE'),
      );
      expect(
        sqlPagoAttachment,
        contains('REFERENCES pago (id) ON DELETE CASCADE'),
      );
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
      expect(
        pagos,
        hasLength(1),
        reason: 'ningún Pago real debe perderse en una migración aditiva',
      );

      final empleados = await db.select(db.empleado).get();
      expect(
        empleados,
        isEmpty,
        reason: 'Empleado es tabla nueva en 5A, sin backfill',
      );

      final direcciones = await db.select(db.direccion).get();
      for (final d in direcciones) {
        expect(d.empleadoId, isNull);
      }

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
          .insert(
            EmpleadoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              empleadoId: empleado.id,
            ),
          );

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
        () => db
            .into(db.empleado)
            .insert(
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
      await db
          .into(db.direccion)
          .insert(
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
        () => db
            .into(db.direccion)
            .insert(
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
      expect(
        tablas,
        isNot(contains('empleado_evaluacion')),
        reason: 'sin tablas satélite, sin historial de evaluaciones',
      );

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
      final columnasEmpleado =
          schema.rawDatabase.select('PRAGMA table_info(empleado)').toList();
      for (final nombre in columnasNuevas) {
        final columna = columnasEmpleado.firstWhere(
          (c) => c['name'] == nombre,
          orElse:
              () =>
                  throw StateError(
                    'Falta la columna $nombre en empleado (19.json)',
                  ),
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
      expect(
        empleados,
        hasLength(1),
        reason: 'ningún Empleado real debe perderse en una migración aditiva',
      );
      final empleado = empleados.single;
      expect(empleado.numeroEmpleado, 1);
      expect(empleado.fechaEvaluacionPsicologica, isNull);
      expect(empleado.resumenPsicologico, isNull);
      expect(empleado.fechaEstudioSocioeconomico, isNull);
      expect(empleado.fechaAntidoping, isNull);
      expect(empleado.resultadoAmp, isNull);
      expect(empleado.resultadoOpi, isNull);

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

      final actualizado = await (db.update(db.empleado)
        ..where((t) => t.id.equals(empleado.id))).writeReturning(
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

      final columnasEmpleado =
          schema.rawDatabase.select('PRAGMA table_info(empleado)').toList();
      for (final nombre in [
        'fecha_baja',
        'motivo_baja',
        'observaciones_baja',
      ]) {
        final columna = columnasEmpleado.firstWhere(
          (c) => c['name'] == nombre,
          orElse:
              () =>
                  throw StateError(
                    'Falta la columna $nombre en empleado (20.json)',
                  ),
        );
        expect(columna['notnull'], 0, reason: '$nombre debe ser nullable');
      }

      final sqlPeriodo =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado_periodo_laboral'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlPeriodo,
        contains(
          '"empleado_id" TEXT NOT NULL REFERENCES empleado (id) ON DELETE CASCADE',
        ),
      );
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
      expect(
        empleados,
        hasLength(2),
        reason: 'ningún Empleado real debe perderse en una migración aditiva',
      );

      final empleado = empleados.firstWhere((e) => e.id == 'empleado-real');
      expect(empleado.fechaBaja, isNull);
      expect(empleado.motivoBaja, isNull);
      expect(empleado.observacionesBaja, isNull);

      final legado = empleados.firstWhere(
        (e) => e.id == 'empleado-baja-legado',
      );
      expect(legado.estatus, 'baja');
      expect(
        legado.fechaBaja,
        isNull,
        reason: 'sin backfill — invariante de aplicación, no de BD',
      );

      final periodos = await db.select(db.empleadoPeriodoLaboral).get();
      expect(
        periodos,
        isEmpty,
        reason: 'EmpleadoPeriodoLaboral es tabla nueva en 5C, sin backfill',
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

      await (db.update(db.empleado)
        ..where((t) => t.id.equals(empleado.id))).write(
        EmpleadoCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(DateTime(2026, 6, 15)),
          motivoBaja: const Value('renuncia'),
        ),
      );

      await db
          .into(db.empleadoPeriodoLaboral)
          .insert(
            EmpleadoPeriodoLaboralCompanion.insert(
              empleadoId: empleado.id,
              fechaIngreso: DateTime(2026, 1, 1),
              fechaBaja: DateTime(2026, 6, 15),
              motivoBaja: 'renuncia',
            ),
          );

      final periodos =
          await (db.select(db.empleadoPeriodoLaboral)
            ..where((t) => t.empleadoId.equals(empleado.id))).get();
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
        () => db
            .into(db.empleadoPeriodoLaboral)
            .insert(
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
          .firstWhere(
            (c) => c['name'] == 'codigo_postal_fiscal',
            orElse: () => throw StateError('Falta codigo_postal_fiscal'),
          );
      expect(
        columnaCp['notnull'],
        0,
        reason: 'codigo_postal_fiscal debe ser nullable',
      );

      final sqlAsignacion =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_servicio'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains('"empleado_id" TEXT NOT NULL REFERENCES empleado (id)'),
      );
      expect(
        sqlAsignacion,
        contains('"servicio_id" TEXT NOT NULL REFERENCES servicio (id)'),
      );
      expect(
        sqlAsignacion,
        contains('"turno_id" TEXT NULL REFERENCES tipo_modalidad_turno (id)'),
      );
      expect(sqlAsignacion, contains('"fecha_termino" INTEGER NULL'));
      expect(
        sqlAsignacion,
        contains(
          'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
        ),
      );

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
      expect(
        empleados,
        hasLength(1),
        reason: 'ningún Empleado real debe perderse en una migración aditiva',
      );
      expect(empleados.single.codigoPostalFiscal, isNull);

      final servicios = await db.select(db.servicio).get();
      expect(
        servicios,
        hasLength(1),
        reason: 'ningún Servicio real debe perderse en una migración aditiva',
      );

      final asignaciones = await db.select(db.asignacionServicio).get();
      expect(
        asignaciones,
        isEmpty,
        reason: 'AsignacionServicio es tabla nueva en 5D, sin backfill',
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
          .insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-000001',
              nombreComercial: 'Sportium',
            ),
          );
      final servicioA = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Servicio A',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      final servicioB = await db
          .into(db.servicio)
          .insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000002',
              clienteId: cliente.id,
              nombre: 'Servicio B',
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );

      await db
          .into(db.asignacionServicio)
          .insert(
            AsignacionServicioCompanion.insert(
              empleadoId: empleado.id,
              servicioId: servicioA.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );

      expect(
        () => db
            .into(db.asignacionServicio)
            .insert(
              AsignacionServicioCompanion.insert(
                empleadoId: empleado.id,
                servicioId: servicioB.id,
                fechaInicio: DateTime(2026, 2, 1),
              ),
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'ficha_tecnica_empleado'",
                  )
                  .single['sql']
              as String;
      expect(sqlFicha, contains('"folio" TEXT NOT NULL UNIQUE'));
      expect(
        sqlFicha,
        contains('"empleado_id" TEXT NOT NULL REFERENCES empleado (id)'),
      );
      expect(
        sqlFicha,
        contains('"servicio_id" TEXT NULL REFERENCES servicio (id)'),
      );
      expect(
        sqlFicha,
        contains('"attachment_id" TEXT NOT NULL REFERENCES attachment (id)'),
      );
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
      expect(
        empleados,
        hasLength(1),
        reason: 'ningún Empleado real debe perderse en una migración aditiva',
      );

      final codigoFichaTecnica =
          await (db.select(db.codigoSecuencia)..where(
            (t) => t.entityType.equals('ficha_tecnica'),
          )).getSingleOrNull();
      expect(
        codigoFichaTecnica,
        isNotNull,
        reason: 'runSeed debe sembrar el contador de folio de ficha_tecnica',
      );
      expect(codigoFichaTecnica!.prefijo, 'FICHA');

      final fichas = await db.select(db.fichaTecnicaEmpleado).get();
      expect(
        fichas,
        isEmpty,
        reason: 'FichaTecnicaEmpleado es tabla nueva en 5E, sin backfill',
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

  test('23.json coincide con el esquema final de la Etapa 6A (numeroEmpleado + datos bancarios + '
      'condición administrativa en Empleado, catálogo Banco)', () async {
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
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado'",
                )
                .single['sql']
            as String;
    expect(sqlEmpleado, isNot(contains('codigo_empleado')));
    expect(sqlEmpleado, contains('"numero_empleado" INTEGER NOT NULL UNIQUE'));
    expect(sqlEmpleado, contains('"banco_id" TEXT NULL REFERENCES banco (id)'));
    expect(sqlEmpleado, contains('"numero_cuenta_tarjeta" TEXT NULL'));
    expect(sqlEmpleado, contains('"clabe" TEXT NULL'));
    expect(
      sqlEmpleado,
      contains(
        'CHECK (sueldo_mensual_administrativo IS NULL OR sueldo_mensual_administrativo > 0)',
      ),
    );
    expect(
      sqlEmpleado,
      contains(
        'CHECK (bono_mensual_administrativo IS NULL OR bono_mensual_administrativo >= 0)',
      ),
    );

    schema.rawDatabase.dispose();
  });

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

      final empleados =
          await db.select(db.empleado).get()
            ..sort((a, b) => a.numeroEmpleado.compareTo(b.numeroEmpleado));
      expect(
        empleados,
        hasLength(2),
        reason:
            'ningún Empleado real debe perderse en una migración estructural',
      );
      expect(
        empleados[0].id,
        'empleado-1',
        reason: 'creado primero (created_at menor) → numeroEmpleado 1',
      );
      expect(empleados[0].numeroEmpleado, 1);
      expect(empleados[1].id, 'empleado-2');
      expect(empleados[1].numeroEmpleado, 2);
      expect(empleados[0].bancoId, isNull);
      expect(empleados[0].sueldoMensualAdministrativo, isNull);

      final bancos = await db.select(db.banco).get();
      expect(
        bancos,
        isNotEmpty,
        reason:
            'runSeed/seedBanco debe sembrar el catálogo Banco en la migración',
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
        db
            .into(db.empleado)
            .insert(base.copyWith(sueldoMensualAdministrativo: const Value(0))),
        throwsA(anything),
        reason:
            'sueldo_mensual_administrativo = 0 debe rechazarse (debe ser > 0)',
      );

      final conBonoCero = await db
          .into(db.empleado)
          .insertReturning(
            base.copyWith(bonoMensualAdministrativo: const Value(0)),
          );
      expect(
        conBonoCero.bonoMensualAdministrativo,
        0,
        reason: 'bono_mensual_administrativo = 0 sí es válido',
      );

      await db.close();
    },
  );

  test('24.json coincide con el esquema final de la Etapa 6B (sueldo/bono de referencia en Servicio, '
      'tabla nueva AsignacionServicioSueldoVigencia)', () async {
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
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'servicio'",
                )
                .single['sql']
            as String;
    expect(
      sqlServicio,
      contains(
        'CHECK (sueldo_mensual_referencia_personal IS NULL OR sueldo_mensual_referencia_personal > 0)',
      ),
    );
    expect(
      sqlServicio,
      contains(
        'CHECK (bono_mensual_referencia_personal IS NULL OR bono_mensual_referencia_personal >= 0)',
      ),
    );

    final sqlVigencia =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_servicio_sueldo_vigencia'",
                )
                .single['sql']
            as String;
    expect(
      sqlVigencia,
      contains(
        '"asignacion_servicio_id" TEXT NOT NULL REFERENCES asignacion_servicio (id)',
      ),
    );
    expect(sqlVigencia, contains('CHECK (sueldo_mensual > 0)'));
    expect(sqlVigencia, contains('CHECK (bono_mensual >= 0)'));

    schema.rawDatabase.dispose();
  });

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
      expect(
        servicios,
        hasLength(1),
        reason:
            'ningún Servicio real debe perderse en una migración estructural',
      );
      expect(servicios.single.id, 'servicio-real');
      expect(servicios.single.sueldoMensualReferenciaPersonal, isNull);
      expect(servicios.single.bonoMensualReferenciaPersonal, isNull);

      final vigenciasSueldo =
          await db.select(db.asignacionServicioSueldoVigencia).get();
      expect(
        vigenciasSueldo,
        isEmpty,
        reason:
            'AsignacionServicioSueldoVigencia es tabla nueva en 6B, sin backfill',
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
    'CHECK de sueldo/bono de referencia y de vigencia de sueldo tras la migración: sueldo debe ser > 0, bono acepta 0',
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
      final baseServicio = ServicioCompanion.insert(
        codigo: 'SER-000001',
        clienteId: cliente.id,
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      );

      await expectLater(
        db
            .into(db.servicio)
            .insert(
              baseServicio.copyWith(
                sueldoMensualReferenciaPersonal: const Value(0),
              ),
            ),
        throwsA(anything),
        reason:
            'sueldo_mensual_referencia_personal = 0 debe rechazarse (debe ser > 0)',
      );

      final servicio = await db
          .into(db.servicio)
          .insertReturning(
            baseServicio.copyWith(
              sueldoMensualReferenciaPersonal: const Value(1500000),
              bonoMensualReferenciaPersonal: const Value(0),
            ),
          );
      expect(
        servicio.bonoMensualReferenciaPersonal,
        0,
        reason: 'bono_mensual_referencia_personal = 0 sí es válido',
      );

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
              aniosExperienciaSeguridad: 0,
            ),
          );
      final asignacion = await db
          .into(db.asignacionServicio)
          .insertReturning(
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
        db
            .into(db.asignacionServicioSueldoVigencia)
            .insert(baseVigencia.copyWith(sueldoMensual: const Value(0))),
        throwsA(anything),
        reason:
            'sueldo_mensual = 0 debe rechazarse (debe ser > 0) en AsignacionServicioSueldoVigencia',
      );

      final vigencia = await db
          .into(db.asignacionServicioSueldoVigencia)
          .insertReturning(baseVigencia.copyWith(bonoMensual: const Value(0)));
      expect(
        vigencia.bonoMensual,
        0,
        reason:
            'bono_mensual = 0 sí es válido en AsignacionServicioSueldoVigencia',
      );

      await db.close();
    },
  );

  test('25.json coincide con el esquema final de la Etapa 6C (tablas nuevas Nomina, NominaEmpleado, '
      'NominaEmpleadoTramo, NominaEvento)', () async {
    final schema = await verifier.schemaAt(25);
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
        'nomina',
        'nomina_empleado',
        'nomina_empleado_tramo',
        'nomina_evento',
      ]),
    );

    final sqlNomina =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'nomina'",
                )
                .single['sql']
            as String;
    expect(sqlNomina, contains('UNIQUE (anio, mes, tipo_periodo)'));
    expect(sqlNomina, contains('"folio" TEXT NOT NULL UNIQUE'));
    expect(sqlNomina, contains('CHECK (mes >= 1 AND mes <= 12)'));

    final sqlNominaEmpleado =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'nomina_empleado'",
                )
                .single['sql']
            as String;
    expect(sqlNominaEmpleado, contains('UNIQUE (nomina_id, empleado_id)'));
    expect(sqlNominaEmpleado, contains('CHECK (dias_pagables >= 0)'));
    expect(sqlNominaEmpleado, contains('CHECK (sueldo_mensual_utilizado > 0)'));
    // Deliberadamente sin CHECK monto_fiscal + monto_no_fiscal == total_a_pagar
    // (Resolución explícita de Marlon: debe poder existir una distribución
    // temporalmente pendiente de revisar sin que la escritura falle).
    expect(
      sqlNominaEmpleado,
      isNot(contains('monto_fiscal + monto_no_fiscal')),
    );

    final sqlNominaEmpleadoTramo =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'nomina_empleado_tramo'",
                )
                .single['sql']
            as String;
    expect(sqlNominaEmpleadoTramo, contains('CHECK (dias_reales > 0)'));
    expect(sqlNominaEmpleadoTramo, contains('CHECK (sueldo_mensual > 0)'));

    schema.rawDatabase.dispose();
  });

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
      expect(
        empleados,
        hasLength(1),
        reason:
            'ningún Empleado real debe perderse en una migración puramente aditiva',
      );
      expect(empleados.single.id, 'empleado-real');

      final nominas = await db.select(db.nomina).get();
      expect(
        nominas,
        isEmpty,
        reason: 'Nomina es tabla nueva en 6C, sin backfill',
      );
      final renglones = await db.select(db.nominaEmpleado).get();
      expect(renglones, isEmpty);
      final tramos = await db.select(db.nominaEmpleadoTramo).get();
      expect(tramos, isEmpty);
      final eventos = await db.select(db.nominaEvento).get();
      expect(eventos, isEmpty);

      final codigoNomina =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('nomina'))).getSingleOrNull();
      expect(
        codigoNomina,
        isNotNull,
        reason: 'runSeed debe sembrar el contador de folio de nomina',
      );
      expect(codigoNomina!.prefijo, 'NOM');

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
    'CHECK de Nomina/NominaEmpleado/NominaEmpleadoTramo tras la migración: unicidad de periodo, distribución '
    'pendiente permitida temporalmente, importe_tramo >= 0',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nomina = await db
          .into(db.nomina)
          .insertReturning(
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
        db
            .into(db.nomina)
            .insert(
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
        reason:
            'una segunda Nómina para el mismo (anio, mes, tipo_periodo) debe rechazarse',
      );

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
      final renglonPendiente = await db
          .into(db.nominaEmpleado)
          .insertReturning(
            baseRenglon.copyWith(
              montoFiscal: const Value(100000),
              montoNoFiscal: const Value(0),
              distribucionPendienteRevision: const Value(true),
            ),
          );
      expect(renglonPendiente.distribucionPendienteRevision, isTrue);

      await expectLater(
        db
            .into(db.nominaEmpleadoTramo)
            .insert(
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

  test('26.json coincide con el esquema final de la Etapa 6D (tablas nuevas PagoNomina, AplicacionPagoNomina, '
      'PagoNominaEvento, PagoNominaAttachment)', () async {
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
      containsAll([
        'pago_nomina',
        'aplicacion_pago_nomina',
        'pago_nomina_evento',
        'pago_nomina_attachment',
      ]),
    );

    final sqlPagoNomina =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'pago_nomina'",
                )
                .single['sql']
            as String;
    expect(sqlPagoNomina, contains('"folio_pago_nomina" TEXT NOT NULL UNIQUE'));
    expect(
      sqlPagoNomina,
      contains('"egreso_id" TEXT NULL UNIQUE REFERENCES egreso (id)'),
    );
    expect(sqlPagoNomina, contains('CHECK (monto_total > 0)'));

    final sqlAplicacion =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'aplicacion_pago_nomina'",
                )
                .single['sql']
            as String;
    expect(
      sqlAplicacion,
      contains(
        '"nomina_empleado_id" TEXT NOT NULL REFERENCES nomina_empleado (id)',
      ),
    );
    expect(sqlAplicacion, contains('CHECK (monto > 0)'));
    expect(
      sqlAplicacion,
      contains('CHECK (saldo_despues = saldo_antes - monto)'),
    );
    expect(sqlAplicacion, contains('CHECK (saldo_despues >= 0)'));

    // Confirma la dirección deliberada de la FK: PagoNomina (tabla
    // nueva) referencia a Egreso (tabla ya existente desde 4K.1) —
    // Egreso mismo no gana ninguna columna nueva en esta etapa.
    final sqlEgreso =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'egreso'",
                )
                .single['sql']
            as String;
    expect(sqlEgreso, isNot(contains('pago_nomina')));

    schema.rawDatabase.dispose();
  });

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
      expect(
        nominas,
        hasLength(1),
        reason:
            'ninguna Nómina real debe perderse en una migración puramente aditiva',
      );
      expect(nominas.single.id, 'nomina-real');

      final pagos = await db.select(db.pagoNomina).get();
      expect(
        pagos,
        isEmpty,
        reason: 'PagoNomina es tabla nueva en 6D, sin backfill',
      );
      final aplicaciones = await db.select(db.aplicacionPagoNomina).get();
      expect(aplicaciones, isEmpty);
      final eventos = await db.select(db.pagoNominaEvento).get();
      expect(eventos, isEmpty);

      final codigoPagoNomina =
          await (db.select(db.codigoSecuencia)..where(
            (t) => t.entityType.equals('pago_nomina'),
          )).getSingleOrNull();
      expect(
        codigoPagoNomina,
        isNotNull,
        reason: 'runSeed debe sembrar el contador de folio de pago_nomina',
      );
      expect(codigoPagoNomina!.prefijo, 'PAGN');

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
    'CHECK de PagoNomina/AplicacionPagoNomina tras la migración: monto_total > 0, saldo nunca negativo, '
    'la aritmética del saldo debe cuadrar exactamente',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final nomina = await db
          .into(db.nomina)
          .insertReturning(
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
              aniosExperienciaSeguridad: 0,
            ),
          );
      final renglon = await db
          .into(db.nominaEmpleado)
          .insertReturning(
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
        db
            .into(db.pagoNomina)
            .insert(
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

      final pagoNomina = await db
          .into(db.pagoNomina)
          .insertReturning(
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
        db
            .into(db.aplicacionPagoNomina)
            .insert(baseAplicacion.copyWith(saldoDespues: const Value(1))),
        throwsA(anything),
        reason:
            'saldo_despues debe cuadrar exactamente con saldo_antes - monto',
      );
      await expectLater(
        db
            .into(db.aplicacionPagoNomina)
            .insert(
              baseAplicacion.copyWith(
                monto: const Value(800000),
                saldoAntes: const Value(750000),
                saldoDespues: const Value(-50000),
              ),
            ),
        throwsA(anything),
        reason:
            'saldo_despues nunca puede quedar negativo (nunca se sobrepaga un renglón)',
      );

      final aplicacion = await db
          .into(db.aplicacionPagoNomina)
          .insertReturning(baseAplicacion);
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo'",
                  )
                  .single['sql']
              as String;
      expect(sqlArticulo, contains('"folio" TEXT NOT NULL UNIQUE'));
      expect(
        sqlArticulo,
        contains('CHECK (costo_referencia IS NULL OR costo_referencia >= 0)'),
      );

      final sqlVariante =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo_variante'",
                  )
                  .single['sql']
              as String;
      expect(sqlVariante, contains('UNIQUE (articulo_id, valor)'));

      final sqlMovimiento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'movimiento_inventario'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlMovimiento,
        contains('CHECK (variante_id IS NULL OR unidad_id IS NULL)'),
      );
      expect(sqlMovimiento, contains('CHECK (cantidad > 0)'));
      expect(
        sqlMovimiento,
        contains('CHECK (unidad_id IS NULL OR cantidad = 1)'),
      );

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
      expect(
        nominas,
        hasLength(1),
        reason:
            'ninguna Nómina real debe perderse en una migración puramente aditiva',
      );

      final articulos = await db.select(db.articulo).get();
      expect(
        articulos,
        isEmpty,
        reason: 'Articulo es tabla nueva en 7A, sin backfill',
      );
      final movimientos = await db.select(db.movimientoInventario).get();
      expect(movimientos, isEmpty);

      final codigoArticulo =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('articulo'))).getSingleOrNull();
      expect(
        codigoArticulo,
        isNotNull,
        reason: 'runSeed debe sembrar el contador de folio de articulo',
      );
      expect(codigoArticulo!.prefijo, 'ART');

      final codigoUnidad =
          await (db.select(db.codigoSecuencia)..where(
            (t) => t.entityType.equals('articulo_unidad'),
          )).getSingleOrNull();
      expect(codigoUnidad, isNotNull);
      expect(codigoUnidad!.prefijo, 'UNI');

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
    'CHECK de Articulo/ArticuloVariante/MovimientoInventario tras la migración: costo >= 0, variante/unidad '
    'mutuamente excluyentes, cantidad siempre positiva',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Camisa'));

      await expectLater(
        db
            .into(db.articulo)
            .insert(
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

      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Camisa RISEG',
              manejaVariante: const Value(true),
            ),
          );
      final variante = await db
          .into(db.articuloVariante)
          .insertReturning(
            ArticuloVarianteCompanion.insert(
              articuloId: articulo.id,
              valor: 'M',
            ),
          );

      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: 'UNI-000001',
              articuloId: articulo.id,
              numeroSerie: 'SN-0001',
            ),
          );

      await expectLater(
        db
            .into(db.movimientoInventario)
            .insert(
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
        db
            .into(db.movimientoInventario)
            .insert(
              MovimientoInventarioCompanion.insert(
                articuloId: articulo.id,
                cantidad: 2,
                tipoMovimiento: 'entrada',
                fecha: DateTime(2026, 1, 1),
                unidadId: Value(unidad.id),
              ),
            ),
        throwsA(anything),
        reason:
            'un movimiento de unidad serializada siempre tiene cantidad = 1',
      );

      final movimiento = await db
          .into(db.movimientoInventario)
          .insertReturning(
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

      expect(
        tablas,
        containsAll([
          'asignacion',
          'descuento_inventario',
          'asignacion_attachment',
        ]),
      );

      final sqlAsignacion =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains(
          'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
          '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        ),
      );
      expect(
        sqlAsignacion,
        contains('CHECK (variante_id IS NULL OR unidad_id IS NULL)'),
      );
      expect(
        sqlAsignacion,
        contains('CHECK (unidad_id IS NULL OR cantidad = 1)'),
      );
      expect(
        sqlAsignacion,
        contains(
          "CHECK ((estatus = 'activa' AND fecha_cierre IS NULL) OR "
          "(estatus != 'activa' AND fecha_cierre IS NOT NULL))",
        ),
      );
      expect(
        sqlAsignacion,
        contains(
          "CHECK (atribuible_al_empleado IS NULL OR estatus = 'danada' OR estatus = 'perdida')",
        ),
      );

      final sqlDescuento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'descuento_inventario'",
                  )
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

  test('migración 27 → 28 conserva una Nómina real y crea las tablas de Asignaciones vacías, sin nuevas '
      'entradas de CodigoSecuencia', () async {
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
    expect(
      nominas,
      hasLength(1),
      reason:
          'ninguna Nómina real debe perderse en una migración puramente aditiva',
    );

    final asignaciones = await db.select(db.asignacion).get();
    expect(
      asignaciones,
      isEmpty,
      reason: 'Asignacion es tabla nueva en 7B, sin backfill',
    );
    final descuentos = await db.select(db.descuentoInventario).get();
    expect(descuentos, isEmpty);

    final codigosSecuencia = await db.select(db.codigoSecuencia).get();
    expect(
      codigosSecuencia,
      hasLength(30), // +1: folio TRF de transferencias (v91)
      reason:
          '7B no agrega ninguna entrada nueva de CodigoSecuencia (la migración corre hasta '
          '_currentSchemaVersion, así que sí incluye las de vehiculo/linea_telefonica/compra sembradas en 8A/9A/10, '
          'las 2 de descuentoProgramadoPrestamo/Botas sembradas en 57, la de entrega sembrada en 60, la de deuda '
          'sembrada en 61, la de cuenta_financiera sembrada en 63, la de tiempoExtra sembrada en 65 y la de servicioEventual sembrada en 87)',
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
  });

  test(
    'CHECK y protección de unidad serializada tras la migración: empleado/servicio mutuamente excluyentes, '
    'cierre consistente con fecha_cierre, atribución solo en danada/perdida, importe de descuento positivo, '
    'índice único rechaza una segunda asignación activa sobre la misma unidad',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Radios'));
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Radio Motorola',
              manejaSerie: const Value(true),
            ),
          );
      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: 'UNI-000001',
              articuloId: articulo.id,
              numeroSerie: 'SN-0001',
            ),
          );

      final tipoServicio = await db
          .into(db.tipoServicio)
          .insertReturning(
            TipoServicioCompanion.insert(
              id: 'tipo-servicio-real',
              codigo: 'VIGILANCIA_FIJA',
              nombre: 'Vigilancia fija',
            ),
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
              tipoServicioId: tipoServicio.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
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

      final baseAsignacion = AsignacionCompanion.insert(
        articuloId: articulo.id,
        cantidad: 1,
        unidadId: const Value('placeholder'),
        empleadoId: Value(empleado.id),
        fechaEntrega: DateTime(2026, 1, 1),
      );

      await expectLater(
        db
            .into(db.asignacion)
            .insert(
              baseAsignacion.copyWith(
                unidadId: Value(unidad.id),
                servicioId: Value(servicio.id),
              ),
            ),
        throwsA(anything),
        reason:
            'empleado_id y servicio_id nunca pueden venir poblados a la vez',
      );
      await expectLater(
        db
            .into(db.asignacion)
            .insert(
              baseAsignacion.copyWith(
                unidadId: Value(unidad.id),
                empleadoId: const Value(null),
              ),
            ),
        throwsA(anything),
        reason: 'exactamente uno de empleado_id/servicio_id debe venir poblado',
      );
      await expectLater(
        db
            .into(db.asignacion)
            .insert(
              baseAsignacion.copyWith(
                unidadId: Value(unidad.id),
                estatus: const Value('devuelta'),
              ),
            ),
        throwsA(anything),
        reason: 'estatus != activa exige fecha_cierre poblada',
      );
      await expectLater(
        db
            .into(db.asignacion)
            .insert(
              baseAsignacion.copyWith(
                unidadId: Value(unidad.id),
                atribuibleAlEmpleado: const Value(true),
              ),
            ),
        throwsA(anything),
        reason: 'atribuible_al_empleado solo tiene sentido en danada/perdida',
      );

      final asignacion = await db
          .into(db.asignacion)
          .insertReturning(baseAsignacion.copyWith(unidadId: Value(unidad.id)));
      expect(asignacion.estatus, 'activa');

      await expectLater(
        db
            .into(db.asignacion)
            .insert(
              AsignacionCompanion.insert(
                articuloId: articulo.id,
                cantidad: 1,
                unidadId: Value(unidad.id),
                empleadoId: Value(empleado.id),
                fechaEntrega: DateTime(2026, 1, 2),
              ),
            ),
        throwsA(anything),
        reason:
            'idx_asignacion_unidad_activa rechaza una segunda asignación activa sobre la misma unidad',
      );

      await expectLater(
        db
            .into(db.descuentoInventario)
            .insert(
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

      final descuento = await db
          .into(db.descuentoInventario)
          .insertReturning(
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_attachment'",
                  )
                  .single['sql']
              as String;
      expect(sqlAsignacionAttachment, contains('asignacion_id'));
      expect(
        sqlAsignacionAttachment,
        contains('PRIMARY KEY'),
        reason:
            'la llave primaria debe seguir declarada explícitamente (ahora compuesta)',
      );

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 28 → 29 conserva una Asignacion real y recrea AsignacionAttachment vacía',
    () async {
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
      expect(
        asignaciones,
        hasLength(1),
        reason:
            'ninguna Asignacion real debe perderse en una migración puramente estructural',
      );

      final asignacionAttachments =
          await db.select(db.asignacionAttachment).get();
      expect(
        asignacionAttachments,
        isEmpty,
        reason: 'AsignacionAttachment nunca tuvo filas — se recrea vacía',
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
    'llave primaria compuesta de AsignacionAttachment: un mismo Attachment puede unirse a varias Asignaciones, '
    'pero no repetir el mismo par',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Radios'));
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Radio Motorola',
            ),
          );
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
      final asignacion1 = await db
          .into(db.asignacion)
          .insertReturning(
            AsignacionCompanion.insert(
              articuloId: articulo.id,
              cantidad: 1,
              empleadoId: Value(empleado.id),
              fechaEntrega: DateTime(2026, 1, 1),
            ),
          );
      final asignacion2 = await db
          .into(db.asignacion)
          .insertReturning(
            AsignacionCompanion.insert(
              articuloId: articulo.id,
              cantidad: 1,
              empleadoId: Value(empleado.id),
              fechaEntrega: DateTime(2026, 1, 1),
            ),
          );

      final attachment = await db
          .into(db.attachment)
          .insertReturning(
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

      await db
          .into(db.asignacionAttachment)
          .insert(
            AsignacionAttachmentCompanion.insert(
              attachmentId: attachment.id,
              asignacionId: asignacion1.id,
            ),
          );
      await db
          .into(db.asignacionAttachment)
          .insert(
            AsignacionAttachmentCompanion.insert(
              attachmentId: attachment.id,
              asignacionId: asignacion2.id,
            ),
          );

      final filas = await db.select(db.asignacionAttachment).get();
      expect(
        filas,
        hasLength(2),
        reason:
            'un mismo Attachment sí debe poder unirse a más de una Asignación',
      );

      await expectLater(
        db
            .into(db.asignacionAttachment)
            .insert(
              AsignacionAttachmentCompanion.insert(
                attachmentId: attachment.id,
                asignacionId: asignacion1.id,
              ),
            ),
        throwsA(anything),
        reason:
            'el mismo par (attachment_id, asignacion_id) no puede repetirse',
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo'",
                  )
                  .single['sql']
              as String;
      expect(sqlVehiculo, contains('"codigo" TEXT NOT NULL UNIQUE'));
      expect(
        sqlVehiculo,
        contains('CHECK (costo_adquisicion IS NULL OR costo_adquisicion >= 0)'),
      );
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
      expect(
        asignaciones,
        hasLength(1),
        reason:
            'ninguna Asignacion real debe perderse en una migración puramente aditiva',
      );

      final vehiculos = await db.select(db.vehiculo).get();
      expect(
        vehiculos,
        isEmpty,
        reason: 'Vehiculo es tabla nueva en 8A, sin backfill',
      );
      final vehiculoAttachments = await db.select(db.vehiculoAttachment).get();
      expect(vehiculoAttachments, isEmpty);

      final codigoVehiculo =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('vehiculo'))).getSingleOrNull();
      expect(
        codigoVehiculo,
        isNotNull,
        reason: 'runSeed debe sembrar el contador de código de vehiculo',
      );
      expect(codigoVehiculo!.prefijo, 'VEH');

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
        db
            .into(db.vehiculo)
            .insert(baseVehiculo.copyWith(costoAdquisicion: const Value(-100))),
        throwsA(anything),
        reason: 'costo_adquisicion negativo debe rechazarse',
      );
      await expectLater(
        db
            .into(db.vehiculo)
            .insert(baseVehiculo.copyWith(estatus: const Value('baja'))),
        throwsA(anything),
        reason: 'estatus = baja exige fecha_baja poblada',
      );
      await expectLater(
        db
            .into(db.vehiculo)
            .insert(
              baseVehiculo.copyWith(fechaBaja: Value(DateTime(2026, 1, 1))),
            ),
        throwsA(anything),
        reason: 'fecha_baja poblada exige estatus = baja',
      );

      final vehiculo1 = await db
          .into(db.vehiculo)
          .insertReturning(
            baseVehiculo.copyWith(
              codigo: const Value('VEH-000001'),
              placas: const Value('ABC-123'),
              vin: const Value('VIN-0001'),
            ),
          );
      expect(vehiculo1.estatus, 'disponible');

      // Dos vehículos sin placas/VIN capturados deben coexistir sin problema.
      await db
          .into(db.vehiculo)
          .insertReturning(
            baseVehiculo.copyWith(codigo: const Value('VEH-000002')),
          );
      await db
          .into(db.vehiculo)
          .insertReturning(
            baseVehiculo.copyWith(codigo: const Value('VEH-000003')),
          );

      await expectLater(
        db
            .into(db.vehiculo)
            .insert(
              baseVehiculo.copyWith(
                codigo: const Value('VEH-000004'),
                placas: const Value('ABC-123'),
              ),
            ),
        throwsA(anything),
        reason: 'idx_vehiculo_placas_unica rechaza placas duplicadas',
      );
      await expectLater(
        db
            .into(db.vehiculo)
            .insert(
              baseVehiculo.copyWith(
                codigo: const Value('VEH-000005'),
                vin: const Value('VIN-0001'),
              ),
            ),
        throwsA(anything),
        reason: 'idx_vehiculo_vin_unico rechaza VIN duplicado',
      );

      await db.close();
    },
  );

  test('31.json coincide con el esquema final de la Etapa 8B (tablas nuevas AsignacionVehiculo, VehiculoKilometraje '
      '+ índice único parcial idx_asignacion_vehiculo_vigente)', () async {
    final schema = await verifier.schemaAt(31);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();

    expect(
      tablas,
      containsAll(['asignacion_vehiculo', 'vehiculo_kilometraje']),
    );

    final sqlAsignacion =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_vehiculo'",
                )
                .single['sql']
            as String;
    expect(
      sqlAsignacion,
      contains(
        'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
        '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
      ),
    );
    expect(
      sqlAsignacion,
      contains(
        'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
      ),
    );

    final sqlKilometraje =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo_kilometraje'",
                )
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
  });

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
      expect(
        vehiculos,
        hasLength(1),
        reason:
            'ningún Vehículo real debe perderse en una migración puramente aditiva',
      );

      final asignaciones = await db.select(db.asignacionVehiculo).get();
      expect(
        asignaciones,
        isEmpty,
        reason: 'AsignacionVehiculo es tabla nueva en 8B, sin backfill',
      );
      final lecturas = await db.select(db.vehiculoKilometraje).get();
      expect(lecturas, isEmpty);

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
    'CHECK de AsignacionVehiculo/VehiculoKilometraje tras la migración: empleado/servicio mutuamente '
    'excluyentes, fecha_termino >= fecha_inicio, kilometraje >= 0, índice único rechaza una segunda '
    'asignación vigente sobre el mismo Vehículo',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculo = await db
          .into(db.vehiculo)
          .insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-000001',
              marca: 'BMW',
              modelo: '320i',
              tipoVehiculo: 'sedan',
            ),
          );
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
      final tipoServicio = await db
          .into(db.tipoServicio)
          .insertReturning(
            TipoServicioCompanion.insert(
              id: 'tipo-servicio-real',
              codigo: 'VIGILANCIA_FIJA',
              nombre: 'Vigilancia fija',
            ),
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
        db
            .into(db.asignacionVehiculo)
            .insert(
              baseAsignacion.copyWith(
                empleadoId: Value(empleado.id),
                servicioId: Value(servicio.id),
              ),
            ),
        throwsA(anything),
        reason:
            'empleado_id y servicio_id nunca pueden venir poblados a la vez',
      );
      await expectLater(
        db
            .into(db.asignacionVehiculo)
            .insert(baseAsignacion.copyWith(empleadoId: const Value(null))),
        throwsA(anything),
        reason: 'exactamente uno de empleado_id/servicio_id debe venir poblado',
      );
      await expectLater(
        db
            .into(db.asignacionVehiculo)
            .insert(
              baseAsignacion.copyWith(
                empleadoId: Value(empleado.id),
                fechaTermino: Value(DateTime(2025, 12, 1)),
              ),
            ),
        throwsA(anything),
        reason: 'fecha_termino no puede ser anterior a fecha_inicio',
      );

      final asignacion = await db
          .into(db.asignacionVehiculo)
          .insertReturning(
            baseAsignacion.copyWith(empleadoId: Value(empleado.id)),
          );
      expect(asignacion.fechaTermino, isNull);

      await expectLater(
        db
            .into(db.asignacionVehiculo)
            .insert(
              AsignacionVehiculoCompanion.insert(
                vehiculoId: vehiculo.id,
                empleadoId: const Value(null),
                servicioId: Value(servicio.id),
                fechaInicio: DateTime(2026, 1, 2),
              ),
            ),
        throwsA(anything),
        reason:
            'idx_asignacion_vehiculo_vigente rechaza una segunda asignación vigente para el mismo Vehículo',
      );

      await expectLater(
        db
            .into(db.vehiculoKilometraje)
            .insert(
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

      final lectura = await db
          .into(db.vehiculoKilometraje)
          .insertReturning(
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

  test('32.json coincide con el esquema final de la Etapa 8C (tablas nuevas VehiculoDocumento, '
      'VehiculoDocumentoAttachment, sin índices propios)', () async {
    final schema = await verifier.schemaAt(32);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();

    expect(
      tablas,
      containsAll(['vehiculo_documento', 'vehiculo_documento_attachment']),
    );

    final sqlDocumento =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo_documento'",
                )
                .single['sql']
            as String;
    expect(
      sqlDocumento,
      contains(
        'CHECK (fecha_vencimiento IS NULL OR fecha_emision IS NULL OR fecha_vencimiento >= fecha_emision)',
      ),
    );

    schema.rawDatabase.dispose();
  });

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
      expect(
        vehiculos,
        hasLength(1),
        reason:
            'ningún Vehículo real debe perderse en una migración puramente aditiva',
      );

      final documentos = await db.select(db.vehiculoDocumento).get();
      expect(
        documentos,
        isEmpty,
        reason: 'VehiculoDocumento es tabla nueva en 8C, sin backfill',
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
    'CHECK de VehiculoDocumento tras la migración: fecha_vencimiento >= fecha_emision cuando ambas existen',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculo = await db
          .into(db.vehiculo)
          .insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-000001',
              marca: 'BMW',
              modelo: '320i',
              tipoVehiculo: 'sedan',
            ),
          );

      await expectLater(
        db
            .into(db.vehiculoDocumento)
            .insert(
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

      final documento = await db
          .into(db.vehiculoDocumento)
          .insertReturning(
            VehiculoDocumentoCompanion.insert(
              vehiculoId: vehiculo.id,
              tipo: 'facturaCartaFactura',
            ),
          );
      expect(
        documento.fechaVencimiento,
        isNull,
        reason: 'documentos sin vencimiento (ej. factura) son válidos',
      );

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

      expect(
        tablas,
        containsAll([
          'vehiculo_mantenimiento',
          'vehiculo_mantenimiento_attachment',
        ]),
      );

      final sqlMantenimiento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'vehiculo_mantenimiento'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlMantenimiento,
        contains('CHECK (kilometraje IS NULL OR kilometraje >= 0)'),
      );
      expect(sqlMantenimiento, contains('CHECK (costo IS NULL OR costo >= 0)'));
      expect(
        sqlMantenimiento,
        contains(
          'CHECK (proximo_mantenimiento_kilometraje IS NULL OR proximo_mantenimiento_kilometraje >= 0)',
        ),
      );
      expect(
        sqlMantenimiento,
        contains(
          'CHECK (proximo_mantenimiento_fecha IS NULL OR proximo_mantenimiento_fecha >= fecha)',
        ),
      );

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
      expect(
        vehiculos,
        hasLength(1),
        reason:
            'ningún Vehículo real debe perderse en una migración puramente aditiva',
      );

      final mantenimientos = await db.select(db.vehiculoMantenimiento).get();
      expect(
        mantenimientos,
        isEmpty,
        reason: 'VehiculoMantenimiento es tabla nueva en 8D, sin backfill',
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
    'CHECK de VehiculoMantenimiento tras la migración: kilometraje/costo/proximo_kilometraje >= 0, '
    'proximo_fecha >= fecha',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vehiculo = await db
          .into(db.vehiculo)
          .insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-000001',
              marca: 'BMW',
              modelo: '320i',
              tipoVehiculo: 'sedan',
            ),
          );
      final base = VehiculoMantenimientoCompanion.insert(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'preventivo',
        descripcion: 'Servicio',
      );

      await expectLater(
        db
            .into(db.vehiculoMantenimiento)
            .insert(base.copyWith(kilometraje: const Value(-1))),
        throwsA(anything),
        reason: 'kilometraje nunca puede ser negativo',
      );
      await expectLater(
        db
            .into(db.vehiculoMantenimiento)
            .insert(base.copyWith(costo: const Value(-1))),
        throwsA(anything),
        reason: 'costo nunca puede ser negativo',
      );
      await expectLater(
        db
            .into(db.vehiculoMantenimiento)
            .insert(
              base.copyWith(proximoMantenimientoKilometraje: const Value(-1)),
            ),
        throwsA(anything),
        reason: 'proximo_mantenimiento_kilometraje nunca puede ser negativo',
      );
      await expectLater(
        db
            .into(db.vehiculoMantenimiento)
            .insert(
              base.copyWith(
                proximoMantenimientoFecha: Value(DateTime(2026, 1, 5)),
              ),
            ),
        throwsA(anything),
        reason: 'proximo_mantenimiento_fecha no puede ser anterior a fecha',
      );

      final registro = await db
          .into(db.vehiculoMantenimiento)
          .insertReturning(
            base.copyWith(
              proximoMantenimientoFecha: Value(DateTime(2026, 4, 10)),
            ),
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

      expect(
        tablas,
        containsAll(['linea_telefonica', 'linea_telefonica_plan']),
      );

      final sqlLinea =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica'",
                  )
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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica_plan'",
                  )
                  .single['sql']
              as String;
      expect(sqlPlan, contains('CHECK (costo_mensual >= 0)'));
      expect(
        sqlPlan,
        contains(
          'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
        ),
      );
      expect(
        sqlPlan,
        contains(
          'CHECK (fecha_fin_permanencia IS NULL OR fecha_fin_permanencia >= fecha_inicio_vigencia)',
        ),
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
      expect(
        vehiculos,
        hasLength(1),
        reason:
            'ningún Vehículo real debe perderse en una migración puramente aditiva',
      );

      final lineas = await db.select(db.lineaTelefonica).get();
      expect(
        lineas,
        isEmpty,
        reason: 'LineaTelefonica es tabla nueva en 9A, sin backfill',
      );

      final codigoLinea =
          await (db.select(db.codigoSecuencia)..where(
            (t) => t.entityType.equals('linea_telefonica'),
          )).getSingleOrNull();
      expect(
        codigoLinea,
        isNotNull,
        reason:
            'runSeed debe sembrar el contador de código de linea_telefonica',
      );
      expect(codigoLinea!.prefijo, 'TEL');

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
    'CHECK de LineaTelefonica tras la migración: fecha_baja consistente con estatus, '
    'número único solo cuando se captura',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final baseLinea = LineaTelefonicaCompanion.insert(
        codigo: 'TEL-000001',
        operador: 'telcel',
        modalidadSim: 'fisica',
      );

      await expectLater(
        db
            .into(db.lineaTelefonica)
            .insert(baseLinea.copyWith(estatus: const Value('baja'))),
        throwsA(anything),
        reason: 'estatus = baja exige fecha_baja poblada',
      );
      await expectLater(
        db
            .into(db.lineaTelefonica)
            .insert(baseLinea.copyWith(fechaBaja: Value(DateTime(2026, 1, 1)))),
        throwsA(anything),
        reason: 'fecha_baja poblada exige estatus = baja',
      );

      await db
          .into(db.lineaTelefonica)
          .insertReturning(
            baseLinea.copyWith(numero: const Value('7221234567')),
          );

      // Dos líneas sin número capturado deben coexistir sin problema.
      await db
          .into(db.lineaTelefonica)
          .insertReturning(
            baseLinea.copyWith(codigo: const Value('TEL-000002')),
          );
      await db
          .into(db.lineaTelefonica)
          .insertReturning(
            baseLinea.copyWith(codigo: const Value('TEL-000003')),
          );

      await expectLater(
        db
            .into(db.lineaTelefonica)
            .insert(
              baseLinea.copyWith(
                codigo: const Value('TEL-000004'),
                numero: const Value('7221234567'),
              ),
            ),
        throwsA(anything),
        reason: 'idx_linea_telefonica_numero_unico rechaza número duplicado',
      );

      await db.close();
    },
  );

  test('35.json coincide con el esquema final de la Etapa 9B (tablas nuevas AsignacionLineaTelefonica, '
      'LineaTelefonicaEquipo + índice único parcial idx_asignacion_linea_telefonica_vigente) — '
      'asignaciones y equipo asociado de Telefonía', () async {
    final schema = await verifier.schemaAt(35);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();

    expect(
      tablas,
      containsAll(['asignacion_linea_telefonica', 'linea_telefonica_equipo']),
    );

    final sqlAsignacion =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion_linea_telefonica'",
                )
                .single['sql']
            as String;
    expect(
      sqlAsignacion,
      contains(
        'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
        '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
      ),
    );
    expect(
      sqlAsignacion,
      contains(
        'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
      ),
    );

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
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica_equipo'",
                )
                .single['sql']
            as String;
    expect(
      sqlEquipo,
      contains('CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)'),
    );

    schema.rawDatabase.dispose();
  });

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
      expect(
        lineas,
        hasLength(1),
        reason:
            'ninguna LineaTelefonica real debe perderse en una migración puramente aditiva',
      );
      expect(lineas.single.numero, '7221234567');

      final asignaciones = await db.select(db.asignacionLineaTelefonica).get();
      expect(
        asignaciones,
        isEmpty,
        reason: 'AsignacionLineaTelefonica es tabla nueva en 9B, sin backfill',
      );
      final equipos = await db.select(db.lineaTelefonicaEquipo).get();
      expect(
        equipos,
        isEmpty,
        reason: 'LineaTelefonicaEquipo es tabla nueva en 9B, sin backfill',
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
    'CHECK/índice único de AsignacionLineaTelefonica/LineaTelefonicaEquipo tras la migración: exactamente uno de '
    'empleado/servicio, fecha_termino/fecha_fin coherentes, una sola asignación vigente por línea',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final linea = await db
          .into(db.lineaTelefonica)
          .insertReturning(
            LineaTelefonicaCompanion.insert(
              codigo: 'TEL-000001',
              operador: 'telcel',
              modalidadSim: 'fisica',
            ),
          );
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
        db
            .into(db.asignacionLineaTelefonica)
            .insert(
              baseAsignacion.copyWith(
                empleadoId: Value(empleado.id),
                servicioId: Value('servicio-inexistente'),
              ),
            ),
        throwsA(anything),
        reason: 'empleado y servicio poblados a la vez debe rechazarse',
      );
      await expectLater(
        db
            .into(db.asignacionLineaTelefonica)
            .insert(
              baseAsignacion.copyWith(
                empleadoId: Value(empleado.id),
                fechaTermino: Value(DateTime(2026, 1, 1)),
              ),
            ),
        throwsA(anything),
        reason: 'fecha_termino anterior a fecha_inicio debe rechazarse',
      );

      final asignacion = await db
          .into(db.asignacionLineaTelefonica)
          .insertReturning(
            baseAsignacion.copyWith(empleadoId: Value(empleado.id)),
          );
      expect(asignacion.empleadoId, empleado.id);

      final empleado2 = await db
          .into(db.empleado)
          .insertReturning(
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
        db
            .into(db.asignacionLineaTelefonica)
            .insert(
              AsignacionLineaTelefonicaCompanion.insert(
                lineaTelefonicaId: linea.id,
                fechaInicio: DateTime(2026, 2, 1),
                empleadoId: const Value('otro-empleado-no-usado'),
              ).copyWith(empleadoId: Value(empleado2.id)),
            ),
        throwsA(anything),
        reason:
            'idx_asignacion_linea_telefonica_vigente rechaza una segunda asignación vigente para la misma línea',
      );

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Smartphone',
              manejaSerie: const Value(true),
            ),
          );
      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: 'UNI-000001',
              articuloId: articulo.id,
              numeroSerie: 'SN-0001',
            ),
          );

      final baseEquipo = LineaTelefonicaEquipoCompanion.insert(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
      );
      await expectLater(
        db
            .into(db.lineaTelefonicaEquipo)
            .insert(baseEquipo.copyWith(fechaFin: Value(DateTime(2026, 1, 1)))),
        throwsA(anything),
        reason: 'fecha_fin anterior a fecha_inicio debe rechazarse',
      );

      final equipo = await db
          .into(db.lineaTelefonicaEquipo)
          .insertReturning(baseEquipo);
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

      expect(
        tablas,
        containsAll([
          'recarga_linea_telefonica',
          'recarga_linea_telefonica_attachment',
        ]),
      );
      expect(
        tablas,
        isNot(contains('linea_telefonica_plan')),
        reason: 'retirada por completo en 9C — operación prepago, sin planes',
      );

      final sqlRecarga =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'recarga_linea_telefonica'",
                  )
                  .single['sql']
              as String;
      expect(sqlRecarga, contains('CHECK (importe > 0)'));

      schema.rawDatabase.dispose();
    },
  );

  test('migración 35 → 36 retira LineaTelefonicaPlan (incluso con filas reales) y crea las tablas de Recarga vacías, '
      'conservando la LineaTelefonica real', () async {
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
    expect(
      lineas,
      hasLength(1),
      reason:
          'ninguna LineaTelefonica real debe perderse al retirar LineaTelefonicaPlan',
    );
    expect(lineas.single.numero, '7221234567');

    final tablasRestantes =
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'linea_telefonica_plan'",
            )
            .get();
    expect(
      tablasRestantes,
      isEmpty,
      reason:
          'linea_telefonica_plan debe desaparecer por completo, con o sin filas reales',
    );

    final recargas = await db.select(db.recargaLineaTelefonica).get();
    expect(
      recargas,
      isEmpty,
      reason: 'RecargaLineaTelefonica es tabla nueva en 9C, sin backfill',
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
  });

  test(
    'CHECK de RecargaLineaTelefonica tras la migración: importe siempre > 0',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final linea = await db
          .into(db.lineaTelefonica)
          .insertReturning(
            LineaTelefonicaCompanion.insert(
              codigo: 'TEL-000001',
              operador: 'telcel',
              modalidadSim: 'fisica',
            ),
          );
      final baseRecarga = RecargaLineaTelefonicaCompanion.insert(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 8, 5),
        importe: 20000,
      );

      await expectLater(
        db
            .into(db.recargaLineaTelefonica)
            .insert(baseRecarga.copyWith(importe: const Value(0))),
        throwsA(anything),
        reason: 'importe = 0 debe rechazarse',
      );
      await expectLater(
        db
            .into(db.recargaLineaTelefonica)
            .insert(baseRecarga.copyWith(importe: const Value(-100))),
        throwsA(anything),
        reason: 'importe negativo debe rechazarse',
      );

      final recarga = await db
          .into(db.recargaLineaTelefonica)
          .insertReturning(baseRecarga);
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
        containsAll([
          'compra',
          'compra_partida',
          'compra_partida_movimiento',
          'compra_attachment',
          'compra_evento',
        ]),
      );

      final sqlCompra =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlCompra,
        contains(
          '"egreso_id" TEXT NULL UNIQUE REFERENCES egreso (id) ON DELETE RESTRICT',
        ),
      );

      final sqlPartida =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra_partida'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlPartida,
        contains("CHECK (destino <> 'gastoDirecto' OR articulo_id IS NULL)"),
      );
      expect(
        sqlPartida,
        contains("CHECK (destino <> 'inventario' OR articulo_id IS NOT NULL)"),
      );
      expect(sqlPartida, contains('CHECK (cantidad > 0)'));
      expect(sqlPartida, contains('CHECK (costo_unitario >= 0)'));

      final sqlPuente =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra_partida_movimiento'",
                  )
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
      expect(
        vehiculos,
        hasLength(1),
        reason:
            'ningún Vehículo real debe perderse en una migración puramente aditiva',
      );

      final compras = await db.select(db.compra).get();
      expect(
        compras,
        isEmpty,
        reason: 'Compra es tabla nueva en la Etapa 10, sin backfill',
      );
      final partidas = await db.select(db.compraPartida).get();
      expect(partidas, isEmpty);

      final codigoCompra =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('compra'))).getSingleOrNull();
      expect(
        codigoCompra,
        isNotNull,
        reason: 'runSeed debe sembrar el contador de código de compra',
      );
      expect(codigoCompra!.prefijo, 'COM');

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
    'CHECK de CompraPartida tras la migración: destino/artículo coherentes, cantidad y costo válidos',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Uniformes'),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Camisola CH',
            ),
          );
      final egreso = await db
          .into(db.egreso)
          .insertReturning(
            EgresoCompanion.insert(
              folioEgreso: 'EGR-000001',
              monto: 180000,
              fecha: DateTime(2026, 8, 10),
              formaPago: 'tarjeta',
              concepto: 'Compra COM-000001',
            ),
          );
      final compra = await db
          .into(db.compra)
          .insertReturning(
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
        db
            .into(db.compraPartida)
            .insert(basePartida.copyWith(destino: const Value('gastoDirecto'))),
        throwsA(anything),
        reason: 'destino gastoDirecto con articulo_id poblado debe rechazarse',
      );
      await expectLater(
        db
            .into(db.compraPartida)
            .insert(
              basePartida.copyWith(
                articuloId: const Value.absent(),
                destino: const Value('inventario'),
              ),
            ),
        throwsA(anything),
        reason: 'destino inventario sin articulo_id debe rechazarse',
      );
      await expectLater(
        db
            .into(db.compraPartida)
            .insert(basePartida.copyWith(cantidad: const Value(0))),
        throwsA(anything),
        reason: 'cantidad = 0 debe rechazarse',
      );
      await expectLater(
        db
            .into(db.compraPartida)
            .insert(basePartida.copyWith(costoUnitario: const Value(-1))),
        throwsA(anything),
        reason: 'costo_unitario negativo debe rechazarse',
      );

      final partida = await db
          .into(db.compraPartida)
          .insertReturning(basePartida);
      expect(partida.cantidad, 10);

      await expectLater(
        db
            .into(db.compra)
            .insert(
              CompraCompanion.insert(
                folioCompra: 'COM-000002',
                fecha: DateTime(2026, 8, 11),
                formaPago: 'efectivo',
                egresoId: Value(egreso.id),
              ),
            ),
        throwsA(anything),
        reason:
            'egreso_id debe ser único — un Egreso no puede pertenecer a dos Compras',
      );

      await db.close();
    },
  );

  test('38.json coincide con el esquema final de la Etapa 11A (tablas nuevas Usuario, UsuarioEvento) — '
      'funda el dominio Usuarios', () async {
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
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'usuario'",
                )
                .single['sql']
            as String;
    expect(sqlUsuario, contains('"nombre_usuario" TEXT NOT NULL UNIQUE'));
    expect(sqlUsuario, contains('"password_hash" TEXT NOT NULL'));
    expect(
      sqlUsuario,
      contains(
        '"puesto_id" TEXT NULL REFERENCES puesto (id) ON DELETE RESTRICT',
      ),
    );
    expect(
      sqlUsuario,
      contains(
        '"es_maestro" INTEGER NOT NULL DEFAULT 0 CHECK ("es_maestro" IN (0, 1))',
      ),
    );

    final sqlEvento =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'usuario_evento'",
                )
                .single['sql']
            as String;
    expect(
      sqlEvento,
      contains(
        '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
      ),
    );

    schema.rawDatabase.dispose();
  });

  test('migración 37 → 38 conserva una Compra real y crea las tablas de Usuarios vacías, sin backfill ni '
      'siembra de CodigoSecuencia (Usuario no tiene folio)', () async {
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
    expect(
      compras,
      hasLength(1),
      reason:
          'ninguna Compra real debe perderse en una migración puramente aditiva',
    );

    final usuarios = await db.select(db.usuario).get();
    expect(
      usuarios,
      isEmpty,
      reason: 'Usuario es tabla nueva en la Etapa 11A, sin backfill',
    );
    final eventos = await db.select(db.usuarioEvento).get();
    expect(eventos, isEmpty);

    final codigoUsuario =
        await (db.select(db.codigoSecuencia)
          ..where((t) => t.entityType.equals('usuario'))).getSingleOrNull();
    expect(
      codigoUsuario,
      isNull,
      reason:
          'Usuario no tiene folio — nunca se siembra un CodigoSecuencia para él',
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
  });

  test('UNIQUE de Usuario.nombreUsuario tras la migración', () async {
    final schemaV1 = await verifier.schemaAt(1);
    final db = AppDatabase(schemaV1.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    await db
        .into(db.usuario)
        .insert(
          UsuarioCompanion.insert(
            nombre: 'Ana',
            nombreUsuario: 'ana',
            passwordHash: 'pbkdf2\$1\$AA==\$BB==',
          ),
        );

    await expectLater(
      db
          .into(db.usuario)
          .insert(
            UsuarioCompanion.insert(
              nombre: 'Otra Ana',
              nombreUsuario: 'ana',
              passwordHash: 'pbkdf2\$1\$CC==\$DD==',
            ),
          ),
      throwsA(anything),
      reason: 'nombre_usuario debe ser único',
    );

    await db.close();
  });

  test('39.json coincide con el esquema final de la Etapa 11B (tabla nueva PermisoUsuario) — '
      'permisos dinámicos por Usuario', () async {
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
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'permiso_usuario'",
                )
                .single['sql']
            as String;
    expect(sqlPermisoUsuario, contains('PRIMARY KEY ("usuario_id", "codigo")'));

    schema.rawDatabase.dispose();
  });

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
      expect(
        usuarios,
        hasLength(1),
        reason:
            'ningún Usuario real debe perderse en una migración puramente aditiva',
      );

      final permisos = await db.select(db.permisoUsuario).get();
      expect(
        permisos,
        isEmpty,
        reason: 'PermisoUsuario es tabla nueva en la Etapa 11B, sin backfill',
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
    'PermisoUsuario: llave primaria compuesta permite el mismo código en usuarios distintos '
    'pero rechaza repetir el mismo par',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final u1 = await db
          .into(db.usuario)
          .insertReturning(
            UsuarioCompanion.insert(
              nombre: 'Ana',
              nombreUsuario: 'ana',
              passwordHash: 'pbkdf2\$1\$AA==\$BB==',
            ),
          );
      final u2 = await db
          .into(db.usuario)
          .insertReturning(
            UsuarioCompanion.insert(
              nombre: 'Beto',
              nombreUsuario: 'beto',
              passwordHash: 'pbkdf2\$1\$CC==\$DD==',
            ),
          );

      await db
          .into(db.permisoUsuario)
          .insert(
            PermisoUsuarioCompanion.insert(
              usuarioId: u1.id,
              codigo: 'personal.ver',
            ),
          );
      // Mismo código, usuario distinto — permitido.
      await db
          .into(db.permisoUsuario)
          .insert(
            PermisoUsuarioCompanion.insert(
              usuarioId: u2.id,
              codigo: 'personal.ver',
            ),
          );

      await expectLater(
        db
            .into(db.permisoUsuario)
            .insert(
              PermisoUsuarioCompanion.insert(
                usuarioId: u1.id,
                codigo: 'personal.ver',
              ),
            ),
        throwsA(anything),
        reason: 'el mismo par (usuario, código) no puede repetirse',
      );

      await db.close();
    },
  );

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
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'eliminacion_fisica_evento'",
                  )
                  .single['sql']
              as String;
      expect(sqlEliminacion, contains('"tipo_entidad" TEXT NOT NULL'));
      expect(sqlEliminacion, contains('"entidad_id_original" TEXT NOT NULL'));
      expect(
        sqlEliminacion,
        contains(
          '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
        ),
      );
      expect(sqlEliminacion, contains('"motivo" TEXT NOT NULL'));
      expect(sqlEliminacion, contains('"snapshot_json" TEXT NOT NULL'));

      // Muestra representativa de las 15 tablas — no las 15, mismo
      // criterio que el resto de la suite de migraciones.
      for (final tabla in [
        'compra_evento',
        'movimiento_inventario',
        'recarga_linea_telefonica',
        'vehiculo_documento',
      ]) {
        final sql =
            schema.rawDatabase.select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                  [tabla],
                ).single['sql']
                as String;
        expect(
          sql,
          contains(
            '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
          ),
          reason: '$tabla debe tener actor_usuario_id tras la migración a 40',
        );
      }

      // La columna legacy `actor` permanece físicamente en las 12 tablas
      // donde ya existía — decisión explícita de Marlon (migración
      // aditiva, sin dropColumn).
      final sqlCompraEvento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'compra_evento'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlCompraEvento,
        contains('"actor" TEXT NULL'),
        reason: 'la columna legacy actor debe seguir existiendo físicamente',
      );

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
      expect(
        compras,
        hasLength(1),
        reason:
            'ninguna Compra real debe perderse en una migración puramente aditiva',
      );

      final eventos = await db.select(db.compraEvento).get();
      expect(eventos, hasLength(1));
      expect(
        eventos.single.actorUsuarioId,
        isNull,
        reason: 'histórico anterior a 11D queda con actorUsuarioId = null',
      );

      final eliminaciones = await db.select(db.eliminacionFisicaEvento).get();
      expect(
        eliminaciones,
        isEmpty,
        reason:
            'EliminacionFisicaEvento es tabla nueva en la Etapa 11D, sin backfill',
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
    'EliminacionFisicaEvento: actor_usuario_id sobrevive con SET NULL si el Usuario se elimina',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final usuario = await db
          .into(db.usuario)
          .insertReturning(
            UsuarioCompanion.insert(
              nombre: 'Ana',
              nombreUsuario: 'ana',
              passwordHash: 'pbkdf2\$1\$AA==\$BB==',
              esMaestro: const Value(true),
            ),
          );

      await db
          .into(db.eliminacionFisicaEvento)
          .insert(
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
      expect(
        eventos,
        hasLength(1),
        reason:
            'el evento sobrevive aunque el Usuario que lo generó se elimine',
      );
      expect(eventos.single.actorUsuarioId, isNull);

      await db.close();
    },
  );

  test('41.json coincide con el esquema final de la Etapa 9D (imei2 + actor_usuario_id en '
      'ArticuloUnidadTelefono/AsignacionLineaTelefonica/LineaTelefonicaEquipo + '
      'EquipoTelefonicoCredencial/EquipoTelefonicoEvento) — expediente del teléfono físico', () async {
    final schema = await verifier.schemaAt(41);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();

    expect(
      tablas,
      containsAll(['equipo_telefonico_credencial', 'equipo_telefonico_evento']),
    );

    final sqlCredencial =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'equipo_telefonico_credencial'",
                )
                .single['sql']
            as String;
    expect(
      sqlCredencial,
      contains(
        '"unidad_id" TEXT NOT NULL REFERENCES articulo_unidad (id) ON DELETE CASCADE',
      ),
    );
    expect(sqlCredencial, contains('PRIMARY KEY ("unidad_id")'));
    expect(sqlCredencial, contains('"correo" TEXT'));
    expect(sqlCredencial, contains('"contrasena_cifrada" TEXT'));
    expect(sqlCredencial, contains('"fecha_actualizacion_contrasena" INTEGER'));

    final sqlEvento =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'equipo_telefonico_evento'",
                )
                .single['sql']
            as String;
    expect(
      sqlEvento,
      contains(
        '"unidad_id" TEXT NOT NULL REFERENCES articulo_unidad (id) ON DELETE RESTRICT',
      ),
    );
    expect(
      sqlEvento,
      contains(
        '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
      ),
    );
    expect(sqlEvento, contains('"tipo_evento" TEXT NOT NULL'));

    final sqlTelefono =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo_unidad_telefono'",
                )
                .single['sql']
            as String;
    expect(sqlTelefono, contains('"imei2" TEXT'));

    for (final tabla in [
      'asignacion_linea_telefonica',
      'linea_telefonica_equipo',
    ]) {
      final sql =
          schema.rawDatabase.select(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                [tabla],
              ).single['sql']
              as String;
      expect(
        sql,
        contains(
          '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
        ),
        reason: '$tabla debe tener actor_usuario_id tras la migración a 41',
      );
    }

    schema.rawDatabase.dispose();
  });

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
      expect(
        unidades,
        hasLength(1),
        reason:
            'ninguna ArticuloUnidad real debe perderse en una migración puramente aditiva',
      );

      final telefonos = await db.select(db.articuloUnidadTelefono).get();
      expect(telefonos, hasLength(1));
      expect(
        telefonos.single.imei2,
        isNull,
        reason: 'imei2 es nuevo — no hay dato histórico que llenarlo',
      );
      expect(
        telefonos.single.imei,
        '123456789012345',
        reason: 'el IMEI 1 existente se conserva intacto',
      );

      final asignacionesLinea =
          await db.select(db.asignacionLineaTelefonica).get();
      expect(asignacionesLinea, hasLength(1));
      expect(
        asignacionesLinea.single.empleadoId,
        'empleado-real',
        reason: 'la asignación real no debe perderse',
      );
      expect(
        asignacionesLinea.single.actorUsuarioId,
        isNull,
        reason: 'histórico anterior a 9D queda con actorUsuarioId = null',
      );

      final credenciales = await db.select(db.equipoTelefonicoCredencial).get();
      expect(
        credenciales,
        isEmpty,
        reason:
            'EquipoTelefonicoCredencial es tabla nueva en la Etapa 9D, sin backfill',
      );

      final eventos = await db.select(db.equipoTelefonicoEvento).get();
      expect(
        eventos,
        isEmpty,
        reason:
            'EquipoTelefonicoEvento es tabla nueva en la Etapa 9D, sin backfill',
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
    'EquipoTelefonicoCredencial se elimina en cascada si su ArticuloUnidad se elimina',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Teléfono',
              manejaSerie: const Value(true),
            ),
          );
      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: 'UNI-000001',
              articuloId: articulo.id,
              numeroSerie: 'SN-001',
            ),
          );
      await db
          .into(db.equipoTelefonicoCredencial)
          .insert(
            EquipoTelefonicoCredencialCompanion.insert(
              unidadId: unidad.id,
              correo: const Value('equipo@riseg.mx'),
            ),
          );

      await db.delete(db.articuloUnidad).delete(unidad);

      final credenciales = await db.select(db.equipoTelefonicoCredencial).get();
      expect(
        credenciales,
        isEmpty,
        reason:
            'ON DELETE CASCADE — la credencial no debe sobrevivir sin su unidad',
      );

      await db.close();
    },
  );

  test(
    'EquipoTelefonicoEvento: actor_usuario_id sobrevive con SET NULL si el Usuario se elimina',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Teléfono',
              manejaSerie: const Value(true),
            ),
          );
      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: 'UNI-000001',
              articuloId: articulo.id,
              numeroSerie: 'SN-001',
            ),
          );
      final usuario = await db
          .into(db.usuario)
          .insertReturning(
            UsuarioCompanion.insert(
              nombre: 'Ana',
              nombreUsuario: 'ana',
              passwordHash: 'pbkdf2\$1\$AA==\$BB==',
            ),
          );

      await db
          .into(db.equipoTelefonicoEvento)
          .insert(
            EquipoTelefonicoEventoCompanion.insert(
              unidadId: unidad.id,
              fechaHora: DateTime(2026, 1, 1),
              tipoEvento: 'equipoConfigurado',
              actorUsuarioId: Value(usuario.id),
            ),
          );

      await db.delete(db.usuario).delete(usuario);

      final eventos = await db.select(db.equipoTelefonicoEvento).get();
      expect(
        eventos,
        hasLength(1),
        reason:
            'el evento sobrevive aunque el Usuario que lo generó se elimine',
      );
      expect(eventos.single.actorUsuarioId, isNull);

      await db.close();
    },
  );

  test(
    '42.json coincide con el esquema final de la Etapa 9D (ajuste posterior: actor_usuario_id en '
    'Asignacion) — "cambiar responsable" del mismo bien, sin MovimientoInventario ni cambio de estatus',
    () async {
      final schema = await verifier.schemaAt(42);
      final sqlAsignacion =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'asignacion'",
                  )
                  .single['sql']
              as String;
      expect(
        sqlAsignacion,
        contains(
          '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
        ),
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
      expect(
        asignaciones,
        hasLength(1),
        reason:
            'ninguna Asignacion real debe perderse en una migración puramente aditiva',
      );
      final asignacion = asignaciones.single;
      expect(asignacion.empleadoId, 'empleado-real');
      expect(asignacion.cantidad, 3);
      expect(asignacion.estatus, 'activa');
      expect(
        asignacion.actorUsuarioId,
        isNull,
        reason:
            'histórico anterior a este ajuste queda con actorUsuarioId = null',
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
    'cambiar responsable de una Asignacion real tras la migración: misma unidad, sin MovimientoInventario '
    'nuevo, estatus reasignada en la fila vieja',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              categoriaId: categoria.id,
              nombre: 'Teléfono',
              manejaSerie: const Value(true),
            ),
          );
      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(
              codigo: 'UNI-000001',
              articuloId: articulo.id,
              numeroSerie: 'SN-001',
            ),
          );
      final empleadoA = await db
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
      final empleadoB = await db
          .into(db.empleado)
          .insertReturning(
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
      expect(
        movimientosDespues.length,
        movimientosAntes.length,
        reason: 'sin MovimientoInventario nuevo',
      );

      final unidadTrasCambio = await db.select(db.articuloUnidad).getSingle();
      expect(
        unidadTrasCambio.estatus,
        'asignado',
        reason: 'nunca pasa por disponible',
      );

      await db.close();
    },
  );

  test('43.json coincide con el esquema final de la Etapa 9D (segundo ajuste posterior: '
      'aplicacion_especializada en CategoriaArticulo)', () async {
    final schema = await verifier.schemaAt(43);
    final sqlCategoria =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'categoria_articulo'",
                )
                .single['sql']
            as String;
    expect(
      sqlCategoria,
      contains('"aplicacion_especializada" TEXT NULL'),
      reason:
          'CategoriaArticulo debe tener aplicacion_especializada tras la migración a 43',
    );

    schema.rawDatabase.dispose();
  });

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
      expect(
        categorias,
        hasLength(1),
        reason:
            'ninguna CategoriaArticulo real debe perderse en una migración puramente aditiva',
      );
      final categoria = categorias.single;
      expect(categoria.nombre, 'Uniformes');
      expect(
        categoria.aplicacionEspecializada,
        isNull,
        reason: 'histórico anterior a este ajuste queda genérico (null)',
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
    'regularización de un Articulo mal configurado tras la migración: convierte cantidad en '
    'unidades, re-liga CompraPartidaMovimiento, no cambia existencia total',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(
              nombre: 'Teléfonos',
              aplicacionEspecializada: const Value('telefonia'),
            ),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000002',
              categoriaId: categoria.id,
              nombre: 'SMARTPHONE',
            ),
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
      final unidades =
          (resultado as RegularizarArticuloSerializadoExitoso).unidades;
      expect(unidades, hasLength(2));

      final articuloActualizado = await articuloRepo.obtenerPorId(articulo.id);
      expect(articuloActualizado!.manejaSerie, isTrue);

      final movimientos = await db.select(db.movimientoInventario).get();
      expect(
        movimientos,
        hasLength(2),
        reason:
            'el movimiento original por cantidad se borra, quedan 2 nuevos de unidad',
      );
      expect(
        movimientos.every((m) => m.unidadId != null && m.cantidad == 1),
        isTrue,
      );

      final existencia = await inventarioRepo.calcularExistenciaUnidades(
        articulo.id,
      );
      expect(
        existencia.total,
        2,
        reason: 'la existencia total no cambia con la regularización',
      );

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      await db.close();
    },
  );

  test('44.json coincide con el esquema final de la Etapa 9D (tercer ajuste posterior: tabla nueva '
      'ArticuloUnidadEvento) — corrección de identidad de unidad', () async {
    final schema = await verifier.schemaAt(44);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();
    expect(tablas, contains('articulo_unidad_evento'));

    final sqlEvento =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'articulo_unidad_evento'",
                )
                .single['sql']
            as String;
    expect(
      sqlEvento,
      contains('"unidad_id" TEXT NOT NULL REFERENCES articulo_unidad (id)'),
    );
    expect(
      sqlEvento,
      contains(
        '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
      ),
    );
    expect(sqlEvento, contains('"tipo_evento" TEXT NOT NULL'));
    expect(sqlEvento, contains('"campo" TEXT NOT NULL'));
    expect(sqlEvento, contains('"valor_anterior" TEXT'));
    expect(sqlEvento, contains('"valor_nuevo" TEXT'));
    expect(sqlEvento, contains('"motivo" TEXT NOT NULL'));

    schema.rawDatabase.dispose();
  });

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
      expect(
        unidades,
        hasLength(1),
        reason:
            'ninguna ArticuloUnidad real debe perderse en una migración puramente aditiva',
      );
      expect(unidades.single.numeroSerie, 'SN-REAL-001');
      expect(unidades.single.id, 'unidad-real');
      expect(unidades.single.codigo, 'UNI-000001');

      final eventos = await db.select(db.articuloUnidadEvento).get();
      expect(eventos, isEmpty, reason: 'tabla nueva, sin backfill');

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

  test('45.json coincide con el esquema de la Bóveda de Accesos del Maestro (Etapa 14D: tablas nuevas '
      'BovedaCredencial/BovedaCredencialEvento)', () async {
    final schema = await verifier.schemaAt(45);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();
    expect(
      tablas,
      containsAll(['boveda_credencial', 'boveda_credencial_evento']),
    );

    final sqlCredencial =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'boveda_credencial'",
                )
                .single['sql']
            as String;
    expect(sqlCredencial, contains('"nombre" TEXT NOT NULL'));
    expect(sqlCredencial, contains('"tipo" TEXT NOT NULL'));
    expect(sqlCredencial, contains('"secreto_cifrado" TEXT'));
    expect(sqlCredencial, contains('"ciclo_vida_registro" TEXT NOT NULL'));

    final sqlEvento =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'boveda_credencial_evento'",
                )
                .single['sql']
            as String;
    expect(
      sqlEvento,
      contains(
        '"credencial_id" TEXT NOT NULL REFERENCES boveda_credencial (id) ON DELETE RESTRICT',
      ),
    );
    expect(
      sqlEvento,
      contains(
        '"actor_usuario_id" TEXT NULL REFERENCES usuario (id) ON DELETE SET NULL',
      ),
    );
    expect(sqlEvento, contains('"tipo_evento" TEXT NOT NULL'));

    schema.rawDatabase.dispose();
  });

  test(
    'migración 44 → 45 conserva datos existentes y crea las tablas de la Bóveda vacías',
    () async {
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
      expect(
        usuarios,
        hasLength(1),
        reason:
            'ningún Usuario real debe perderse en una migración puramente aditiva',
      );
      expect(usuarios.single.id, 'usuario-real');

      final credenciales = await db.select(db.bovedaCredencial).get();
      expect(credenciales, isEmpty, reason: 'tabla nueva, sin backfill');
      final eventos = await db.select(db.bovedaCredencialEvento).get();
      expect(eventos, isEmpty, reason: 'tabla nueva, sin backfill');

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

  test('46.json coincide con el esquema de "Recuérdame en este equipo" (Etapa 15: tabla nueva '
      'SesionPersistente)', () async {
    final schema = await verifier.schemaAt(46);
    final tablas =
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((row) => row['name'] as String)
            .toSet();
    expect(tablas, contains('sesion_persistente'));

    final sql =
        schema.rawDatabase
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sesion_persistente'",
                )
                .single['sql']
            as String;
    expect(
      sql,
      contains(
        '"usuario_id" TEXT NOT NULL REFERENCES usuario (id) ON DELETE CASCADE',
      ),
    );
    expect(sql, contains('"token_hash" TEXT NOT NULL UNIQUE'));
    expect(sql, contains('"created_at" INTEGER NOT NULL'));

    schema.rawDatabase.dispose();
  });

  test(
    'migración 45 → 46 conserva datos existentes y crea SesionPersistente vacía',
    () async {
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
      expect(
        usuarios,
        hasLength(1),
        reason:
            'ningún Usuario real debe perderse en una migración puramente aditiva',
      );

      final sesiones = await db.select(db.sesionPersistente).get();
      expect(sesiones, isEmpty, reason: 'tabla nueva, sin backfill');

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
    '47.json elimina serieFiscal/folioFiscal de DocumentoPorEmitir y CuentaPorCobrar (Etapa 15, '
    'corrección estructural CFDI real: uuid único, sin certificado CSD)',
    () async {
      final schema = await verifier.schemaAt(47);

      final sqlDocumento =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'documento_por_emitir'",
                  )
                  .single['sql']
              as String;
      expect(sqlDocumento, isNot(contains('serie_fiscal')));
      expect(sqlDocumento, isNot(contains('folio_fiscal')));
      expect(sqlDocumento, contains('"uuid" TEXT'));
      expect(sqlDocumento, contains('"folio_documento" TEXT'));

      final sqlCuenta =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'cuenta_por_cobrar'",
                  )
                  .single['sql']
              as String;
      expect(sqlCuenta, isNot(contains('serie_fiscal')));
      expect(sqlCuenta, isNot(contains('folio_fiscal')));
      expect(sqlCuenta, contains('"uuid" TEXT'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 46 → 47 fusiona folioFiscal en uuid con COALESCE (caso real MILUYOLE) y descarta '
    'serieFiscal sin perder ningún dato de negocio',
    () async {
      final schemaV46 = await verifier.schemaAt(46);
      final raw = schemaV46.rawDatabase;

      raw.execute('''
        INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
        VALUES ('cliente-miluyole', 'CLI-000099', 'MILUYOLE', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
      ''');
      // Caso real reportado por Marlon: `serieFiscal` fue capturado por
      // error con el número de serie del CSD (nunca un dato real de
      // "serie fiscal"), y el UUID del CFDI real se había capturado en
      // `folioFiscal`, dejando `uuid` vacío — exactamente el escenario
      // que `COALESCE(uuid, folio_fiscal)` debe resolver sin pérdida.
      raw.execute('''
        INSERT INTO documento_por_emitir (
          id, codigo, cliente_id, tipo_documento, agrupacion, metodo, requiere_complemento,
          periodo_inicio, periodo_fin, generation_key, importe_base_esperado, importe_final_esperado,
          estatus, folio_documento, serie_fiscal, folio_fiscal, uuid, fecha_emision_real, importe_emitido,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'documento-miluyole', 'DOC-000099', 'cliente-miluyole', 'cfdi', 'porServicio', 'PUE', 0,
          1700000000, 1701000000, 'clave-miluyole-v47', 2180000, 2180000,
          'procesadoAceptado', 'F-1523', '00001000000709181459', 'FE6FC43F-B308-4F0B-B610-A079E69A64BC', NULL,
          1700500000, 2180000,
          1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO cuenta_por_cobrar (
          id, documento_por_emitir_id, cliente_id, tipo_documento, metodo, requiere_complemento,
          folio_documento, serie_fiscal, folio_fiscal, uuid, fecha_emision_real, importe_emitido,
          saldo_original, saldo_pendiente, moneda, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'cxc-miluyole', 'documento-miluyole', 'cliente-miluyole', 'cfdi', 'PUE', 0,
          'F-1523', '00001000000709181459', 'FE6FC43F-B308-4F0B-B610-A079E69A64BC', NULL, 1700500000, 2180000,
          2180000, 2180000, 'MXN', 'pendiente',
          1700000000, 1700000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV46.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final documento =
          await (db.select(db.documentoPorEmitir)
            ..where((t) => t.id.equals('documento-miluyole'))).getSingle();
      expect(
        documento.uuid,
        'FE6FC43F-B308-4F0B-B610-A079E69A64BC',
        reason:
            'uuid estaba vacío; debe heredar el valor de folioFiscal vía COALESCE',
      );
      expect(
        documento.folioDocumento,
        'F-1523',
        reason: 'folioDocumento no se toca',
      );

      final cuenta =
          await (db.select(db.cuentaPorCobrar)
            ..where((t) => t.id.equals('cxc-miluyole'))).getSingle();
      expect(cuenta.uuid, 'FE6FC43F-B308-4F0B-B610-A079E69A64BC');

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
    'corregir identidad de una ArticuloUnidad real tras la migración: número de serie y marca '
    'cambian, mismo id/código, evento de auditoría con valor anterior y nuevo',
    () async {
      final schemaV1 = await verifier.schemaAt(1);
      final db = AppDatabase(schemaV1.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      await db
          .into(db.usuario)
          .insert(
            UsuarioCompanion.insert(
              id: const Value('usuario-actor'),
              nombre: 'Usuario de prueba',
              nombreUsuario: 'usuario-prueba',
              passwordHash: 'x',
            ),
          );

      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'),
          );
      final articulo = await db
          .into(db.articulo)
          .insertReturning(
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
      expect(
        eventos,
        hasLength(2),
        reason: 'un evento por campo que cambió (numeroSerie y marca)',
      );
      final eventoSerie = eventos.firstWhere((e) => e.campo == 'numeroSerie');
      expect(eventoSerie.valorAnterior, 'SN-MAL-CAPTURADA');
      expect(eventoSerie.valorNuevo, 'SN-CORRECTA-001');
      expect(eventoSerie.actorUsuarioId, 'usuario-actor');
      expect(eventoSerie.motivo, 'Error de captura al dar de alta.');

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      await db.close();
    },
  );

  test(
    '48.json agrega Empleado.bancoOtroDescripcion (Etapa 15: nombre del banco cuando bancoId apunta a la '
    'fila catálogo "OTRO")',
    () async {
      final schema = await verifier.schemaAt(48);

      final sqlEmpleado =
          schema.rawDatabase
                  .select(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'empleado'",
                  )
                  .single['sql']
              as String;
      expect(sqlEmpleado, contains('"banco_otro_descripcion" TEXT'));

      schema.rawDatabase.dispose();
    },
  );

  test(
    'migración 47 → 48 conserva datos existentes y agrega bancoOtroDescripcion nulo por defecto',
    () async {
      final schemaV47 = await verifier.schemaAt(47);
      final raw = schemaV47.rawDatabase;

      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, nacionalidad, fecha_ingreso, estatus, anios_experiencia_seguridad,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real-existente', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 'Mexicana', 1700000000, 'activo', 3,
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV47.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado =
          await (db.select(db.empleado)
            ..where((t) => t.id.equals('empleado-real-existente'))).getSingle();
      expect(
        empleado.nombres,
        'Juan',
        reason:
            'ningún Empleado real debe perderse en una migración puramente aditiva',
      );
      expect(
        empleado.bancoOtroDescripcion,
        isNull,
        reason: 'columna nueva, sin backfill',
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
    'migración 48 → 49 preserva configuraciones reales de configuracion_cobro_regla_evento como '
    'ConfiguracionCobroEtapa equivalentes, resolviendo evento_referencia al id nuevo (Etapa 15)',
    () async {
      final schemaV48 = await verifier.schemaAt(48);
      final raw = schemaV48.rawDatabase;

      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-miluyole-real', 'CLI-000099', 'MILUYOLE', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-real', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
      // `schemaAt(48)` da un snapshot estructural puro, sin la siembra que
      // una instalación real ya habría aplicado (mismo criterio que el
      // fixture de schemaAt(9) más arriba) — se inserta a mano.
      raw.execute('''
      INSERT INTO tipo_frecuencia_cobro (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.frecuenciaCobroMensual}', 'MENSUAL', 'Mensual', 1700000000, 1700000000);
    ''');

      // Vigencia real con encadenamiento completo (emisión → procesamiento
      // → pago esperado), el caso Miluyole ya validado en
      // calcular_fechas_cobro_test.dart — aquí se comprueba que la
      // migración conserva exactamente esa cadena, no solo filas sueltas.
      raw.execute('''
      INSERT INTO servicio (id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro)
      VALUES ('servicio-miluyole-real', 'SER-000099', 'cliente-miluyole-real', 'Vigilancia Miluyole', 'tipo-servicio-real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('configuracion-miluyole-real', 'servicio-miluyole-real', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_vigencia (
        id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo,
        agrupacion, metodo, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-miluyole-real', 'configuracion-miluyole-real', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 1,
        'porServicio', 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_regla_evento (configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, mes_relativo, dia_del_mes)
      VALUES ('vigencia-miluyole-real', 'emision', 'diaFijoDelMes', 'actual', 1);
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_regla_evento (configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, mes_relativo, dia_semana, ordinal_semana)
      VALUES ('vigencia-miluyole-real', 'procesamiento', 'nEsimoDiaSemanaDelMes', 'actual', 'miercoles', 'primero');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_regla_evento (configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, dia_semana, evento_referencia)
      VALUES ('vigencia-miluyole-real', 'pagoEsperado', 'mismoDiaSemanaSiguienteA', 'miercoles', 'procesamiento');
    ''');

      // Segunda vigencia real, caso Tikal: una sola regla suelta, sin
      // ninguna referencia — confirma que la migración no inventa
      // dependencias donde el modelo viejo nunca tuvo ninguna.
      raw.execute('''
      INSERT INTO servicio (id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro)
      VALUES ('servicio-tikal-real', 'SER-000098', 'cliente-miluyole-real', 'Residencial Tikal', 'tipo-servicio-real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('configuracion-tikal-real', 'servicio-tikal-real', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_vigencia (
        id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo,
        agrupacion, metodo, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-tikal-real', 'configuracion-tikal-real', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 1,
        'porServicio', 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_regla_evento (configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, mes_relativo, dia_del_mes)
      VALUES ('vigencia-tikal-real', 'pagoEsperado', 'diaFijoDelMes', 'actual', 20);
    ''');

      final conteoOriginal =
          raw
                  .select(
                    'SELECT COUNT(*) AS n FROM configuracion_cobro_regla_evento',
                  )
                  .single['n']
              as int;
      expect(
        conteoOriginal,
        4,
        reason: 'fixture: 3 reglas de Miluyole + 1 de Tikal',
      );

      final db = AppDatabase(schemaV48.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final tablaVieja =
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'configuracion_cobro_regla_evento'",
              )
              .get();
      expect(
        tablaVieja,
        isEmpty,
        reason: 'la tabla vieja se retira tras copiar sus datos',
      );

      final etapasMiluyole =
          await (db.select(db.configuracionCobroEtapa)
                ..where(
                  (t) => t.configuracionCobroVigenciaId.equals(
                    'vigencia-miluyole-real',
                  ),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.orden)]))
              .get();
      expect(
        etapasMiluyole,
        hasLength(3),
        reason: 'ninguna regla real debe perderse',
      );

      final emision = etapasMiluyole[0];
      expect(emision.tipoSistema, 'emision');
      expect(emision.orden, 0);
      expect(emision.tipoRegla, 'diaFijoDelMes');
      expect(emision.mesRelativo, 'actual');
      expect(emision.diaDelMes, 1);
      expect(emision.etapaReferenciaId, isNull);

      final procesamiento = etapasMiluyole[1];
      expect(procesamiento.tipoSistema, 'procesamiento');
      expect(procesamiento.orden, 1);
      expect(procesamiento.tipoRegla, 'nEsimoDiaSemanaDelMes');
      expect(procesamiento.diaSemana, 'miercoles');
      expect(procesamiento.ordinalSemana, 'primero');

      final pagoMiluyole = etapasMiluyole[2];
      expect(pagoMiluyole.tipoSistema, 'pagoEsperado');
      expect(pagoMiluyole.orden, 2);
      expect(pagoMiluyole.tipoRegla, 'mismoDiaSemanaSiguienteA');
      expect(pagoMiluyole.diaSemana, 'miercoles');
      expect(
        pagoMiluyole.etapaReferenciaId,
        procesamiento.id,
        reason:
            'evento_referencia ("procesamiento", un TipoEventoCobro) se resuelve al id real de la etapa hermana',
      );

      // La configuración migrada sigue siendo calculable de punta a
      // punta con el motor nuevo — no solo se copiaron columnas sueltas.
      const calcular = CalcularFechasCobroUseCase();
      final fechasMiluyole = calcular.ejecutar(
        etapas: etapasMiluyole,
        mesInicioPeriodo: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );
      expect(
        fechaDeEtapaSistema(fechasMiluyole, TipoEventoCobro.emision),
        DateTime(2026, 1, 1),
      );
      expect(
        fechaDeEtapaSistema(fechasMiluyole, TipoEventoCobro.procesamiento),
        DateTime(2026, 1, 7),
      );
      expect(
        fechaDeEtapaSistema(fechasMiluyole, TipoEventoCobro.pagoEsperado),
        DateTime(2026, 1, 14),
      );

      final etapasTikal =
          await (db.select(db.configuracionCobroEtapa)..where(
            (t) => t.configuracionCobroVigenciaId.equals('vigencia-tikal-real'),
          )).get();
      expect(etapasTikal, hasLength(1));
      expect(etapasTikal.single.tipoSistema, 'pagoEsperado');
      expect(etapasTikal.single.diaDelMes, 20);
      expect(
        etapasTikal.single.etapaReferenciaId,
        isNull,
        reason: 'el modelo viejo nunca tuvo referencia aquí',
      );

      final totalEtapas = await db.select(db.configuracionCobroEtapa).get();
      expect(
        totalEtapas,
        hasLength(4),
        reason: '3 + 1, ninguna fila extra ni faltante',
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
    'migración 49 → 50 (Etapa 15, rediseño Condiciones de Personal): copia sueldo/bono global a la '
    'vigencia vigente cuando el Servicio tiene exactamente 1 línea comercial (caso MORGAN); nunca '
    'adivina con 2+ líneas',
    () async {
      final schemaV49 = await verifier.schemaAt(49);
      final raw = schemaV49.rawDatabase;

      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-morgan', 'CLI-000088', 'Morgan Atlacomulco', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-morgan', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
      // `schemaAt(49)` da un snapshot estructural puro, sin la siembra
      // de catálogos que una instalación real ya habría aplicado (mismo
      // criterio que el fixture de `tipo_frecuencia_cobro` más arriba).
      raw.execute('''
      INSERT INTO area (id, codigo, nombre, activo, created_at, updated_at)
      VALUES ('${SeedIds.areaOperaciones}', 'OPERACIONES', 'Operaciones', 1, 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO tipo_modalidad_turno (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.modalidadTurnoMixto}', 'MIXTO', 'Mixto', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO tipo_modalidad_turno (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.modalidadTurno24x24}', '24X24', '24x24', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO tipo_modalidad_turno (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.modalidadTurno12x12}', '12X12', '12x12', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO puesto (id, codigo, nombre, area_id, tipo, nivel_jerarquico, created_at, updated_at, ciclo_vida_registro)
      VALUES ('puesto-elemento', 'PUE-000001', 'Elemento Operativo', '${SeedIds.areaOperaciones}', 'operativo', 5, 1700000000, 1700000000, 'activo');
    ''');

      // Servicio A: sueldo/bono global capturado + exactamente 1 línea
      // comercial, con exactamente 1 vigencia vigente hoy — el caso
      // trivial y determinista (real: MORGAN ATLACOMULCO).
      raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
        sueldo_mensual_referencia_personal, bono_mensual_referencia_personal,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-morgan', 'SER-000088', 'cliente-morgan', 'Vigilancia Morgan Atlacomulco', 'tipo-servicio-morgan',
        'activo', 1700000000, 1200000, 50000, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('linea-morgan', 'servicio-morgan', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial_vigencia (
        id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
        tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-morgan', 'linea-morgan', 'puesto-elemento', '${SeedIds.modalidadTurnoMixto}',
        3, 1645000, 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      // Servicio B: sueldo/bono global también capturado, pero con 2
      // líneas comerciales — nunca se adivina a cuál pertenecía.
      raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
        sueldo_mensual_referencia_personal, bono_mensual_referencia_personal,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-dos-lineas', 'SER-000089', 'cliente-morgan', 'Servicio con 2 líneas', 'tipo-servicio-morgan',
        'activo', 1700000000, 900000, 0, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('linea-dos-a', 'servicio-dos-lineas', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('linea-dos-b', 'servicio-dos-lineas', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial_vigencia (
        id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
        tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-dos-a', 'linea-dos-a', 'puesto-elemento', '${SeedIds.modalidadTurno24x24}',
        2, 1500000, 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial_vigencia (
        id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
        tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-dos-b', 'linea-dos-b', 'puesto-elemento', '${SeedIds.modalidadTurno12x12}',
        1, 2000000, 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV49.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vigenciaMorgan =
          await (db.select(db.servicioLineaComercialVigencia)
            ..where((t) => t.id.equals('vigencia-morgan'))).getSingle();
      expect(
        vigenciaMorgan.sueldoMensualReferenciaPersonal,
        1200000,
        reason: 'caso trivial: 1 sola línea vigente, se copia',
      );
      expect(vigenciaMorgan.bonoMensualReferenciaPersonal, 50000);

      final vigenciaDosA =
          await (db.select(db.servicioLineaComercialVigencia)
            ..where((t) => t.id.equals('vigencia-dos-a'))).getSingle();
      final vigenciaDosB =
          await (db.select(db.servicioLineaComercialVigencia)
            ..where((t) => t.id.equals('vigencia-dos-b'))).getSingle();
      expect(
        vigenciaDosA.sueldoMensualReferenciaPersonal,
        isNull,
        reason: '2+ líneas — nunca se adivina',
      );
      expect(vigenciaDosB.sueldoMensualReferenciaPersonal, isNull);

      // Las columnas globales de Servicio permanecen intactas — nunca
      // se borran, solo dejan de ser la fuente para operación nueva.
      final servicioMorgan =
          await (db.select(db.servicio)
            ..where((t) => t.id.equals('servicio-morgan'))).getSingle();
      expect(servicioMorgan.sueldoMensualReferenciaPersonal, 1200000);

      final columnasAsignacion =
          await db
              .customSelect("PRAGMA table_info('asignacion_servicio')")
              .get();
      expect(
        columnasAsignacion.any(
          (fila) => fila.data['name'] == 'linea_comercial_id',
        ),
        isTrue,
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
    'migración 50 → 51 (Etapa 15, Horario personalizado de línea comercial) conserva una '
    'ServicioLineaComercialVigencia real y crea ServicioLineaComercialVigenciaHorario vacía',
    () async {
      final schemaV50 = await verifier.schemaAt(50);
      final raw = schemaV50.rawDatabase;

      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real', 'CLI-000090', 'Vigilancia Real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      // `schemaAt(50)` da un snapshot estructural puro, sin la siembra
      // de catálogos que una instalación real ya habría aplicado (mismo
      // criterio que los fixtures anteriores de este archivo).
      raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.tipoServicioVigilanciaFija}', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO area (id, codigo, nombre, activo, created_at, updated_at)
      VALUES ('${SeedIds.areaOperaciones}', 'OPERACIONES', 'Operaciones', 1, 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO tipo_modalidad_turno (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.modalidadTurno24x24}', '24X24', '24x24', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO servicio (
        id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
        elementos_autorizados, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'servicio-real', 'SRV-000090', 'cliente-real', 'Vigilancia Real', '${SeedIds.tipoServicioVigilanciaFija}',
        'activo', 1700000000, 1, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO puesto (id, codigo, nombre, area_id, tipo, nivel_jerarquico, created_at, updated_at, ciclo_vida_registro)
      VALUES ('puesto-real', 'PUE-000090', 'Elemento Operativo', '${SeedIds.areaOperaciones}', 'operativo', 5,
        1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('linea-real', 'servicio-real', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio_linea_comercial_vigencia (
        id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
        tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-real', 'linea-real', 'puesto-real', '${SeedIds.modalidadTurno24x24}',
        2, 1500000, 'masIva', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV50.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final vigencia =
          await (db.select(db.servicioLineaComercialVigencia)
            ..where((t) => t.id.equals('vigencia-real'))).getSingle();
      expect(
        vigencia.cantidadElementos,
        2,
        reason:
            'ninguna vigencia real debe perderse en una migración puramente aditiva',
      );
      expect(vigencia.precioUnitario, 1500000);

      final horario =
          await db.select(db.servicioLineaComercialVigenciaHorario).get();
      expect(horario, isEmpty, reason: 'tabla nueva, sin backfill');

      // La tabla nueva sí acepta una fila real después de migrar —
      // confirma que la FK hacia la vigencia y los CHECK de rango
      // quedaron bien formados, no solo que la tabla existe vacía.
      await db
          .into(db.servicioLineaComercialVigenciaHorario)
          .insert(
            ServicioLineaComercialVigenciaHorarioCompanion.insert(
              lineaComercialVigenciaId: 'vigencia-real',
              diaSemana: 0,
              horaInicio: 1200,
              horaFin: 420,
              cruzaMedianoche: const Value(true),
            ),
          );
      final horarioTrasInsertar =
          await db.select(db.servicioLineaComercialVigenciaHorario).get();
      expect(horarioTrasInsertar, hasLength(1));

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
    'migración 51 → 52 (Etapa 15, portal único del Cliente) crea/reutiliza ClientePortal por Cliente a partir '
    'de portales legados reales, cifra cualquier contraseña capturada, deduplica por Cliente+URL+usuario, nunca '
    'toca los correos y conserva intactas las 5 columnas legacy',
    () async {
      final schemaV51 = await verifier.schemaAt(51);
      final raw = schemaV51.rawDatabase;

      raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-real', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO tipo_frecuencia_cobro (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.frecuenciaCobroMensual}', 'MENSUAL', 'Mensual', 1700000000, 1700000000);
    ''');

      // SPORTIUM (real, caso del propio Marlon en su instrucción): un
      // Cliente, dos Servicios (Coyoacán / San Ángel), cada uno con su
      // propia Configuración de cobro capturando el MISMO portal —
      // misma URL+usuario+contraseña, literalmente copiado y pegado al
      // crear el segundo club — la migración debe deduplicar a una sola
      // fila `ClientePortal`, nunca crear dos.
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-sportium', 'CLI-000091', 'SPORTIUM', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      for (final club in ['coyoacan', 'sanangel']) {
        raw.execute('''
        INSERT INTO servicio (id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro)
        VALUES ('servicio-sportium-$club', 'SER-$club', 'cliente-sportium', 'SPORTIUM ${club.toUpperCase()}', 'tipo-servicio-real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
      ''');
        raw.execute('''
        INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
        VALUES ('configuracion-sportium-$club', 'servicio-sportium-$club', 1700000000, 1700000000, 'activo');
      ''');
        raw.execute('''
        INSERT INTO configuracion_cobro_vigencia (
          id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo, agrupacion, metodo,
          portal_nombre, portal_url, portal_usuario, portal_contrasena, portal_observaciones,
          fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'vigencia-sportium-$club', 'configuracion-sportium-$club', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 21,
          'porServicio', 'noAplica',
          'Portal SIPOT', 'https://sipot.sportium.mx', 'sportium_admin', 'ClaveOriginal2025!', 'Acceso compartido entre clubes',
          1700000000, 1700000000, 1700000000, 'activo'
        );
      ''');
      }
      // Un correo real ya capturado en San Ángel — la migración no debe
      // tocarlo (instrucción explícita: "no migres ni alteres los
      // correos").
      raw.execute('''
      INSERT INTO configuracion_cobro_correo (configuracion_cobro_vigencia_id, correo)
      VALUES ('vigencia-sportium-sanangel', 'facturacion@sportium.mx');
    ''');

      // MORGAN: portal legado capturado sin contraseña (campo vacío,
      // como sí ocurría en más de una instalación real) — nunca debe
      // cifrarse un vacío, `contrasena_cifrada` debe quedar NULL.
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-morgan', 'CLI-000092', 'Morgan Atlacomulco', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio (id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro)
      VALUES ('servicio-morgan', 'SER-morgan', 'cliente-morgan', 'Vigilancia Morgan', 'tipo-servicio-real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('configuracion-morgan', 'servicio-morgan', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_vigencia (
        id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo, agrupacion, metodo,
        portal_nombre, portal_url, portal_usuario, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-morgan', 'configuracion-morgan', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 1,
        'porServicio', 'noAplica', 'Portal Morgan', 'https://portal.morgan.mx', 'morgan_admin',
        1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      // TOLUCA 32: sin ningún portal capturado — caso real ya conocido
      // de este archivo. Debe seguir sin portal después de migrar,
      // nunca inventar uno.
      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-toluca', 'CLI-000093', 'Toluca 32', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO servicio (id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro)
      VALUES ('servicio-toluca', 'SER-toluca', 'cliente-toluca', 'Vigilancia Toluca 32', 'tipo-servicio-real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('configuracion-toluca', 'servicio-toluca', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO configuracion_cobro_vigencia (
        id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo, agrupacion, metodo,
        fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-toluca', 'configuracion-toluca', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 1,
        'porServicio', 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');

      final almacen = _AlmacenClaveCifradoEnMemoria();
      final db = AppDatabase(
        schemaV51.newConnection(),
        almacenClaveCifrado: almacen,
      );
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // Deduplicación: 2 vigencias de SPORTIUM con el mismo Cliente +
      // URL + usuario → un solo ClientePortal nuevo, nunca dos.
      final vigenciaCoyoacan =
          await (db.select(db.configuracionCobroVigencia)..where(
            (t) => t.id.equals('vigencia-sportium-coyoacan'),
          )).getSingle();
      final vigenciaSanAngel =
          await (db.select(db.configuracionCobroVigencia)..where(
            (t) => t.id.equals('vigencia-sportium-sanangel'),
          )).getSingle();
      expect(vigenciaCoyoacan.clientePortalId, isNotNull);
      expect(
        vigenciaCoyoacan.clientePortalId,
        vigenciaSanAngel.clientePortalId,
        reason: 'mismo Cliente+URL+usuario → un solo portal, deduplicado',
      );

      final portalSportium =
          await (db.select(db.clientePortal)..where(
            (t) => t.id.equals(vigenciaCoyoacan.clientePortalId!),
          )).getSingle();
      expect(portalSportium.clienteId, 'cliente-sportium');
      expect(portalSportium.nombre, 'Portal SIPOT');
      expect(portalSportium.url, 'https://sipot.sportium.mx');
      expect(portalSportium.usuario, 'sportium_admin');
      expect(portalSportium.observaciones, 'Acceso compartido entre clubes');
      expect(
        portalSportium.tipo,
        TipoPortalCliente.otro.name,
        reason: 'el modelo legado nunca capturó tipo/propósito',
      );
      expect(portalSportium.cicloVidaRegistro, 'activo');

      // La contraseña legada quedó cifrada — nunca en texto plano —
      // pero descifra exactamente al valor original.
      expect(portalSportium.contrasenaCifrada, isNotNull);
      expect(
        portalSportium.contrasenaCifrada,
        isNot(equals('ClaveOriginal2025!')),
      );
      expect(portalSportium.contrasenaCifrada, startsWith('aesgcm\$1\$'));
      final cipherVerificacion = CredentialCipher(almacen: almacen);
      expect(
        await cipherVerificacion.descifrar(portalSportium.contrasenaCifrada!),
        'ClaveOriginal2025!',
      );

      // Las 5 columnas legacy de ambas vigencias de SPORTIUM se
      // conservan intactas — nunca se borran ni se alteran.
      expect(vigenciaCoyoacan.portalNombre, 'Portal SIPOT');
      expect(vigenciaCoyoacan.portalUrl, 'https://sipot.sportium.mx');
      expect(vigenciaCoyoacan.portalUsuario, 'sportium_admin');
      expect(vigenciaCoyoacan.portalContrasena, 'ClaveOriginal2025!');
      expect(vigenciaSanAngel.portalContrasena, 'ClaveOriginal2025!');

      // El correo real de San Ángel no se tocó — ni se migró a otra
      // parte, ni se alteró su contenido.
      final correosSanAngel =
          await (db.select(db.configuracionCobroCorreo)..where(
            (t) => t.configuracionCobroVigenciaId.equals(
              'vigencia-sportium-sanangel',
            ),
          )).get();
      expect(correosSanAngel, hasLength(1));
      expect(correosSanAngel.single.correo, 'facturacion@sportium.mx');

      // MORGAN: portal propio (Cliente distinto, nunca se mezcla con
      // SPORTIUM), sin contraseña — nunca se inventa ni se cifra un
      // vacío.
      final vigenciaMorgan =
          await (db.select(db.configuracionCobroVigencia)
            ..where((t) => t.id.equals('vigencia-morgan'))).getSingle();
      expect(vigenciaMorgan.clientePortalId, isNotNull);
      expect(
        vigenciaMorgan.clientePortalId,
        isNot(equals(vigenciaCoyoacan.clientePortalId)),
      );
      final portalMorgan =
          await (db.select(db.clientePortal)..where(
            (t) => t.id.equals(vigenciaMorgan.clientePortalId!),
          )).getSingle();
      expect(portalMorgan.clienteId, 'cliente-morgan');
      expect(portalMorgan.nombre, 'Portal Morgan');
      expect(
        portalMorgan.contrasenaCifrada,
        isNull,
        reason: 'nunca se inventa ni se cifra una contraseña que no existía',
      );

      // TOLUCA 32: nunca tuvo portal — sigue sin ninguno, la migración
      // nunca inventa uno donde el modelo legado no capturó nada.
      final vigenciaToluca =
          await (db.select(db.configuracionCobroVigencia)
            ..where((t) => t.id.equals('vigencia-toluca'))).getSingle();
      expect(vigenciaToluca.clientePortalId, isNull);
      final portalesToluca =
          await (db.select(db.clientePortal)
            ..where((t) => t.clienteId.equals('cliente-toluca'))).get();
      expect(portalesToluca, isEmpty);

      // Exactamente 2 portales nuevos en total: SPORTIUM (deduplicado) + MORGAN.
      final totalPortales = await db.select(db.clientePortal).get();
      expect(totalPortales, hasLength(2));

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
    'migración 53 → 55 conserva Nóminas/renglones/pago históricos reales: el listado carga, una Nómina '
    'anterior y una Borrador abren, los importes no cambian, los descuentos de Inventario quedan en 0 '
    'sin bloquear el cierre, y el pago histórico sigue vinculado',
    () async {
      final schemaV53 = await verifier.schemaAt(53);
      final raw = schemaV53.rawDatabase;

      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1700000000, 3,
        1700000000, 1700000000, 'activo'
      );
    ''');

      // Nómina histórica ya CERRADA, con un renglón y un pago real —
      // exactamente el caso "abre una nómina anterior" / "una nómina
      // pagada histórica sigue mostrando sus pagos".
      raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, fecha_cierre, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-cerrada-real', 'NOM-000001', 2026, 6, 'primera', 1700000000, 1701000000, 1701100000,
        'cerrada', 1701200000, 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO nomina_empleado (
        id, nomina_id, empleado_id, numero_empleado, nombre_completo, fuente_sueldo_utilizada,
        dias_pagables, sueldo_mensual_utilizado, sueldo_quincenal_referencia, pago_por_dia, importe_base,
        prestamo, tiempo_extra, bono, faltas, descuento_por_faltas, otros_descuentos,
        monto_fiscal, monto_no_fiscal, total_a_pagar,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'renglon-cerrada-real', 'nomina-cerrada-real', 'empleado-real', 1, 'Juan Pérez', 'administrativo',
        15, 1500000, 750000, 50000, 750000,
        0, 0, 0, 0, 0, 0,
        750000, 0, 750000,
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO pago_nomina (
        id, folio_pago_nomina, nomina_id, monto_total, fecha_pago, forma_pago, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'pago-real', 'PAG-NOM-000001', 'nomina-cerrada-real', 750000, 1701200000, 'transferencia', 'registrado',
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO aplicacion_pago_nomina (
        id, pago_nomina_id, nomina_empleado_id, monto, saldo_antes, saldo_despues,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'aplicacion-real', 'pago-real', 'renglon-cerrada-real', 750000, 750000, 0,
        1700000000, 1700000000, 'activo'
      );
    ''');

      // Nómina BORRADOR real, sin pago — caso "abre una nómina
      // borrador".
      raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-borrador-real', 'NOM-000002', 2026, 7, 'primera', 1703000000, 1704000000, 1704100000,
        'borrador', 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO nomina_empleado (
        id, nomina_id, empleado_id, numero_empleado, nombre_completo, fuente_sueldo_utilizada,
        dias_pagables, sueldo_mensual_utilizado, sueldo_quincenal_referencia, pago_por_dia, importe_base,
        prestamo, tiempo_extra, bono, faltas, descuento_por_faltas, otros_descuentos,
        monto_fiscal, monto_no_fiscal, total_a_pagar,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'renglon-borrador-real', 'nomina-borrador-real', 'empleado-real', 1, 'Juan Pérez', 'administrativo',
        15, 1500000, 750000, 50000, 750000,
        20000, 0, 0, 0, 0, 0,
        730000, 0, 730000,
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV53.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // "Carga el listado de nóminas históricas" — exactamente la
      // consulta de `NominaRepositoryImpl.listar` / `NominasController`.
      final nominas = await db.select(db.nomina).get();
      expect(
        nominas,
        hasLength(2),
        reason: 'ninguna Nómina real debe perderse en una migración aditiva',
      );

      // "Abre una nómina anterior".
      final nominaCerrada = nominas.firstWhere(
        (n) => n.id == 'nomina-cerrada-real',
      );
      expect(nominaCerrada.estatus, 'cerrada');
      final renglonesCerrada =
          await (db.select(db.nominaEmpleado)
            ..where((t) => t.nominaId.equals('nomina-cerrada-real'))).get();
      expect(
        renglonesCerrada,
        hasLength(1),
        reason: '"abre una nómina anterior" — el renglón histórico se conserva',
      );
      final renglonCerrada = renglonesCerrada.single;
      expect(
        renglonCerrada.totalAPagar,
        750000,
        reason: 'los renglones históricos conservan sus importes',
      );
      expect(renglonCerrada.importeBase, 750000);
      expect(
        renglonCerrada.descuentosInventario,
        0,
        reason: 'campo nuevo con backfill 0 para un renglón anterior a v54',
      );
      expect(renglonCerrada.descuentosInventarioPendienteRevision, isFalse);

      // "Abre una nómina borrador".
      final nominaBorrador = nominas.firstWhere(
        (n) => n.id == 'nomina-borrador-real',
      );
      expect(nominaBorrador.estatus, 'borrador');
      final renglonesBorrador =
          await (db.select(db.nominaEmpleado)
            ..where((t) => t.nominaId.equals('nomina-borrador-real'))).get();
      expect(renglonesBorrador, hasLength(1));
      expect(renglonesBorrador.single.totalAPagar, 730000);

      // "Una nómina pagada histórica sigue mostrando sus pagos".
      final pagos =
          await (db.select(db.pagoNomina)
            ..where((t) => t.nominaId.equals('nomina-cerrada-real'))).get();
      expect(pagos, hasLength(1));
      expect(pagos.single.montoTotal, 750000);
      final aplicaciones =
          await (db.select(db.aplicacionPagoNomina)..where(
            (t) => t.nominaEmpleadoId.equals('renglon-cerrada-real'),
          )).get();
      expect(aplicaciones, hasLength(1));
      expect(aplicaciones.single.pagoNominaId, 'pago-real');

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
    'BUG REAL (Etapa 15): una instalación que se quedó "atascada" en schemaVersion 54 con la forma anterior de '
    'migrarDescuentoInventarioNominaV54 (sin descuentos_inventario_pendiente_revision) se repara al migrar a 55 '
    '— reproduce exactamente "No se pudo cargar la nómina" y confirma que deja de ocurrir sin perder historial '
    'ni alterar ningún DescuentoInventario existente',
    () async {
      final schemaV53 = await verifier.schemaAt(53);
      final raw = schemaV53.rawDatabase;

      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-atascado', 2, 'Pedro', 'Gómez', 'masculino', 631152000, 'GOPJ900101HDFXXX02',
        'GOPJ900101AB2', '12345678902', 'soltero', 1700000000, 3,
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-atascada-real', 'NOM-000022', 2026, 8, 'primera', 1700000000, 1701000000, 1701100000,
        'borrador', 1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO nomina_empleado (
        id, nomina_id, empleado_id, numero_empleado, nombre_completo, fuente_sueldo_utilizada,
        dias_pagables, sueldo_mensual_utilizado, sueldo_quincenal_referencia, pago_por_dia, importe_base,
        prestamo, tiempo_extra, bono, faltas, descuento_por_faltas, otros_descuentos,
        monto_fiscal, monto_no_fiscal, total_a_pagar,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'renglon-atascado-real', 'nomina-atascada-real', 'empleado-atascado', 2, 'Pedro Gómez', 'administrativo',
        15, 1500000, 750000, 50000, 750000,
        0, 0, 0, 0, 0, 0,
        750000, 0, 750000,
        1700000000, 1700000000, 'activo'
      );
    ''');

      // Un `DescuentoInventario` real y PENDIENTE, previo a toda la
      // integración con Nómina (Etapa 7B) — "no se altera ningún
      // descuento existente" exige que sobreviva intacto.
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-real', 'Uniformes', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo (id, folio, categoria_id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('articulo-real', 'ART-000001', 'categoria-real', 'PANTALON NEGRO COMANDO', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO asignacion (
        id, articulo_id, cantidad, empleado_id, fecha_entrega, estatus, fecha_cierre, atribuible_al_empleado,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'asignacion-real', 'articulo-real', 1, 'empleado-atascado', 1700000000, 'perdida', 1700100000, 1,
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO descuento_inventario (
        id, asignacion_id, empleado_id, motivo, importe, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'descuento-real-preexistente', 'asignacion-real', 'empleado-atascado', 'perdida', 20000, 'pendiente',
        1700000000, 1700000000, 'activo'
      );
    ''');

      // Simula EXACTAMENTE el estado real reportado por Marlon: la
      // instalación ya corrió la forma ANTERIOR de
      // `migrarDescuentoInventarioNominaV54` (agregaba solo estas dos
      // columnas) y guardó `user_version = 54` — la tercera columna
      // (`descuentos_inventario_pendiente_revision`, agregada después
      // en el mismo cambio sin subir de versión) nunca llegó a esta
      // base de datos.
      raw.execute(
        'ALTER TABLE descuento_inventario ADD COLUMN nomina_empleado_id TEXT NULL REFERENCES nomina_empleado (id) ON DELETE RESTRICT;',
      );
      raw.execute(
        'ALTER TABLE nomina_empleado ADD COLUMN descuentos_inventario INTEGER NOT NULL DEFAULT 0;',
      );
      raw.execute('PRAGMA user_version = 54;');

      // Antes del fix (`migrarReparacionDescuentosInventarioV55`), abrir
      // esta base de datos con schemaVersion 55 SIN el paso de
      // reparación reproduce el bug real reportado: Drift genera un
      // `SELECT` que incluye TODAS las columnas declaradas de
      // `NominaEmpleado` (incluida `descuentos_inventario_pendiente_revision`,
      // que ya existe en el código Dart actual mucho antes de este
      // cambio) contra una tabla física que no la tiene —
      // `SqliteException(1): no such column: descuentos_inventario_pendiente_revision`,
      // capturada por `NominasController._cargar` y mostrada como "No
      // se pudo cargar la nómina. Ocurrió un error al cargar el listado
      // de nóminas.". El `verifier.migrateAndValidate` de abajo aplica
      // el fix real (el paso de reparación agregado a `onUpgrade`) y
      // confirma que dejó de ocurrir.
      final db = AppDatabase(schemaV53.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // La consulta exacta que usa la pantalla (`NominasController._cargar`
      // → `NominaRepositoryImpl.listar` + `listarEmpleados`) ya no
      // lanza ninguna excepción.
      final nominas = await db.select(db.nomina).get();
      expect(nominas, hasLength(1));
      final renglones =
          await (db.select(db.nominaEmpleado)
            ..where((t) => t.nominaId.equals('nomina-atascada-real'))).get();
      expect(
        renglones,
        hasLength(1),
        reason: 'el renglón histórico sobrevive a la reparación',
      );
      final renglon = renglones.single;
      expect(
        renglon.totalAPagar,
        750000,
        reason: 'los importes no se alteran al reparar la columna faltante',
      );
      expect(renglon.descuentosInventario, 0);
      expect(
        renglon.descuentosInventarioPendienteRevision,
        isFalse,
        reason: 'columna reparada con su default, sin bloquear nada',
      );

      // "No se altera ningún descuento existente" — el DescuentoInventario
      // preexistente sigue pendiente, con su importe intacto y sin
      // vínculo a ninguna Nómina inventado por la reparación.
      final descuento =
          await (db.select(db.descuentoInventario)..where(
            (t) => t.id.equals('descuento-real-preexistente'),
          )).getSingle();
      expect(descuento.estatus, 'pendiente');
      expect(descuento.importe, 20000);
      expect(
        descuento.nominaEmpleadoId,
        isNull,
        reason: 'la reparación nunca inventa una aplicación que no existía',
      );

      final violacionesFk =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(
        violacionesFk,
        isEmpty,
        reason: 'foreign_key_check debe quedar limpio tras la reparación',
      );

      final integridad =
          await db
              .customSelect('PRAGMA integrity_check')
              .map((r) => r.data['integrity_check'] as String)
              .get();
      expect(
        integridad,
        ['ok'],
        reason: 'integrity_check debe reportar "ok" tras la reparación',
      );

      await db.close();
    },
  );

  test(
    'migración 55 → 56 (Etapa 15, rediseño del Dashboard) conserva datos existentes y crea VacanteOperativa vacía',
    () async {
      final schemaV55 = await verifier.schemaAt(55);
      final raw = schemaV55.rawDatabase;

      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real-v55', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1700000000, 3,
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV55.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final empleado =
          await (db.select(db.empleado)
            ..where((t) => t.id.equals('empleado-real-v55'))).getSingleOrNull();
      expect(
        empleado,
        isNotNull,
        reason:
            'ningún Empleado real debe perderse en una migración puramente aditiva',
      );

      final vacantes = await db.select(db.vacanteOperativa).get();
      expect(
        vacantes,
        isEmpty,
        reason:
            'tabla nueva, sin backfill — se mantiene hacia adelante, nunca retroactivo',
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

  test('migración 56 → 57 (Etapa 15, Descuentos Programados al Personal) conserva un préstamo manual histórico, '
      'crea tablas nuevas vacías y siembra CodigoSecuencia', () async {
    final schemaV56 = await verifier.schemaAt(56);
    final raw = schemaV56.rawDatabase;

    raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-real-v56', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
        'PEXJ900101AB1', '12345678901', 'soltero', 1700000000, 3,
        1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute('''
      INSERT INTO nomina (
        id, folio, anio, mes, tipo_periodo, fecha_inicio_periodo, fecha_fin_periodo, fecha_pago_ordinaria,
        estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'nomina-real-v56', 'NOM-000001', 2026, 1, 'primera', 1735689600, 1736812800, 1737331200,
        'cerrada', 1700000000, 1700000000, 'activo'
      );
    ''');
    // Renglón histórico con `prestamo > 0` capturado a mano — el
    // módulo nuevo nunca debe destruir ni reinterpretar este dato
    // (Resolución explícita de Marlon: "Puede etiquetarse en lectura
    // como 'Préstamo manual histórico'. No migrar/inventar préstamos
    // nuevos para registros históricos sin evidencia").
    raw.execute('''
      INSERT INTO nomina_empleado (
        id, nomina_id, empleado_id, numero_empleado, nombre_completo, fuente_sueldo_utilizada,
        dias_pagables, sueldo_mensual_utilizado, sueldo_quincenal_referencia, pago_por_dia, importe_base,
        prestamo, tiempo_extra, bono, faltas, descuento_por_faltas, otros_descuentos,
        descuentos_inventario, descuentos_inventario_pendiente_revision,
        monto_fiscal, monto_no_fiscal, total_a_pagar,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'renglon-prestamo-manual-v56', 'nomina-real-v56', 'empleado-real-v56', 1, 'Juan Pérez', 'administrativo',
        15, 1500000, 750000, 50000, 750000,
        50000, 0, 0, 0, 0, 0,
        0, 0,
        700000, 0, 700000,
        1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaV56.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final renglon =
        await (db.select(db.nominaEmpleado)..where(
          (t) => t.id.equals('renglon-prestamo-manual-v56'),
        )).getSingle();
    expect(
      renglon.prestamo,
      50000,
      reason:
          'el préstamo manual histórico se conserva intacto, nunca se destruye ni se reinterpreta',
    );
    expect(
      renglon.totalAPagar,
      700000,
      reason: 'ningún importe histórico se recalcula por la migración',
    );
    expect(
      renglon.descuentosProgramados,
      0,
      reason: 'columna nueva, default 0 — sin backfill inventado',
    );
    expect(renglon.descuentosProgramadosPendienteRevision, isFalse);

    final descuentos = await db.select(db.descuentoProgramadoEmpleado).get();
    expect(
      descuentos,
      isEmpty,
      reason:
          'tabla nueva, sin backfill — se mantiene hacia adelante, nunca retroactivo',
    );
    final cuotas = await db.select(db.descuentoProgramadoCuota).get();
    expect(cuotas, isEmpty);
    final movimientos = await db.select(db.descuentoProgramadoMovimiento).get();
    expect(movimientos, isEmpty);

    final secuenciaPrestamo =
        await (db.select(db.codigoSecuencia)..where(
          (t) => t.entityType.equals('descuentoProgramadoPrestamo'),
        )).getSingle();
    expect(secuenciaPrestamo.prefijo, 'PRE');
    expect(
      secuenciaPrestamo.contadorActual,
      0,
      reason: 'sembrado sin consumir ningún folio todavía',
    );
    final secuenciaBotas =
        await (db.select(db.codigoSecuencia)..where(
          (t) => t.entityType.equals('descuentoProgramadoBotas'),
        )).getSingle();
    expect(secuenciaBotas.prefijo, 'DES');

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
  });

  test(
    'migración 57 → 58 (Etapa 15, rediseño de Personal/Bajas) agrega el snapshot de baja y hace backfill real del '
    'puesto de una baja vigente — servicio/turno quedan NULL cuando no hay AsignacionServicio que cruzar (nunca inventados)',
    () async {
      final schemaV57 = await verifier.schemaAt(57);
      final raw = schemaV57.rawDatabase;

      raw.execute('''
      INSERT INTO area (id, codigo, nombre, created_at, updated_at)
      VALUES ('area-v57', 'ARE-TEST', 'Operaciones', 1700000000, 1700000000);
    ''');
      raw.execute('''
      INSERT INTO puesto (
        id, codigo, nombre, area_id, tipo, nivel_jerarquico, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'puesto-v57', 'PUE-TEST', 'Elemento Operativo', 'area-v57', 'operativo', 1, 1700000000, 1700000000, 'activo'
      );
    ''');
      // Empleado YA de baja (nunca reingresó) — el puesto todavía
      // apunta al puntero vigente sin sobrescribir, así que sí debe
      // recuperarse; nunca tuvo AsignacionServicio, así que
      // servicio/turno deben quedar NULL, nunca inventados.
      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, puesto_id, estatus, fecha_baja, motivo_baja,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-baja-v57', 1, 'Ana', 'Gómez', 'femenino', 631152000, 'GOAX900101MDFXXX01',
        'GOAX900101AB1', '12345678902', 'soltero', 1700000000, 3, 'puesto-v57', 'baja', 1705000000, 'renuncia',
        1700000000, 1705000000, 'activo'
      );
    ''');
      // Empleado ya reingresado con un periodo archivado — servicio/
      // turno de ESE periodo también deben quedar NULL (sin
      // AsignacionServicio con ese motivo/fecha exactos), y puesto de
      // un periodo YA archivado antes de esta migración es
      // irrecuperable a propósito (ver el doc comment de la migración).
      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-reingreso-v57', 2, 'Luis', 'Torres', 'masculino', 631152000, 'TOLX900101HDFXXX01',
        'TOLX900101AB2', '12345678903', 'soltero', 1705000000, 2, 'activo',
        1700000000, 1705000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO empleado_periodo_laboral (id, empleado_id, fecha_ingreso, fecha_baja, motivo_baja)
      VALUES (1, 'empleado-reingreso-v57', 1690000000, 1700000000, 'finContrato');
    ''');

      final db = AppDatabase(schemaV57.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final bajaVigente =
          await (db.select(db.empleado)
            ..where((t) => t.id.equals('empleado-baja-v57'))).getSingle();
      expect(
        bajaVigente.puestoNombreBaja,
        'Elemento Operativo',
        reason:
            'puesto todavía intacto — nunca reingresó, se recupera del puntero vigente',
      );
      expect(
        bajaVigente.servicioNombreBaja,
        isNull,
        reason:
            'sin AsignacionServicio que cruzar — nunca se inventa un Servicio',
      );
      expect(bajaVigente.turnoNombreBaja, isNull);

      final periodo =
          await (db.select(db.empleadoPeriodoLaboral)..where(
            (t) => t.empleadoId.equals('empleado-reingreso-v57'),
          )).getSingle();
      expect(
        periodo.puestoNombre,
        isNull,
        reason:
            'puesto de un periodo ya archivado antes de esta migración es irrecuperable — nunca inventado',
      );
      expect(periodo.servicioNombre, isNull);
      expect(periodo.turnoNombre, isNull);
      expect(
        periodo.motivoBaja,
        'finContrato',
        reason: 'los datos existentes del periodo archivado nunca se tocan',
      );

      final activo =
          await (db.select(db.empleado)
            ..where((t) => t.id.equals('empleado-reingreso-v57'))).getSingle();
      expect(
        activo.puestoNombreBaja,
        isNull,
        reason:
            'Empleado activo — el bloque de snapshot de baja completo queda NULL',
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
    'migración 58 → 59 (Etapa 16, evolución visual) agrega Cliente.logoAttachmentId, NULL para clientes existentes',
    () async {
      final schemaV58 = await verifier.schemaAt(58);
      final raw = schemaV58.rawDatabase;

      raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-real-v58', 'CLI-000001', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');

      final db = AppDatabase(schemaV58.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final cliente =
          await (db.select(db.cliente)
            ..where((t) => t.id.equals('cliente-real-v58'))).getSingle();
      expect(
        cliente.nombreComercial,
        'Sportium',
        reason:
            'ningún Cliente real debe perderse en una migración puramente aditiva',
      );
      expect(
        cliente.logoAttachmentId,
        isNull,
        reason:
            'ningún Cliente existente tiene un logo que reconstruir — NULL, nunca inventado',
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
    'migración 59 → 60 ("Entrega múltiple de Inventario") crea la tabla Entrega, agrega Asignacion.entregaId '
    '(NULL para toda Asignacion legacy) y siembra CodigoSecuencia ENT',
    () async {
      final schemaV59 = await verifier.schemaAt(59);
      final raw = schemaV59.rawDatabase;

      raw.execute('''
      INSERT INTO empleado (
        id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
        estado_civil, fecha_ingreso, anios_experiencia_seguridad,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'empleado-v59', 1, 'Brenda', 'Cruz', 'femenino', 631152000, 'CUGB900101MDFXXX01',
        'CUGB900101AB1', '12345678901', 'soltero', 1700000000, 3,
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO categoria_articulo (id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('categoria-v59', 'Uniformes', 1700000000, 1700000000, 'activo');
    ''');
      raw.execute('''
      INSERT INTO articulo (id, folio, categoria_id, nombre, created_at, updated_at, ciclo_vida_registro)
      VALUES ('articulo-v59', 'ART-000001', 'categoria-v59', 'CAMISOLA', 1700000000, 1700000000, 'activo');
    ''');
      // Asignacion legacy real, creada por el flujo individual "Asignar
      // artículo" — nunca tuvo ni podía tener un concepto de Entrega.
      raw.execute('''
      INSERT INTO asignacion (
        id, articulo_id, cantidad, empleado_id, fecha_entrega, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'asignacion-legacy-v59', 'articulo-v59', 1, 'empleado-v59', 1700000000, 'activa',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV59.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final tablas =
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name = 'entrega'",
              )
              .get();
      expect(
        tablas,
        hasLength(1),
        reason: 'la tabla Entrega debe existir tras la migración',
      );

      final legacy =
          await (db.select(db.asignacion)
            ..where((t) => t.id.equals('asignacion-legacy-v59'))).getSingle();
      expect(
        legacy.entregaId,
        isNull,
        reason:
            'una Asignacion legacy nunca debe quedar agrupada retroactivamente',
      );
      expect(
        legacy.estatus,
        'activa',
        reason: 'ningún dato existente se altera — migración puramente aditiva',
      );

      final codigoEntrega =
          await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('entrega'))).getSingleOrNull();
      expect(
        codigoEntrega,
        isNotNull,
        reason: 'CodigoSecuencia para "entrega" debe sembrarse en la migración',
      );
      expect(codigoEntrega!.prefijo, 'ENT');
      expect(codigoEntrega.digitos, 6);

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

  test('migración 60 → 61 (Etapa 19, "Deudas y crédito empresarial") crea las tablas Deuda/MovimientoDeuda, '
      'conserva un Egreso real existente y siembra CodigoSecuencia DEU', () async {
    final schemaV60 = await verifier.schemaAt(60);
    final raw = schemaV60.rawDatabase;

    // Egreso real preexistente — una migración puramente aditiva
    // nunca debe tocarlo.
    raw.execute('''
      INSERT INTO egreso (
        id, folio_egreso, monto, fecha, forma_pago, concepto, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'egreso-v60', 'EGR-000001', 500000, 1700000000, 'transferencia', 'Renta de oficina', 'registrado',
        1700000000, 1700000000, 'activo'
      );
    ''');

    final db = AppDatabase(schemaV60.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    final tablaDeuda =
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name = 'deuda'",
            )
            .get();
    expect(
      tablaDeuda,
      hasLength(1),
      reason: 'la tabla Deuda debe existir tras la migración',
    );

    final tablaMovimientoDeuda =
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name = 'movimiento_deuda'",
            )
            .get();
    expect(
      tablaMovimientoDeuda,
      hasLength(1),
      reason: 'la tabla MovimientoDeuda debe existir tras la migración',
    );

    final egresoPreexistente =
        await (db.select(db.egreso)
          ..where((t) => t.id.equals('egreso-v60'))).getSingle();
    expect(
      egresoPreexistente.monto,
      500000,
      reason:
          'ningún Egreso real debe perderse en una migración puramente aditiva',
    );
    expect(egresoPreexistente.estatus, 'registrado');

    final codigoDeuda =
        await (db.select(db.codigoSecuencia)
          ..where((t) => t.entityType.equals('deuda'))).getSingleOrNull();
    expect(
      codigoDeuda,
      isNotNull,
      reason: 'CodigoSecuencia para "deuda" debe sembrarse en la migración',
    );
    expect(codigoDeuda!.prefijo, 'DEU');
    expect(codigoDeuda.digitos, 6);

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
  });

  test(
    'migración 61 → 62 (Etapa 19B, "Compra ↔ Tarjeta de crédito ↔ Deuda") agrega '
    'MovimientoDeuda.compraId y Compra.deudaId, ambas nullable, y conserva filas reales existentes',
    () async {
      final schemaV61 = await verifier.schemaAt(61);
      final raw = schemaV61.rawDatabase;

      // Compra real preexistente (pagada de contado, como toda Compra
      // antes de esta etapa) — una migración puramente aditiva nunca
      // debe tocarla.
      raw.execute('''
      INSERT INTO compra (
        id, folio_compra, fecha, forma_pago, estatus, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'compra-v61', 'COM-000001', 1700000000, 'efectivo', 'registrada', 1700000000, 1700000000, 'activo'
      );
    ''');

      // Deuda + MovimientoDeuda real preexistentes (tarjeta con un pago
      // ya registrado antes de esta etapa).
      raw.execute('''
      INSERT INTO deuda (
        id, folio, nombre, tipo, fecha_origen, importe_original, saldo_actual, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'deuda-v61', 'DEU-000001', 'TDC BBVA', 'tarjetaCredito', 1700000000, 5000000, 4000000, 'activa',
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO movimiento_deuda (
        deuda_id, fecha, tipo, importe, saldo_anterior, saldo_posterior
      ) VALUES (
        'deuda-v61', 1700000000, 'pago', 1000000, 5000000, 4000000
      );
    ''');

      final db = AppDatabase(schemaV61.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnasMovimientoDeuda =
          await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
      expect(
        columnasMovimientoDeuda.map((f) => f.data['name']),
        contains('compra_id'),
        reason: 'MovimientoDeuda.compraId debe existir tras la migración',
      );

      final columnasCompra =
          await db.customSelect("PRAGMA table_info('compra')").get();
      expect(
        columnasCompra.map((f) => f.data['name']),
        contains('deuda_id'),
        reason: 'Compra.deudaId debe existir tras la migración',
      );

      final compraPreexistente =
          await (db.select(db.compra)
            ..where((t) => t.id.equals('compra-v61'))).getSingle();
      expect(
        compraPreexistente.deudaId,
        isNull,
        reason:
            'una Compra pagada de contado nunca tuvo tarjeta — deudaId debe quedar null',
      );
      expect(
        compraPreexistente.folioCompra,
        'COM-000001',
        reason:
            'ninguna Compra real debe perderse en una migración puramente aditiva',
      );

      final movimientoPreexistente =
          await (db.select(db.movimientoDeuda)
            ..where((t) => t.deudaId.equals('deuda-v61'))).getSingle();
      expect(
        movimientoPreexistente.compraId,
        isNull,
        reason:
            'un pago ya registrado antes de esta etapa nunca tuvo Compra — compraId debe quedar null',
      );
      expect(
        movimientoPreexistente.importe,
        1000000,
        reason:
            'ningún MovimientoDeuda real debe perderse en una migración puramente aditiva',
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
    'migración 62 → 63 (Etapa 19C, "Posición de caja, flujo real y proyección de compromisos") crea la tabla '
    'CuentaFinanciera, agrega Ingreso.cuentaFinancieraId/Egreso.cuentaFinancieraId y conserva filas reales existentes',
    () async {
      final schemaV62 = await verifier.schemaAt(62);
      final raw = schemaV62.rawDatabase;

      // Ingreso/Egreso reales preexistentes (antes de esta etapa,
      // ninguno tenía cuenta financiera) — una migración puramente
      // aditiva nunca debe tocarlos.
      raw.execute('''
      INSERT INTO ingreso (
        id, folio_ingreso, monto, fecha, forma_pago, concepto, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'ingreso-v62', 'ING-000001', 500000, 1700000000, 'efectivo', 'Ingreso de prueba', 'registrado',
        1700000000, 1700000000, 'activo'
      );
    ''');
      raw.execute('''
      INSERT INTO egreso (
        id, folio_egreso, monto, fecha, forma_pago, concepto, estatus,
        created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'egreso-v62', 'EGR-000001', 300000, 1700000000, 'transferencia', 'Egreso de prueba', 'registrado',
        1700000000, 1700000000, 'activo'
      );
    ''');

      final db = AppDatabase(schemaV62.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final tablaCuentaFinanciera =
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name = 'cuenta_financiera'",
              )
              .get();
      expect(
        tablaCuentaFinanciera,
        hasLength(1),
        reason: 'la tabla CuentaFinanciera debe existir tras la migración',
      );

      final columnasIngreso =
          await db.customSelect("PRAGMA table_info('ingreso')").get();
      expect(
        columnasIngreso.map((f) => f.data['name']),
        contains('cuenta_financiera_id'),
        reason: 'Ingreso.cuentaFinancieraId debe existir tras la migración',
      );

      final columnasEgreso =
          await db.customSelect("PRAGMA table_info('egreso')").get();
      expect(
        columnasEgreso.map((f) => f.data['name']),
        contains('cuenta_financiera_id'),
        reason: 'Egreso.cuentaFinancieraId debe existir tras la migración',
      );

      final ingresoPreexistente =
          await (db.select(db.ingreso)
            ..where((t) => t.id.equals('ingreso-v62'))).getSingle();
      expect(
        ingresoPreexistente.cuentaFinancieraId,
        isNull,
        reason:
            'un Ingreso histórico nunca tuvo cuenta financiera — debe quedar null, nunca inferido',
      );
      expect(
        ingresoPreexistente.monto,
        500000,
        reason:
            'ningún Ingreso real debe perderse en una migración puramente aditiva',
      );

      final egresoPreexistente =
          await (db.select(db.egreso)
            ..where((t) => t.id.equals('egreso-v62'))).getSingle();
      expect(
        egresoPreexistente.cuentaFinancieraId,
        isNull,
        reason:
            'un Egreso histórico nunca tuvo cuenta financiera — debe quedar null, nunca inferido',
      );
      expect(
        egresoPreexistente.monto,
        300000,
        reason:
            'ningún Egreso real debe perderse en una migración puramente aditiva',
      );

      final codigoCuentaFinanciera =
          await (db.select(db.codigoSecuencia)..where(
            (t) => t.entityType.equals('cuenta_financiera'),
          )).getSingleOrNull();
      expect(
        codigoCuentaFinanciera,
        isNotNull,
        reason:
            'CodigoSecuencia para "cuenta_financiera" debe sembrarse en la migración',
      );
      expect(codigoCuentaFinanciera!.prefijo, 'CTA');
      expect(codigoCuentaFinanciera.digitos, 4);

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
    'migración 63 → 64 (Etapa 19D, "Calendario financiero y planeación de liquidez") agrega '
    'CuentaPorCobrar.fechaCobroReprogramada y conserva una CxC real existente',
    () async {
      final schemaV63 = await verifier.schemaAt(63);
      final raw = schemaV63.rawDatabase;

      raw.execute('''
        INSERT INTO cliente (id, codigo, nombre_comercial, created_at, updated_at, ciclo_vida_registro)
        VALUES ('cliente-v63', 'CLI-000099', 'Cliente de prueba', 1700000000, 1700000000, 'activo');
      ''');
      raw.execute('''
        INSERT INTO documento_por_emitir (
          id, codigo, cliente_id, tipo_documento, agrupacion, metodo,
          periodo_inicio, periodo_fin, generation_key, importe_base_esperado, importe_final_esperado,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'documento-v63', 'DOC-000099', 'cliente-v63', 'cfdi', 'porServicio', 'PUE',
          1700000000, 1701000000, 'clave-v63', 500000, 500000,
          1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO cuenta_por_cobrar (
          id, documento_por_emitir_id, cliente_id, tipo_documento, metodo,
          fecha_emision_real, importe_emitido, saldo_original, saldo_pendiente, fecha_vencimiento,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'cxc-v63', 'documento-v63', 'cliente-v63', 'cfdi', 'PUE',
          1700500000, 500000, 500000, 500000, 1699000000,
          1700000000, 1700000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV63.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnasCxc = await db.customSelect("PRAGMA table_info('cuenta_por_cobrar')").get();
      expect(
        columnasCxc.map((f) => f.data['name']),
        contains('fecha_cobro_reprogramada'),
        reason: 'CuentaPorCobrar.fechaCobroReprogramada debe existir tras la migración',
      );

      final cxcPreexistente = await (db.select(db.cuentaPorCobrar)..where((t) => t.id.equals('cxc-v63'))).getSingle();
      expect(
        cxcPreexistente.fechaCobroReprogramada,
        isNull,
        reason: 'una CxC histórica nunca tuvo reprogramación — debe quedar null, nunca inferida',
      );
      expect(
        cxcPreexistente.saldoPendiente,
        500000,
        reason: 'ninguna CxC real debe perderse en una migración puramente aditiva',
      );
      expect(cxcPreexistente.fechaVencimiento, DateTime.fromMillisecondsSinceEpoch(1699000000 * 1000));

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 64 → 65 (Etapa "Tiempos Extra") crea las tablas TiempoExtra/'
    'TiempoExtraCostoAdicional/TiempoExtraEvento/NominaEmpleadoAusencia, siembra '
    '12X24 y CodigoSecuencia TEX, y conserva un Empleado y un catálogo de turno reales existentes',
    () async {
      final schemaV64 = await verifier.schemaAt(64);
      final raw = schemaV64.rawDatabase;

      // Catálogo de turno real preexistente — la migración solo agrega
      // 12X24 (`insertOrIgnore`), nunca debe tocar los ya sembrados.
      raw.execute('''
        INSERT INTO tipo_modalidad_turno (id, codigo, nombre, activo)
        VALUES ('turno-24x24-v64', '24X24', '24×24', 1);
      ''');

      // Empleado real preexistente — una migración puramente aditiva
      // (solo tablas nuevas) nunca debe tocarlo.
      raw.execute('''
        INSERT INTO empleado (
          id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
          estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'empleado-v64', 1, 'Juan', 'Pérez', 'masculino', 631152000, 'PEXJ900101HDFXXX01',
          'PEXJ900101AB1', '12345678901', 'soltero', 1700000000, 3, 'activo',
          1700000000, 1700000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV64.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      for (final nombreTabla in [
        'tiempo_extra',
        'tiempo_extra_costo_adicional',
        'tiempo_extra_evento',
        'nomina_empleado_ausencia',
      ]) {
        final tabla = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name = '$nombreTabla'")
            .get();
        expect(tabla, hasLength(1), reason: 'la tabla $nombreTabla debe existir tras la migración');
      }

      final turno12x24 = await (db.select(db.tipoModalidadTurno)..where((t) => t.codigo.equals('12X24'))).getSingleOrNull();
      expect(turno12x24, isNotNull, reason: 'el catálogo de turno 12X24 debe sembrarse en la migración');
      expect(turno12x24!.nombre, '12×24');

      final turno24x24Preexistente =
          await (db.select(db.tipoModalidadTurno)..where((t) => t.id.equals('turno-24x24-v64'))).getSingle();
      expect(
        turno24x24Preexistente.codigo,
        '24X24',
        reason: 'un catálogo de turno real preexistente nunca debe perderse ni duplicarse',
      );

      final empleadoPreexistente = await (db.select(db.empleado)..where((t) => t.id.equals('empleado-v64'))).getSingle();
      expect(
        empleadoPreexistente.nombres,
        'Juan',
        reason: 'ningún Empleado real debe perderse en una migración puramente aditiva',
      );

      final codigoTiempoExtra =
          await (db.select(db.codigoSecuencia)..where((t) => t.entityType.equals('tiempoExtra'))).getSingleOrNull();
      expect(codigoTiempoExtra, isNotNull, reason: 'CodigoSecuencia para "tiempoExtra" debe sembrarse en la migración');
      expect(codigoTiempoExtra!.prefijo, 'TEX');
      expect(codigoTiempoExtra.digitos, 6);

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 65 → 66 ("tarjeta de crédito como línea revolvente") vuelve nullable '
    'importeOriginal/fechaOrigen, agrega fechaSaldoInicial/tarjetaReglaFechaPago/tarjetaDiasDespuesCorte, '
    'y backfillea ambas SIN inventar nada: una TDC real conserva su saldo/importe y hereda su regla '
    '(implícita en tarjetaDiaPago) y su fecha de saldo inicial (real, del MovimientoDeuda altaInicial); '
    'un préstamo real sin esos datos queda con las 3 columnas nuevas en NULL',
    () async {
      final schemaV65 = await verifier.schemaAt(65);
      final raw = schemaV65.rawDatabase;

      // Préstamo real preexistente — nunca tuvo campos de tarjeta ni
      // movimiento de apertura con saldo (alta con saldoInicial == 0,
      // caso real ya soportado desde antes de esta etapa).
      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, fecha_origen, importe_original, saldo_actual, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-prestamo-v65', 'DEU-000001', 'Préstamo refacciones', 'prestamo', 1690000000, 10000000, 10000000, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');

      // Tarjeta de crédito real preexistente — ya tenía tarjetaDiaPago
      // capturado (única regla que existía antes de esta etapa) y un
      // MovimientoDeuda altaInicial real con su propia fecha, distinta
      // de fechaOrigen.
      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, fecha_origen, importe_original, saldo_actual, estatus,
          tarjeta_ultimos_digitos, tarjeta_limite_credito, tarjeta_dia_corte, tarjeta_dia_pago,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-tdc-v65', 'DEU-000002', 'Konfío empresarial', 'tarjetaCredito', 1680000000, 4000000, 3326608, 'activa',
          '4321', 4000000, 17, 7,
          1690000000, 1690000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO movimiento_deuda (
          deuda_id, fecha, tipo, importe, saldo_anterior, saldo_posterior, created_at
        ) VALUES (
          'deuda-tdc-v65', 1701000000, 'altaInicial', 3326608, 0, 3326608, 1701000000
        );
      ''');

      final db = AppDatabase(schemaV65.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnas = await db.customSelect("PRAGMA table_info('deuda')").get();
      final nombresColumnas = columnas.map((f) => f.data['name']).toSet();
      for (final nueva in ['fecha_saldo_inicial', 'tarjeta_regla_fecha_pago', 'tarjeta_dias_despues_corte']) {
        expect(nombresColumnas, contains(nueva), reason: 'Deuda.$nueva debe existir tras la migración');
      }

      final prestamo = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-prestamo-v65'))).getSingle();
      expect(prestamo.importeOriginal, 10000000, reason: 'un préstamo real nunca debe perder su importe original');
      expect(prestamo.saldoActual, 10000000);
      expect(prestamo.fechaOrigen, isNotNull, reason: 'un préstamo real ya tenía fechaOrigen — nunca debe perderse');
      expect(prestamo.fechaSaldoInicial, isNull, reason: 'nunca hubo un MovimientoDeuda altaInicial que backfillar — no se inventa una fecha');
      expect(prestamo.tarjetaReglaFechaPago, isNull, reason: 'un préstamo nunca tuvo tarjetaDiaPago — no se inventa una regla');

      final tarjeta = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-tdc-v65'))).getSingle();
      expect(tarjeta.saldoActual, 3326608, reason: 'el saldo real de la tarjeta nunca debe perderse en la migración');
      expect(tarjeta.tarjetaLimiteCredito, 4000000);
      expect(
        tarjeta.tarjetaReglaFechaPago,
        'diaFijo',
        reason: 'backfill fiel: tarjetaDiaPago ya estaba capturado, así que esa era la única regla implícita posible',
      );
      expect(
        tarjeta.fechaSaldoInicial,
        DateTime.fromMillisecondsSinceEpoch(1701000000 * 1000),
        reason: 'debe backfillarse con la fecha REAL de su propio MovimientoDeuda altaInicial, nunca con fechaOrigen',
      );
      expect(tarjeta.fechaOrigen, isNot(tarjeta.fechaSaldoInicial), reason: 'ambas fechas son conceptualmente distintas y deben seguir siéndolo');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 66 → 67 ("tasa fija/variable y CAT para TDC") agrega 7 columnas nuevas a Deuda '
    'y backfillea tarjetaTipoTasa = fija SOLO para una TDC real que ya tenía tasaInteres capturado — '
    'un préstamo con tasaInteres capturado conserva su valor pero NUNCA recibe tarjetaTipoTasa',
    () async {
      final schemaV66 = await verifier.schemaAt(66);
      final raw = schemaV66.rawDatabase;

      // Préstamo real preexistente con tasaInteres ya capturado —
      // tarjetaTipoTasa es un concepto exclusivo de tarjeta, nunca debe
      // aparecer poblado en una fila de deuda fija.
      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, fecha_origen, importe_original, saldo_actual, tasa_interes, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-prestamo-v66', 'DEU-000003', 'Préstamo refacciones', 'prestamo', 1690000000, 10000000, 10000000, 18.5, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');

      // TDC real preexistente con tasaInteres ya capturado bajo el
      // formulario anterior — la única interpretación posible era una
      // tasa fija (el formulario viejo no distinguía fija/variable).
      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, saldo_actual, tasa_interes, tarjeta_limite_credito, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-tdc-v66', 'DEU-000004', 'TDC BBVA', 'tarjetaCredito', 500000, 24.5, 4000000, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');

      // TDC real preexistente SIN tasaInteres capturado — nunca debe
      // inventarse un tarjetaTipoTasa a partir de la nada.
      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, saldo_actual, tarjeta_limite_credito, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-tdc-sin-tasa-v66', 'DEU-000005', 'TDC Santander', 'tarjetaCredito', 100000, 2000000, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV66.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnas = await db.customSelect("PRAGMA table_info('deuda')").get();
      final nombresColumnas = columnas.map((f) => f.data['name']).toSet();
      for (final nueva in [
        'tarjeta_tipo_tasa',
        'tarjeta_tasa_referencia',
        'tarjeta_tasa_diferencial',
        'tarjeta_tasa_mas_iva',
        'tarjeta_tasa_descripcion',
        'tarjeta_cat',
        'tarjeta_cat_incluye_iva',
      ]) {
        expect(nombresColumnas, contains(nueva), reason: 'Deuda.$nueva debe existir tras la migración');
      }

      final prestamo = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-prestamo-v66'))).getSingle();
      expect(prestamo.tasaInteres, 18.5, reason: 'un préstamo real nunca debe perder su tasaInteres ya capturada');
      expect(prestamo.tarjetaTipoTasa, isNull, reason: 'tarjetaTipoTasa es exclusivo de tarjeta — un préstamo nunca lo recibe');

      final tarjetaConTasa = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-tdc-v66'))).getSingle();
      expect(tarjetaConTasa.tasaInteres, 24.5, reason: 'la tasa ya capturada nunca se pierde ni se reinterpreta');
      expect(
        tarjetaConTasa.tarjetaTipoTasa,
        'fija',
        reason: 'backfill fiel: bajo el formulario anterior, tasaInteres capturado en una TDC solo podía significar una tasa fija',
      );
      expect(tarjetaConTasa.tarjetaTasaReferencia, isNull, reason: 'ningún dato de tasa variable se inventa');
      expect(tarjetaConTasa.tarjetaCat, isNull, reason: 'ningún CAT se inventa — el formulario anterior nunca lo capturaba');

      final tarjetaSinTasa = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-tdc-sin-tasa-v66'))).getSingle();
      expect(tarjetaSinTasa.tasaInteres, isNull);
      expect(tarjetaSinTasa.tarjetaTipoTasa, isNull, reason: 'sin tasaInteres previo, nunca se asume "fija" — se queda no especificada');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 67 → 68 ("ciclo de TDC") agrega tarjetaVencimientoCubiertoHasta a Deuda, sin backfill — '
    'una TDC/préstamo preexistente queda con el campo en null y su comportamiento visible no cambia',
    () async {
      final schemaV67 = await verifier.schemaAt(67);
      final raw = schemaV67.rawDatabase;

      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, fecha_origen, importe_original, saldo_actual, tasa_interes, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-prestamo-v67', 'DEU-000006', 'Préstamo equipo', 'prestamo', 1690000000, 5000000, 5000000, 12.0, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');

      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, saldo_actual, tarjeta_limite_credito, tarjeta_dia_corte,
          tarjeta_regla_fecha_pago, tarjeta_dias_despues_corte, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-tdc-v67', 'DEU-000007', 'TDC Konfío', 'tarjetaCredito', 300000, 5000000, 17,
          'diasDespuesDeCorte', 20, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV67.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnas = await db.customSelect("PRAGMA table_info('deuda')").get();
      final nombresColumnas = columnas.map((f) => f.data['name']).toSet();
      expect(nombresColumnas, contains('tarjeta_vencimiento_cubierto_hasta'),
          reason: 'Deuda.tarjetaVencimientoCubiertoHasta debe existir tras la migración');

      final prestamo = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-prestamo-v67'))).getSingle();
      expect(prestamo.tarjetaVencimientoCubiertoHasta, isNull, reason: 'sin backfill — nunca se inventa un ciclo cubierto');

      final tarjeta = await (db.select(db.deuda)..where((t) => t.id.equals('deuda-tdc-v67'))).getSingle();
      expect(tarjeta.tarjetaVencimientoCubiertoHasta, isNull,
          reason: 'sin backfill — una TDC ya existente queda igual que antes hasta que alguien la concilie o pague');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 68 → 69 ("origen financiero unificado") agrega 6 columnas nuevas (movimiento_deuda ×2, '
    'tiempo_extra ×1, tiempo_extra_costo_adicional ×3), sin backfill — un cargo de TDC ya existente '
    'conserva su compra_id y queda con tiempo_extra_id/costo_adicional_id en null',
    () async {
      final schemaV68 = await verifier.schemaAt(68);
      final raw = schemaV68.rawDatabase;

      // TDC preexistente con un cargo ya vinculado a una Compra —
      // exactamente el shape que ya validaban las pruebas de v66/v67/v68.
      raw.execute('''
        INSERT INTO deuda (
          id, folio, nombre, tipo, saldo_actual, tarjeta_limite_credito, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'deuda-tdc-v68', 'DEU-000008', 'TDC Konfío', 'tarjetaCredito', 500000, 4000000, 'activa',
          1690000000, 1690000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO movimiento_deuda (
          id, deuda_id, fecha, tipo, importe, saldo_anterior, saldo_posterior, created_at
        ) VALUES (
          1, 'deuda-tdc-v68', 1690000000, 'cargoCompra', 500000, 0, 500000, 1690000000
        );
      ''');

      final db = AppDatabase(schemaV68.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnasMovimiento = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
      final nombresMovimiento = columnasMovimiento.map((f) => f.data['name']).toSet();
      expect(nombresMovimiento, containsAll(['tiempo_extra_id', 'costo_adicional_id']));

      final columnasTiempoExtra = await db.customSelect("PRAGMA table_info('tiempo_extra')").get();
      expect(columnasTiempoExtra.map((f) => f.data['name']), contains('deuda_id'));

      final columnasCosto = await db.customSelect("PRAGMA table_info('tiempo_extra_costo_adicional')").get();
      final nombresCosto = columnasCosto.map((f) => f.data['name']).toSet();
      expect(nombresCosto, containsAll(['forma_pago', 'egreso_id', 'deuda_id']));

      final movimiento = await (db.select(db.movimientoDeuda)..where((t) => t.id.equals(1))).getSingle();
      expect(movimiento.tipo, 'cargoCompra', reason: 'el movimiento histórico conserva su tipo/monto/saldo exactamente igual');
      expect(movimiento.importe, 500000);
      expect(movimiento.tiempoExtraId, isNull, reason: 'sin backfill — un movimiento histórico nunca se reasigna a Tiempo Extra');
      expect(movimiento.costoAdicionalId, isNull);

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 69 → 70 (Etapa "corrección real de Tiempo Extra") agrega estadoAnterior/estadoNuevo/eliminado, '
    'y reemplaza personal.gestionarTiemposExtra por 3 permisos separados SIN quitarle acceso a quien ya lo tenía',
    () async {
      final schemaV69 = await verifier.schemaAt(69);
      final raw = schemaV69.rawDatabase;

      raw.execute('''
        INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
        VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
      ''');
      raw.execute('''
        INSERT INTO usuario (
          id, nombre, nombre_usuario, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'usuario-con-permiso-viejo', 'Ana Real', 'ana.real', 'pbkdf2\$1\$AA==\$BB==', 0, 1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO permiso_usuario (usuario_id, codigo)
        VALUES ('usuario-con-permiso-viejo', 'personal.gestionarTiemposExtra');
      ''');

      final db = AppDatabase(schemaV69.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnasEvento = await db.customSelect("PRAGMA table_info('tiempo_extra_evento')").get();
      expect(columnasEvento.map((f) => f.data['name']), containsAll(['estado_anterior', 'estado_nuevo']));

      final columnasCosto = await db.customSelect("PRAGMA table_info('tiempo_extra_costo_adicional')").get();
      expect(columnasCosto.map((f) => f.data['name']), contains('eliminado'));

      final permisos = await (db.select(db.permisoUsuario)..where((t) => t.usuarioId.equals('usuario-con-permiso-viejo'))).get();
      final codigos = permisos.map((p) => p.codigo).toSet();
      expect(
        codigos,
        containsAll(['personal.gestionarTiemposExtra', 'tiempoExtra.crear', 'tiempoExtra.corregir', 'tiempoExtra.cancelar']),
        reason: 'el código viejo se conserva (fila inerte) y los 3 nuevos se otorgan — nadie pierde acceso silenciosamente',
      );
      expect(codigos, isNot(contains('tiempoExtra.eliminarFisicamente')), reason: 'eliminación física nunca es un permiso otorgable');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'migración 70 → 71 (Etapa "1 — Modelo de permisos granular") re-otorga las facultades finas a '
    'todo usuario real que ya tenía el código amplio equivalente, sin quitarle nada y sin tocar al Maestro',
    () async {
      final schemaV70 = await verifier.schemaAt(70);
      final raw = schemaV70.rawDatabase;

      raw.execute('''
        INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
        VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
      ''');

      void sembrarUsuario(String id, String nombre) {
        raw.execute('''
          INSERT INTO usuario (
            id, nombre, nombre_usuario, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
          ) VALUES (
            '$id', '$nombre', '$id', 'pbkdf2\$1\$AA==\$BB==', 0, 1700000000, 1700000000, 'activo'
          );
        ''');
      }

      void otorgar(String usuarioId, String codigo) {
        raw.execute("INSERT INTO permiso_usuario (usuario_id, codigo) VALUES ('$usuarioId', '$codigo');");
      }

      // Usuario real con acceso amplio a Finanzas (los 3 códigos que se
      // retiran del catálogo) — cubre los 7 subdominios nuevos.
      sembrarUsuario('usuario-finanzas', 'Contadora Real');
      otorgar('usuario-finanzas', 'finanzas.crear');
      otorgar('usuario-finanzas', 'finanzas.modificar');
      otorgar('usuario-finanzas', 'finanzas.archivar');

      // Usuario real con acceso amplio a Comercial.
      sembrarUsuario('usuario-comercial', 'Ejecutiva Comercial');
      otorgar('usuario-comercial', 'comercial.crear');
      otorgar('usuario-comercial', 'comercial.modificar');
      otorgar('usuario-comercial', 'comercial.archivar');

      // Usuario real con `nomina.pagar`.
      sembrarUsuario('usuario-nomina', 'Encargado de Nómina');
      otorgar('usuario-nomina', 'nomina.pagar');

      // Usuario real con `personal.gestionarDescuentos`.
      sembrarUsuario('usuario-descuentos', 'RRHH Descuentos');
      otorgar('usuario-descuentos', 'personal.gestionarDescuentos');

      // Usuario real con `inventario.modificar`.
      sembrarUsuario('usuario-inventario', 'Almacenista Real');
      otorgar('usuario-inventario', 'inventario.modificar');

      // Usuario real con los 5 códigos que CONSERVAN su nombre (nunca se
      // retiran del catálogo) pero cuyo alcance se estrecha — la
      // migración solo debe AGREGAR el código nuevo, nunca tocar el viejo.
      sembrarUsuario('usuario-alcance-estrecho', 'Supervisor Operativo');
      otorgar('usuario-alcance-estrecho', 'personal.modificar');
      otorgar('usuario-alcance-estrecho', 'compras.crear');
      otorgar('usuario-alcance-estrecho', 'compras.archivar');
      otorgar('usuario-alcance-estrecho', 'vehiculos.crear');
      otorgar('usuario-alcance-estrecho', 'telefonia.crear');

      // Un Maestro real, SIN ninguna fila de PermisoUsuario (su acceso
      // se recalcula en vivo) — la migración no debe tocarlo ni
      // insertarle nada.
      raw.execute('''
        INSERT INTO usuario (
          id, nombre, nombre_usuario, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'usuario-maestro', 'Maestro Real', 'maestro', 'pbkdf2\$1\$AA==\$BB==', 1, 1700000000, 1700000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV70.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      Future<Set<String>> codigosDe(String usuarioId) async {
        final filas = await (db.select(db.permisoUsuario)..where((t) => t.usuarioId.equals(usuarioId))).get();
        return filas.map((p) => p.codigo).toSet();
      }

      final finanzas = await codigosDe('usuario-finanzas');
      expect(
        finanzas,
        containsAll([
          // Códigos viejos conservados (filas inertes).
          'finanzas.crear', 'finanzas.modificar', 'finanzas.archivar',
          // Otorgados por `finanzas.crear`.
          'ingresos.crear', 'egresos.crear', 'deudas.crear', 'deudas.registrarPago', 'pagos.registrar',
          'cuentasFinancieras.crear', 'categoriasFinancieras.crear',
          // Otorgados por `finanzas.modificar`.
          'ingresos.corregir', 'egresos.corregir', 'deudas.corregir', 'pagos.corregir',
          'cuentasFinancieras.corregir', 'cuentasFinancieras.cambiarEstatus', 'categoriasFinancieras.corregir',
          'cuentaPorCobrar.corregirFecha', 'cuentaPorCobrar.reprogramarCobro',
          // Otorgados por `finanzas.archivar`.
          'ingresos.cancelar', 'egresos.cancelar', 'deudas.cancelar', 'pagos.cancelar', 'pagos.cancelarAplicacion',
          'categoriasFinancieras.archivar',
        ]),
        reason: 'nadie pierde ninguna facultad que ya tenía bajo los 3 códigos amplios de Finanzas',
      );

      final comercial = await codigosDe('usuario-comercial');
      expect(
        comercial,
        containsAll([
          'comercial.crear', 'comercial.modificar', 'comercial.archivar',
          'clientes.crear', 'servicios.crear', 'configuracionCobro.crear', 'agendaComercial.crear',
          'clientes.corregir', 'servicios.corregir', 'configuracionCobro.corregir', 'agendaComercial.corregir',
          'clientes.archivar',
        ]),
      );

      final nomina = await codigosDe('usuario-nomina');
      expect(
        nomina,
        containsAll(['nomina.pagar', 'nomina.registrarPago', 'nomina.corregirPago', 'nomina.cancelarPago']),
      );

      final descuentos = await codigosDe('usuario-descuentos');
      expect(
        descuentos,
        containsAll([
          'personal.gestionarDescuentos',
          'descuentos.ver', 'descuentos.crear', 'descuentos.corregir', 'descuentos.cancelar',
        ]),
        reason: 'descuentos.ver es nuevo — antes Descuentos no tenía ningún guardia de lectura propio',
      );

      final inventario = await codigosDe('usuario-inventario');
      expect(inventario, containsAll(['inventario.modificar', 'inventario.corregir', 'inventario.ajustarExistencia']));

      final estrecho = await codigosDe('usuario-alcance-estrecho');
      expect(
        estrecho,
        containsAll([
          // Los 5 códigos viejos permanecen EXACTAMENTE (nunca se retiran
          // del catálogo, solo se estrecha su alcance en el código).
          'personal.modificar', 'compras.crear', 'compras.archivar', 'vehiculos.crear', 'telefonia.crear',
          // Y cada uno gana el código nuevo que separó la facultad que
          // antes venía incluida.
          'personal.archivar', 'compras.corregir', 'compras.cancelar', 'vehiculos.operar', 'telefonia.recargar',
        ]),
        reason: 'los códigos que conservan su nombre nunca se tocan — solo se agrega el nuevo',
      );

      // Ningún usuario recibe jamás un código de eliminación física —
      // esa facultad nunca es otorgable vía `PermisoUsuario`.
      final todosLosCodigosOtorgados = {...finanzas, ...comercial, ...nomina, ...descuentos, ...inventario, ...estrecho};
      expect(todosLosCodigosOtorgados.where((c) => c.toLowerCase().contains('fisicamente')), isEmpty);

      final maestro = await codigosDe('usuario-maestro');
      expect(maestro, isEmpty, reason: 'un Maestro nunca tiene filas de PermisoUsuario — la migración no lo toca');

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test('migración 70 → 71 es idempotente — correrla dos veces no duplica ninguna fila ni falla', () async {
    final schemaV70 = await verifier.schemaAt(70);
    final raw = schemaV70.rawDatabase;

    raw.execute('''
      INSERT INTO app_metadata (installation_id, installed_at, app_version, last_opened_at)
      VALUES ('instalacion-real-existente', 1700000000, '1.0.0+1', 1700000000);
    ''');
    raw.execute('''
      INSERT INTO usuario (
        id, nombre, nombre_usuario, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'usuario-repetido', 'Usuario Repetido', 'repetido', 'pbkdf2\$1\$AA==\$BB==', 0, 1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute("INSERT INTO permiso_usuario (usuario_id, codigo) VALUES ('usuario-repetido', 'nomina.pagar');");

    final db = AppDatabase(schemaV70.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    // Reejecutar la migración de datos directamente sobre la BD ya
    // migrada (simula lo que pasaría si `onUpgrade` corriera dos veces
    // sobre el mismo rango de versiones) — nunca debe duplicar filas ni
    // violar la llave primaria `(usuario_id, codigo)`.
    await migrarPermisosGranularesV71(db, db.createMigrator());

    final filas =
        await (db.select(db.permisoUsuario)..where((t) => t.usuarioId.equals('usuario-repetido'))).get();
    final codigos = filas.map((p) => p.codigo).toList();
    expect(codigos.toSet().length, codigos.length, reason: 'ninguna fila duplicada tras correr la migración dos veces');
    expect(
      codigos.toSet(),
      {'nomina.pagar', 'nomina.registrarPago', 'nomina.corregirPago', 'nomina.cancelarPago'},
    );

    await db.close();
  });

  test(
    'migración 73 → 74 (Etapa 7, Cuentas por cobrar) re-otorga cuentaPorCobrar.corregir a todo usuario real que '
    'ya tenía cuentaPorCobrar.corregirFecha, sin quitarle nada, y es idempotente',
    () async {
      final schemaV73 = await verifier.schemaAt(73);
      final raw = schemaV73.rawDatabase;

      raw.execute('''
        INSERT INTO usuario (
          id, nombre, nombre_usuario, password_hash, es_maestro, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'usuario-cxc', 'Cobranza Real', 'cobranza', 'pbkdf2\$1\$AA==\$BB==', 0, 1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute("INSERT INTO permiso_usuario (usuario_id, codigo) VALUES ('usuario-cxc', 'cuentaPorCobrar.corregirFecha');");
      raw.execute("INSERT INTO permiso_usuario (usuario_id, codigo) VALUES ('usuario-cxc', 'cuentaPorCobrar.reprogramarCobro');");

      final db = AppDatabase(schemaV73.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final codigos = (await (db.select(db.permisoUsuario)..where((t) => t.usuarioId.equals('usuario-cxc'))).get())
          .map((p) => p.codigo)
          .toSet();
      expect(
        codigos,
        {'cuentaPorCobrar.corregirFecha', 'cuentaPorCobrar.reprogramarCobro', 'cuentaPorCobrar.corregir'},
        reason: 'el código viejo se conserva inerte, reprogramarCobro no cambia, corregir se agrega',
      );

      // Idempotencia: reejecutar la migración de datos directamente no
      // debe duplicar ninguna fila ni violar la llave primaria.
      await migrarCorreccionCuentaPorCobrarV74(db, db.createMigrator());
      final codigosTrasRepetir =
          (await (db.select(db.permisoUsuario)..where((t) => t.usuarioId.equals('usuario-cxc'))).get())
              .map((p) => p.codigo)
              .toList();
      expect(codigosTrasRepetir.toSet().length, codigosTrasRepetir.length, reason: 'ninguna fila duplicada');

      await db.close();
    },
  );

  test(
    'migración 74 → 75 (Etapa "Cierre del ciclo financiero de Descuentos Programados") agrega '
    'cuentaFinancieraId/egresoId nullable a descuento_programado_empleado, sin backfill sobre un préstamo histórico',
    () async {
      final schemaV74 = await verifier.schemaAt(74);

      // Inserta vía el Companion actual (`cuentaFinancieraId`/`egresoId`
      // ausentes → `Value.absent()` → el SQL generado no referencia esas
      // columnas, compatibles con la tabla física en su forma v74).
      final dbV74 = AppDatabase(schemaV74.newConnection());
      final empleado = await dbV74.into(dbV74.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 9001,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ90010101',
              nss: '10000000001',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      final prestamoHistorico = await dbV74.into(dbV74.descuentoProgramadoEmpleado).insertReturning(
            DescuentoProgramadoEmpleadoCompanion.insert(
              folio: 'PRE-000001',
              empleadoId: empleado.id,
              tipo: 'prestamo',
              fechaRegistro: DateTime(2026, 1, 1),
              importeOriginal: 500000,
              saldoPendiente: 300000,
            ),
          );
      await dbV74.close();

      final db = AppDatabase(schemaV74.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnas = await db.customSelect("PRAGMA table_info('descuento_programado_empleado')").get();
      final nombresColumnas = columnas.map((f) => f.data['name']).toSet();
      expect(nombresColumnas, containsAll(['cuenta_financiera_id', 'egreso_id']));

      final actual = await (db.select(db.descuentoProgramadoEmpleado)..where((t) => t.id.equals(prestamoHistorico.id))).getSingle();
      expect(actual.importeOriginal, 500000, reason: 'un préstamo histórico no se altera por esta migración');
      expect(actual.saldoPendiente, 300000);
      expect(actual.cuentaFinancieraId, isNull, reason: 'sin backfill — nunca se asume retroactivamente un origen financiero');
      expect(actual.egresoId, isNull);

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test(
    'migración 75 → 76 (Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC") agrega '
    'egreso.deuda_id y movimiento_deuda.egreso_gasto_id, sin backfill sobre un Egreso histórico con formaPago tarjeta',
    () async {
      final schemaV75 = await verifier.schemaAt(75);

      // El caso real que motivó la etapa, tal como está hoy en la
      // instalación de producción: un gasto pagado con la TDC pero
      // capturado como Egreso contra una cuenta bancaria, con
      // `formaPago: 'tarjeta'` como única (y falsa) pista del origen.
      final dbV75 = AppDatabase(schemaV75.newConnection());
      final cuenta = await dbV75.into(dbV75.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CTA-0002',
              nombre: 'Klar Empresarial',
              tipo: 'banco',
              saldoInicial: 1747177,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );
      final tarjeta = await dbV75.into(dbV75.deuda).insertReturning(
            DeudaCompanion.insert(
              folio: 'DEU-000007',
              nombre: 'TDC Konfío Empresarial',
              tipo: 'tarjetaCredito',
              saldoActual: 3326608,
              tarjetaLimiteCredito: const Value(4000000),
            ),
          );
      final gasolina = await dbV75.into(dbV75.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: 'EGR-000035',
              monto: 135998,
              fecha: DateTime(2026, 3, 5),
              cuentaFinancieraId: Value(cuenta.id),
              formaPago: 'tarjeta',
              concepto: 'gasolina',
            ),
          );
      await dbV75.close();

      final db = AppDatabase(schemaV75.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnasEgreso = await db.customSelect("PRAGMA table_info('egreso')").get();
      expect(columnasEgreso.map((f) => f.data['name']).toSet(), contains('deuda_id'));
      final columnasMovimiento = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
      expect(columnasMovimiento.map((f) => f.data['name']).toSet(), contains('egreso_gasto_id'));

      final actual = await (db.select(db.egreso)..where((t) => t.id.equals(gasolina.id))).getSingle();
      expect(actual.monto, 135998, reason: 'el gasto histórico no se altera');
      expect(actual.formaPago, 'tarjeta', reason: 'la etiqueta se conserva tal cual, nunca se reinterpreta');
      expect(actual.cuentaFinancieraId, cuenta.id, reason: 'su efecto actual sobre Caja y bancos se respeta hasta que el usuario lo corrija');
      expect(
        actual.deudaId,
        isNull,
        reason: 'SIN backfill: nada en la fila dice CUÁL tarjeta lo financió, y adivinarla por concepto/monto/fecha '
            'sería exactamente la heurística que este proyecto nunca aplica',
      );

      final tarjetaDespues = await (db.select(db.deuda)..where((t) => t.id.equals(tarjeta.id))).getSingle();
      expect(tarjetaDespues.saldoActual, 3326608, reason: 'la TDC no recibe ningún cargo retroactivo');
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test('migración 75 → 76 es idempotente — correrla dos veces no falla ni duplica columnas', () async {
    final schemaV75 = await verifier.schemaAt(75);
    final db = AppDatabase(schemaV75.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    // Segunda pasada explícita sobre la MISMA base ya migrada: cada
    // `addColumn` está guardado por su `PRAGMA table_info`, así que
    // repetirla es un no-op (nunca un "duplicate column name").
    await migrarEgresoOrigenTarjetaV76(db, Migrator(db));

    final columnas = await db.customSelect("PRAGMA table_info('egreso')").get();
    expect(columnas.where((f) => f.data['name'] == 'deuda_id'), hasLength(1));

    await db.close();
  });

  test(
    'migración 76 → 77 (Etapa 9, "corrección y cancelación individual de pagos") agrega '
    'movimiento_origen_id y tarjeta_vencimiento_cubierto_anterior, sin backfill sobre un pago histórico',
    () async {
      final schemaV76 = await verifier.schemaAt(76);

      // Un pago histórico real (el único que existe hoy en la
      // instalación: un préstamo, nunca una tarjeta) y un cargo de
      // gasto con TDC — las dos relaciones que esta etapa NO debe
      // confundir jamás: `egreso_id` (Egreso del PAGO) vs.
      // `egreso_gasto_id` (Egreso-documento de un GASTO con tarjeta).
      final dbV76 = AppDatabase(schemaV76.newConnection());
      final deuda = await dbV76.into(dbV76.deuda).insertReturning(
            DeudaCompanion.insert(
              folio: 'DEU-000001',
              nombre: 'SANDRA PRESTAMO PERSONAL',
              tipo: 'prestamo',
              saldoActual: 2700000,
            ),
          );
      final egresoDelPago = await dbV76.into(dbV76.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: 'EGR-000100',
              monto: 300000,
              fecha: DateTime(2026, 3, 5),
              formaPago: 'transferencia',
              concepto: 'Pago de deuda DEU-000001',
            ),
          );
      final pagoHistorico = await dbV76.into(dbV76.movimientoDeuda).insertReturning(
            MovimientoDeudaCompanion.insert(
              deudaId: deuda.id,
              fecha: DateTime(2026, 3, 5),
              tipo: 'pago',
              importe: 300000,
              saldoAnterior: 3000000,
              saldoPosterior: 2700000,
              egresoId: Value(egresoDelPago.id),
            ),
          );
      await dbV76.close();

      final db = AppDatabase(schemaV76.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      final columnas = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
      final nombres = columnas.map((f) => f.data['name']).toSet();
      expect(nombres, containsAll(['movimiento_origen_id', 'tarjeta_vencimiento_cubierto_anterior']));

      final actual = await (db.select(db.movimientoDeuda)..where((t) => t.id.equals(pagoHistorico.id))).getSingle();
      expect(actual.importe, 300000, reason: 'un pago histórico no se altera por esta migración');
      expect(actual.saldoAnterior, 3000000);
      expect(actual.saldoPosterior, 2700000);
      expect(actual.egresoId, egresoDelPago.id, reason: 'el Egreso del PAGO se conserva en egresoId');
      expect(actual.egresoGastoId, isNull, reason: 'nunca se confunde con el Egreso de un GASTO');
      expect(
        actual.movimientoOrigenId,
        isNull,
        reason: 'sin backfill: hasta esta etapa no existía ninguna corrección de pago, '
            'así que ningún ajuste preexistente pertenece a un pago',
      );
      expect(
        actual.tarjetaVencimientoCubiertoAnterior,
        isNull,
        reason: 'el ancla previa de un avance ya ocurrido no está registrada en ninguna parte; '
            'deducirla sería inventarla',
      );

      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty, reason: 'foreign_key_check debe quedar limpio tras la migración');

      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok'], reason: 'integrity_check debe reportar "ok" tras la migración');

      await db.close();
    },
  );

  test('migración 76 → 77 es idempotente — correrla dos veces no falla ni duplica columnas', () async {
    final schemaV76 = await verifier.schemaAt(76);
    final db = AppDatabase(schemaV76.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    await migrarCorreccionPagoDeudaV77(db, Migrator(db));

    final columnas = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
    expect(columnas.where((f) => f.data['name'] == 'movimiento_origen_id'), hasLength(1));

    await db.close();
  });

  test(
    'migración 78 → 79 (Complemento sustituto) conserva TODOS los Complementos existentes '
    'y cambia el UNIQUE de columna por un índice único parcial',
    () async {
      final schemaV78 = await verifier.schemaAt(78);
      final dbV78 = AppDatabase(schemaV78.newConnection());

      // Un Pago con su Complemento, tal como existe hoy en la
      // instalación real (1 Complemento registrado).
      final cliente = await dbV78.into(dbV78.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-MIG79', nombreComercial: 'MORGAN'),
          );
      final pago = await dbV78.into(dbV78.pago).insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-MIG79',
              clienteId: Value(cliente.id),
              montoTotal: 10000000,
              fechaPago: DateTime(2026, 10, 12),
              formaPago: 'transferencia',
            ),
          );
      final complemento = await dbV78.into(dbV78.complementoPago).insertReturning(
            ComplementoPagoCompanion.insert(
              pagoId: pago.id,
              uuid: 'eeeeeeee-1111-2222-3333-444444444444',
              fechaTimbrado: DateTime(2026, 10, 15),
              montoTotal: 10000000,
            ),
          );
      await dbV78.close();

      // Migra con el código real del proyecto.
      final db = AppDatabase(schemaV78.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // 1. El Complemento sobrevivió intacto, con su mismo `id`.
      final conservado = await (db.select(db.complementoPago)..where((t) => t.id.equals(complemento.id))).getSingle();
      expect(conservado.uuid, 'eeeeeeee-1111-2222-3333-444444444444');
      expect(conservado.pagoId, pago.id);
      expect(conservado.montoTotal, 10000000);
      expect(conservado.estatus, 'registrado');

      // 2. El índice único PARCIAL existe.
      final indice = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name='complemento_pago_vigente_por_pago'",
          )
          .get();
      expect(indice, hasLength(1));
      expect(indice.single.data['sql'] as String, contains("WHERE estatus = 'registrado'"));

      // 3. Ya se puede cancelar y registrar un sustituto — el gap que
      //    motivó la migración.
      await (db.update(db.complementoPago)..where((t) => t.id.equals(complemento.id)))
          .write(const ComplementoPagoCompanion(estatus: Value('cancelado')));
      await db.into(db.complementoPago).insert(
            ComplementoPagoCompanion.insert(
              pagoId: pago.id,
              uuid: 'ffffffff-1111-2222-3333-444444444444',
              fechaTimbrado: DateTime(2026, 10, 20),
              montoTotal: 10000000,
            ),
          );
      final historial = await (db.select(db.complementoPago)..where((t) => t.pagoId.equals(pago.id))).get();
      expect(historial, hasLength(2), reason: 'el cancelado se conserva y el sustituto se agrega');

      // 4. Pero DOS vigentes siguen siendo imposibles.
      await expectLater(
        db.into(db.complementoPago).insert(
              ComplementoPagoCompanion.insert(
                pagoId: pago.id,
                uuid: '99999999-1111-2222-3333-444444444444',
                fechaTimbrado: DateTime(2026, 10, 25),
                montoTotal: 10000000,
              ),
            ),
        throwsA(anything),
      );

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty, reason: 'recrear la tabla no puede romper ninguna FK');

      await db.close();
    },
  );

  test(
    'migración 79 → 80 (Etapa "Vehículos: ciclo de vida, gastos, origen financiero y trazabilidad") '
    'conserva el mantenimiento histórico con costo y SIN origen financiero — cero backfill heurístico — '
    'y crea VehiculoEvento vacía',
    () async {
      final schemaV79 = await verifier.schemaAt(79);
      final dbV79 = AppDatabase(schemaV79.newConnection());

      // El caso REAL de la instalación: 1 mantenimiento de $3,800 con
      // costo capturado y ningún origen financiero, porque en la v79 el
      // concepto todavía no existía.
      final vehiculo = await dbV79.into(dbV79.vehiculo).insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-000001',
              marca: 'Nissan',
              modelo: 'NP300',
              tipoVehiculo: 'pickup',
              placas: const Value('ABC-123'),
              vin: const Value('VIN-REAL-0001'),
              costoAdquisicion: const Value(30000000),
            ),
          );
      final mantenimiento = await dbV79.into(dbV79.vehiculoMantenimiento).insertReturning(
            VehiculoMantenimientoCompanion.insert(
              vehiculoId: vehiculo.id,
              fecha: DateTime(2026, 3, 18),
              tipo: 'servicioGeneral',
              descripcion: 'Afinación mayor',
              costo: const Value(380000),
            ),
          );
      await dbV79.close();

      final db = AppDatabase(schemaV79.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // 1. La fila histórica sobrevive EXACTAMENTE como estaba: mismo
      //    id, mismo costo, y los dos orígenes en NULL. Inventarle una
      //    cuenta sería fabricar un hecho financiero que nadie registró.
      final conservado =
          await (db.select(db.vehiculoMantenimiento)..where((t) => t.id.equals(mantenimiento.id))).getSingle();
      expect(conservado.costo, 380000);
      expect(conservado.descripcion, 'Afinación mayor');
      expect(conservado.egresoId, isNull, reason: 'gasto histórico sin origen especificado, NO un backfill inventado');
      expect(conservado.deudaId, isNull);
      expect(conservado.estatus, 'registrado', reason: 'lo histórico está registrado, que es lo que efectivamente es');
      expect(conservado.motivoCancelacion, isNull);

      // 2. Ese gasto histórico NO se convirtió en un Egreso — si lo
      //    hiciera, el saldo de alguna cuenta cambiaría solo por migrar.
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);

      // 3. El Vehículo tampoco se tocó: `costoAdquisicion` es valor del
      //    activo, no un gasto del periodo.
      final vehiculoConservado = await (db.select(db.vehiculo)..where((t) => t.id.equals(vehiculo.id))).getSingle();
      expect(vehiculoConservado.costoAdquisicion, 30000000);
      expect(vehiculoConservado.vin, 'VIN-REAL-0001');

      // 4. El historial nace vacío — nunca eventos retroactivos
      //    fabricados para hechos que nadie presenció.
      expect(await db.select(db.vehiculoEvento).get(), isEmpty);

      // 5. El índice único PARCIAL sobre egreso_id existe (no se pudo
      //    declarar como UNIQUE de columna: SQLite rechaza
      //    `ALTER TABLE … ADD COLUMN … UNIQUE`).
      final indice = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name='vehiculo_mantenimiento_egreso_unico'",
          )
          .get();
      expect(indice, hasLength(1));
      expect(indice.single.data['sql'] as String, contains('WHERE egreso_id IS NOT NULL'));

      // 6. Y el cargo de TDC ya puede apuntar a su mantenimiento.
      final movimiento = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
      expect(
        movimiento.map((f) => f.data['name'] as String),
        contains('vehiculo_mantenimiento_id'),
      );

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);

      await db.close();
    },
  );

  test(
    'migración 79 → 80 es idempotente — correrla dos veces no falla ni duplica columnas ni el índice',
    () async {
      final schemaV79 = await verifier.schemaAt(79);
      final db = AppDatabase(schemaV79.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // Segunda pasada con el mismo código real de la migración.
      await migrarVehiculosOrigenFinancieroV80(db, db.createMigrator());

      final columnas = await db.customSelect("PRAGMA table_info('vehiculo_mantenimiento')").get();
      final nombres = columnas.map((f) => f.data['name'] as String).toList();
      expect(nombres.where((n) => n == 'egreso_id'), hasLength(1));
      expect(nombres.where((n) => n == 'estatus'), hasLength(1));

      final indices = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='vehiculo_mantenimiento_egreso_unico'",
          )
          .get();
      expect(indices, hasLength(1));

      await db.close();
    },
  );

  test(
    'migración 80 → 81 (Etapa "Telefonía: trazabilidad y ciclo de la recarga") conserva la línea y la '
    'recarga históricas, crea LineaTelefonicaEvento vacía y deja toda recarga previa como registrada',
    () async {
      final schemaV80 = await verifier.schemaAt(80);
      final dbV80 = AppDatabase(schemaV80.newConnection());

      final linea = await dbV80.into(dbV80.lineaTelefonica).insertReturning(
            LineaTelefonicaCompanion.insert(
              codigo: 'LIN-000004',
              operador: 'telcel',
              modalidadSim: 'fisica',
              numero: const Value('5512345678'),
              iccid: const Value('8952140061234567890'),
            ),
          );
      final recarga = await dbV80.into(dbV80.recargaLineaTelefonica).insertReturning(
            RecargaLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: linea.id,
              fecha: DateTime(2026, 5, 20),
              importe: 50000,
              observaciones: const Value('Recarga de mayo'),
            ),
          );
      await dbV80.close();

      final db = AppDatabase(schemaV80.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // 1. La recarga histórica sobrevive intacta y queda REGISTRADA,
      //    que es exactamente lo que es. Cero backfill inventado.
      final conservada =
          await (db.select(db.recargaLineaTelefonica)..where((t) => t.id.equals(recarga.id))).getSingle();
      expect(conservada.importe, 50000);
      expect(conservada.observaciones, 'Recarga de mayo');
      expect(conservada.estatus, 'registrada');
      expect(conservada.motivoCancelacion, isNull);

      // 2. La línea tampoco se toca: número e ICCID siguen tal cual en
      //    la ENTIDAD (lo que se enmascara es el diff de auditoría, no
      //    el dato operativo).
      final lineaConservada = await (db.select(db.lineaTelefonica)..where((t) => t.id.equals(linea.id))).getSingle();
      expect(lineaConservada.numero, '5512345678');
      expect(lineaConservada.iccid, '8952140061234567890');

      // 3. El historial nace vacío — nunca eventos retroactivos
      //    fabricados para hechos que nadie presenció.
      expect(await db.select(db.lineaTelefonicaEvento).get(), isEmpty);

      // 4. Y la migración NO inventó ningún movimiento de dinero:
      //    Telefonía sigue sin Egreso, decisión deliberada de la 9C.
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);

      await db.close();
    },
  );

  test(
    'migración 80 → 81 es idempotente — correrla dos veces no falla ni duplica columnas',
    () async {
      final schemaV80 = await verifier.schemaAt(80);
      final db = AppDatabase(schemaV80.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      await migrarTelefoniaTrazabilidadV81(db, db.createMigrator());

      final columnas = await db.customSelect("PRAGMA table_info('recarga_linea_telefonica')").get();
      final nombres = columnas.map((f) => f.data['name'] as String).toList();
      expect(nombres.where((n) => n == 'estatus'), hasLength(1));
      expect(nombres.where((n) => n == 'motivo_cancelacion'), hasLength(1));

      final tablas = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='linea_telefonica_evento'")
          .get();
      expect(tablas, hasLength(1));

      await db.close();
    },
  );

  test(
    'migración 81 → 82 (Etapa "Baja de empleado: activos pendientes") conserva las asignaciones existentes '
    'y NO marca retroactivamente nada como pendiente de recuperación',
    () async {
      final schemaV81 = await verifier.schemaAt(81);
      final dbV81 = AppDatabase(schemaV81.newConnection());

      final categoria = await dbV81.into(dbV81.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Equipo'),
          );
      final articulo = await dbV81.into(dbV81.articulo).insertReturning(
            ArticuloCompanion.insert(
              folio: 'ART-000001',
              nombre: 'Radio',
              categoriaId: categoria.id,
              manejaSerie: const Value(true),
            ),
          );
      final empleado = await dbV81.into(dbV81.empleado).insertReturning(
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
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      final asignacion = await dbV81.into(dbV81.asignacion).insertReturning(
            AsignacionCompanion.insert(
              articuloId: articulo.id,
              cantidad: 1,
              empleadoId: Value(empleado.id),
              fechaEntrega: DateTime(2026, 2, 1),
            ),
          );
      final vehiculo = await dbV81.into(dbV81.vehiculo).insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-000001',
              marca: 'Nissan',
              modelo: 'NP300',
              tipoVehiculo: 'pickup',
            ),
          );
      final asignacionVehiculo = await dbV81.into(dbV81.asignacionVehiculo).insertReturning(
            AsignacionVehiculoCompanion.insert(
              vehiculoId: vehiculo.id,
              empleadoId: Value(empleado.id),
              fechaInicio: DateTime(2026, 2, 1),
            ),
          );
      await dbV81.close();

      final db = AppDatabase(schemaV81.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // 1. Las asignaciones históricas sobreviven intactas y quedan como
      //    asignaciones NORMALES — que es lo que son. Cero backfill:
      //    marcar retroactivamente como pendiente algo que nadie decidió
      //    en su momento sería inventar un hecho administrativo.
      final conservada = await (db.select(db.asignacion)..where((t) => t.id.equals(asignacion.id))).getSingle();
      expect(conservada.empleadoId, empleado.id);
      expect(conservada.estatus, 'activa');
      expect(conservada.pendienteRecuperacionDesde, isNull);

      final vehiculoConservado =
          await (db.select(db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculo.id))).getSingle();
      expect(vehiculoConservado.empleadoId, empleado.id);
      expect(vehiculoConservado.fechaTermino, isNull);
      expect(vehiculoConservado.pendienteRecuperacionDesde, isNull);

      // 2. Y la migración NO inventó ninguna devolución: cero
      //    movimientos de inventario nuevos.
      expect(await db.select(db.movimientoInventario).get(), isEmpty);

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);

      await db.close();
    },
  );

  test(
    'migración 81 → 82 es idempotente — correrla dos veces no falla ni duplica columnas',
    () async {
      final schemaV81 = await verifier.schemaAt(81);
      final db = AppDatabase(schemaV81.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      await migrarPendienteRecuperacionV82(db, db.createMigrator());

      for (final tabla in ['asignacion', 'asignacion_vehiculo']) {
        final columnas = await db.customSelect("PRAGMA table_info('$tabla')").get();
        final nombres = columnas.map((f) => f.data['name'] as String).toList();
        expect(nombres.where((n) => n == 'pendiente_recuperacion_desde'), hasLength(1));
      }

      await db.close();
    },
  );

  test(
    'migración 82 → 83 (Etapa "Baja laboral con conciliación obligatoria") crea las tablas de conciliación '
    'vacías, siembra el folio RES y NO inventa una conciliación para las bajas anteriores',
    () async {
      final schemaV82 = await verifier.schemaAt(82);
      final dbV82 = AppDatabase(schemaV82.newConnection());

      // Una baja YA registrada bajo el régimen de la v82: con su bien
      // marcado como pendiente automáticamente.
      final categoria = await dbV82.into(dbV82.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Equipo'),
          );
      final articulo = await dbV82.into(dbV82.articulo).insertReturning(
            ArticuloCompanion.insert(folio: 'ART-000001', nombre: 'Radio', categoriaId: categoria.id),
          );
      final empleado = await dbV82.into(dbV82.empleado).insertReturning(
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
              fechaIngreso: DateTime(2024, 1, 1),
              aniosExperienciaSeguridad: 3,
              estatus: const Value('baja'),
              fechaBaja: Value(DateTime(2025, 6, 30)),
              motivoBaja: const Value('renuncia'),
            ),
          );
      final asignacion = await dbV82.into(dbV82.asignacion).insertReturning(
            AsignacionCompanion.insert(
              articuloId: articulo.id,
              cantidad: 1,
              empleadoId: Value(empleado.id),
              fechaEntrega: DateTime(2025, 2, 1),
              pendienteRecuperacionDesde: Value(DateTime(2025, 6, 30)),
            ),
          );
      await dbV82.close();

      final db = AppDatabase(schemaV82.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      // 1. Las tablas nuevas nacen VACÍAS: a una baja anterior nadie la
      //    concilió, y fabricarle una conciliación ahora sería afirmar
      //    decisiones que nadie tomó.
      expect(await db.select(db.conciliacionBaja).get(), isEmpty);
      expect(await db.select(db.conciliacionBajaRenglon).get(), isEmpty);

      // 2. El pendiente de la v82 sigue intacto y sigue siendo válido.
      final conservada = await (db.select(db.asignacion)..where((t) => t.id.equals(asignacion.id))).getSingle();
      expect(conservada.pendienteRecuperacionDesde, DateTime(2025, 6, 30));
      expect(conservada.estatus, 'activa');

      // 3. El folio propio de las obligaciones de resguardo existe.
      final secuencia = await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('descuentoProgramadoResguardo')))
          .getSingle();
      expect(secuencia.prefijo, 'RES');

      // 4. Y la migración no inventó ninguna obligación económica.
      expect(await db.select(db.descuentoProgramadoEmpleado).get(), isEmpty);

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);

      await db.close();
    },
  );

  test(
    'migración 82 → 83 es idempotente — correrla dos veces no falla ni duplica la secuencia de folio',
    () async {
      final schemaV82 = await verifier.schemaAt(82);
      final db = AppDatabase(schemaV82.newConnection());
      await verifier.migrateAndValidate(db, _currentSchemaVersion);

      await migrarConciliacionBajaV83(db, db.createMigrator());

      final secuencias = await (db.select(db.codigoSecuencia)
            ..where((t) => t.entityType.equals('descuentoProgramadoResguardo')))
          .get();
      expect(secuencias, hasLength(1));

      await db.close();
    },
  );
  test(
    'migración 83 → 84 (Etapa "Trazabilidad de Comercial") crea las tres bitácoras VACÍAS, con sus índices, '
    'y no inventa eventos para lo que ya existía',
    () async {
      final schemaV83 = await verifier.schemaAt(83);
      final dbV83 = AppDatabase(schemaV83.newConnection());

      // Datos que YA existían antes de que Comercial tuviera bitácora.
      final cliente = await dbV83.into(dbV83.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
      );
      await dbV83.close();

      // Abrir con la versión actual dispara el onUpgrade real.
      final db = AppDatabase(schemaV83.newConnection());
      await db.select(db.cliente).get();

      // 1. Las tres tablas nacen VACÍAS. Nadie registró quién hizo los
      //    cambios anteriores, y fabricar un actor o un motivo ahora
      //    sería afirmar cosas que nunca ocurrieron.
      expect(await db.select(db.clienteEvento).get(), isEmpty);
      expect(await db.select(db.servicioEvento).get(), isEmpty);
      expect(await db.select(db.configuracionCobroEvento).get(), isEmpty);

      // 2. Los datos existentes quedan intactos.
      final conservado = await (db.select(db.cliente)..where((t) => t.id.equals(cliente.id))).getSingle();
      expect(conservado.nombreComercial, 'Sportium');

      // 3. Los índices existen: es como consulta la Auditoría central
      //    (por fecha) y el expediente de cada registro (por entidad).
      final indices = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%evento%'",
      ).get();
      final nombres = indices.map((f) => f.data['name'] as String).toSet();
      expect(nombres, containsAll(<String>[
        'idx_cliente_evento_cliente_fecha',
        'idx_cliente_evento_fecha',
        'idx_servicio_evento_servicio_fecha',
        'idx_servicio_evento_fecha',
        'idx_configuracion_cobro_evento_config_fecha',
        'idx_configuracion_cobro_evento_fecha',
      ]));

      await db.close();
    },
  );

  test(
    'migración 83 → 84 es idempotente — correrla dos veces no falla ni duplica índices',
    () async {
      final schemaV83 = await verifier.schemaAt(83);
      final db = AppDatabase(schemaV83.newConnection());
      await db.select(db.cliente).get();

      await migrarTrazabilidadComercialV84(db, db.createMigrator());
      await migrarTrazabilidadComercialV84(db, db.createMigrator());

      expect(await db.select(db.clienteEvento).get(), isEmpty);
      await db.close();
    },
  );

  /// Etapa "Tiempo Extra: origen de cobertura" (84 → 85).
  ///
  /// Lo que protege: que una instalación real con Tiempos Extra ya
  /// capturados sobreviva a volver nullable \
  /// `empleado_ausente_id`/`motivo_ausencia` y que TODO
  /// lo histórico quede clasificado como `ausenciaEmpleado` — que es lo
  /// que era por construcción del esquema anterior, no una inferencia.
  ///
  /// Se siembra con SQL crudo sobre el esquema v83 (`rawDatabase`),
  /// nunca con las clases Dart actuales: esas ya tienen la forma nueva y
  /// la prueba dejaría de demostrar nada.
  test(
    'migración 84 → 85 (Etapa "origen de cobertura") conserva los Tiempos Extra históricos '
    'y los clasifica como ausenciaEmpleado, sin inventar vacantes',
    () async {
      final schemaV83 = await verifier.schemaAt(83);
      final raw = schemaV83.rawDatabase;

      raw.execute('''
        INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
        VALUES ('cliente-tex', 'CLI-000900', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
      ''');
      raw.execute('''
        INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
        VALUES ('tipo-servicio-tex', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
      ''');
      raw.execute('''
        INSERT INTO servicio (
          id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'servicio-tex', 'SER-000900', 'cliente-tex', 'Vigilancia Satélite', 'tipo-servicio-tex',
          'activo', 1700000000, 1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO empleado (
          id, numero_empleado, nombres, apellido_paterno, sexo, fecha_nacimiento, curp, rfc, nss,
          estado_civil, fecha_ingreso, anios_experiencia_seguridad, estatus,
          created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'empleado-tex', 'EMP-900', 'Juan', 'Pérez', 'masculino', 1700000000, 'CURP900', 'RFC900', 'NSS900',
          'soltero', 1700000000, 2, 'activo',
          1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO tipo_modalidad_turno (id, codigo, nombre, created_at, updated_at)
        VALUES ('turno-tex', '24X24', '24x24', 1700000000, 1700000000);
      ''');
      raw.execute('''
        INSERT INTO tiempo_extra (
          id, folio, fecha, servicio_id, empleado_ausente_id, motivo_ausencia,
          nombre_externo_cubre, turno_id, monto_tiempo_extra, forma_pago,
          estatus, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'tex-historico', 'TEX-000900', 1700000000, 'servicio-tex', 'empleado-tex', 'problemasMedicos',
          'Cobertura externa', 'turno-tex', 150000, 'efectivo',
          'registrado', 1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO tiempo_extra_costo_adicional (tiempo_extra_id, concepto, monto, eliminado)
        VALUES ('tex-historico', 'Traslado', 25000, 0);
      ''');
      raw.execute('''
        INSERT INTO tiempo_extra_evento (tiempo_extra_id, fecha_hora, tipo_evento)
        VALUES ('tex-historico', 1700000000, 'registrado');
      ''');

      // Abrir con la versión actual dispara el onUpgrade real (83 → 85).
      final db = AppDatabase(schemaV83.newConnection());
      final tex = await (db.select(db.tiempoExtra)..where((t) => t.id.equals('tex-historico'))).getSingle();

      // 1. Clasificado, sin inventar nada.
      expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.ausenciaEmpleado.name);
      expect(tex.vacanteOperativaId, isNull, reason: 'no se inventan vacantes históricas');
      expect(tex.descripcionOrigen, isNull, reason: 'no se deduce "otro" para nadie');

      // 2. El id y TODO el dato real intactos.
      expect(tex.id, 'tex-historico');
      expect(tex.folio, 'TEX-000900');
      expect(tex.empleadoAusenteId, 'empleado-tex');
      expect(tex.motivoAusencia, 'problemasMedicos');
      expect(tex.servicioId, 'servicio-tex');
      expect(tex.turnoId, 'turno-tex');
      expect(tex.montoTiempoExtra, 150000);
      expect(tex.formaPago, 'efectivo');
      expect(tex.nombreExternoCubre, 'Cobertura externa');
      expect(tex.estatus, 'registrado');

      // 3. Lo que colgaba de él sobrevive: recrear la tabla no puede
      //    llevarse por delante sus costos ni su bitácora.
      final costos = await (db.select(db.tiempoExtraCostoAdicional)
            ..where((t) => t.tiempoExtraId.equals('tex-historico')))
          .get();
      expect(costos, hasLength(1));
      expect(costos.single.monto, 25000);

      final eventos = await (db.select(db.tiempoExtraEvento)
            ..where((t) => t.tiempoExtraId.equals('tex-historico')))
          .get();
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'registrado');

      // 4. La forma nueva quedó: la columna admite NULL de aquí en
      //    adelante (una vacante no tiene titular ausente).
      final columnas = await db.customSelect("PRAGMA table_info('tiempo_extra')").get();
      final porNombre = {for (final c in columnas) c.data['name'] as String: c.data};
      expect(porNombre.keys, containsAll(<String>['origen_cobertura', 'vacante_operativa_id', 'descripcion_origen']));
      expect(porNombre['empleado_ausente_id']!['notnull'], 0);
      expect(porNombre['motivo_ausencia']!['notnull'], 0);

      // 5. Integridad real, no sólo conteo.
      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);
      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      await db.close();
    },
  );

  test(
    'migración 84 → 85 sobre una base SIN Tiempos Extra no falla y deja la forma nueva',
    () async {
      final schemaV83 = await verifier.schemaAt(83);
      final db = AppDatabase(schemaV83.newConnection());

      expect(await db.select(db.tiempoExtra).get(), isEmpty);
      final columnas = await db.customSelect("PRAGMA table_info('tiempo_extra')").get();
      final nombres = columnas.map((c) => c.data['name'] as String).toSet();
      expect(nombres, containsAll(<String>['origen_cobertura', 'vacante_operativa_id', 'descripcion_origen']));

      await db.close();
    },
  );

  test(
    'migración 91 → 92 (Etapa 3B, vínculo Usuario ↔ Empleado) conserva las cuentas reales, '
    'NO las vincula a nadie automáticamente y deja la unicidad protegida',
    () async {
      final schemaV91 = await verifier.schemaAt(91);
      final raw = schemaV91.rawDatabase;

      // Las dos cuentas REALES de la instalación, tal como están hoy:
      // ambas con empleado_id NULL, una Maestra y otra no, con sus
      // permisos y su historial.
      raw.execute('''
        INSERT INTO usuario (
          id, nombre, nombre_usuario, password_hash, es_maestro, debe_cambiar_password,
          ciclo_vida_registro, created_at, updated_at
        ) VALUES
          ('u-marlon', 'MARLON', 'MARLONRH', 'pbkdf2' || char(36) || '1000' || char(36) || 'salt' || char(36) || 'hash', 1, 0, 'activo', 1700000000, 1700000000),
          ('u-javier', 'JAVIER', 'JAVIER', 'pbkdf2' || char(36) || '1000' || char(36) || 'salt2' || char(36) || 'hash2', 0, 0, 'activo', 1700000000, 1700000000);
      ''');
      raw.execute('''
        INSERT INTO permiso_usuario (usuario_id, codigo) VALUES
          ('u-javier', 'personal.ver'), ('u-javier', 'nomina.ver'), ('u-javier', 'descuentos.crear');
      ''');
      raw.execute('''
        INSERT INTO usuario_evento (usuario_id, actor_usuario_id, fecha_hora, tipo_evento, datos_relevantes)
        VALUES
          ('u-marlon', NULL, 1700000000, 'creado', '{"nombreUsuario":"MARLONRH"}'),
          ('u-javier', 'u-marlon', 1700000100, 'creado', '{"nombreUsuario":"JAVIER"}'),
          ('u-javier', 'u-marlon', 1700000200, 'permisosModificados', '{"agregados":["nomina.ver"]}');
      ''');

      // Abrir con la versión actual dispara el onUpgrade real (91 → 92).
      final db = AppDatabase(schemaV91.newConnection());

      // 1. Las cuentas sobreviven, íntegras.
      final usuarios = await (db.select(db.usuario)..orderBy([(t) => OrderingTerm.asc(t.nombre)])).get();
      expect(usuarios.map((u) => u.nombreUsuario), ['JAVIER', 'MARLONRH']);
      expect(usuarios.firstWhere((u) => u.id == 'u-marlon').esMaestro, isTrue);
      expect(usuarios.every((u) => u.cicloVidaRegistro == 'activo'), isTrue);

      // 2. NADIE queda vinculado automáticamente. Emparejar por nombre
      //    habría sido justo la adivinanza que este proyecto no hace.
      expect(
        usuarios.every((u) => u.empleadoId == null),
        isTrue,
        reason: 'la migración no infiere identidad por nombre, usuario ni puesto',
      );

      // 3. Permisos y auditoría intactos: no se reescribe historia.
      final permisos = await db.select(db.permisoUsuario).get();
      expect(permisos, hasLength(3));
      final eventos = await (db.select(db.usuarioEvento)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      expect(eventos, hasLength(3));
      expect(eventos.first.actorUsuarioId, isNull, reason: 'el bootstrap histórico sigue sin actor');
      expect(eventos.last.tipoEvento, 'permisosModificados');

      // 4. El login sigue funcionando: el hash no se tocó.
      final marlon = usuarios.firstWhere((u) => u.id == 'u-marlon');
      expect(marlon.passwordHash, r'pbkdf2$1000$salt$hash');

      // 5. Y la unicidad ya está protegida por el índice nuevo.
      final indices = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'usuario'").get();
      expect(indices.map((f) => f.data['name']), contains('idx_usuario_empleado_unico'));

      await db.close();
    },
  );

  test(
    'migración 91 → 92 es idempotente — correrla dos veces no falla ni duplica el índice',
    () async {
      final schemaV91 = await verifier.schemaAt(91);
      final db = AppDatabase(schemaV91.newConnection());
      await db.customSelect('SELECT 1').get();
      await migrarVinculoUsuarioEmpleadoV92(db, Migrator(db));
      await migrarVinculoUsuarioEmpleadoV92(db, Migrator(db));

      final indices = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_usuario_empleado_unico'").get();
      expect(indices, hasLength(1));
      await db.close();
    },
  );
}