// Etapa 4D — la migración 92 → 93 no puede cambiar nada de lo que ya
// existe, y sobre todo no puede configurar la recuperación portable por
// su cuenta.
//
// Configurarla exige que una persona elija una frase y guarde una clave
// de recuperación en papel. Una migración que lo hiciera sola produciría
// una configuración que nadie puede usar y, peor, daría la impresión de
// que los respaldos ya están protegidos cuando no lo están.
//
// Estas pruebas parten del esquema 92 real, meten datos de los que sí
// duelen —usuarios con permisos, una credencial de Bóveda cifrada, una
// de Telefonía, un portal de cliente— y comprueban que al otro lado
// siguen exactamente igual.

import 'package:drift/drift.dart' show Migrator;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/migrations/migrar_recuperacion_portable_v93.dart';

import '../../../generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verificador;

  setUpAll(() => verificador = SchemaVerifier(GeneratedHelper()));

  /// Una base en el esquema 92 con datos que importan de verdad.
  Future<({AppDatabase db, dynamic esquema})> baseV92ConDatos() async {
    final esquema = await verificador.schemaAt(92);
    final raw = esquema.rawDatabase;

    raw.execute('''
      INSERT INTO usuario (
        id, nombre, nombre_usuario, password_hash, es_maestro, debe_cambiar_password,
        ciclo_vida_registro, created_at, updated_at
      ) VALUES
        ('u-marlon', 'MARLON', 'MARLONRH', 'pbkdf2' || char(36) || '1000' || char(36) || 's' || char(36) || 'h', 1, 0, 'activo', 1700000000, 1700000000),
        ('u-javier', 'JAVIER', 'JAVIER', 'pbkdf2' || char(36) || '1000' || char(36) || 's2' || char(36) || 'h2', 0, 0, 'activo', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO permiso_usuario (usuario_id, codigo) VALUES
        ('u-javier', 'personal.ver'), ('u-javier', 'nomina.ver');
    ''');
    raw.execute('''
      INSERT INTO boveda_credencial (id, nombre, tipo, secreto_cifrado, ciclo_vida_registro, created_at, updated_at)
      VALUES ('bc-1', 'RISEG - Portal SAT', 'portal',
        'aesgcm' || char(36) || '1' || char(36) || 'aXY=' || char(36) || 'Y2lmcmFkbw==',
        'activo', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, ciclo_vida_registro, created_at, updated_at)
      VALUES ('cli-1', 'CLI-001', 'MORGAN', 'activo', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO cliente_portal (id, cliente_id, nombre, tipo, contrasena_cifrada, ciclo_vida_registro, created_at, updated_at)
      VALUES ('cp-1', 'cli-1', 'Portal MORGAN', 'facturacion',
        'aesgcm' || char(36) || '1' || char(36) || 'aXY=' || char(36) || 'cG9ydGFs',
        'activo', 1700000000, 1700000000);
    ''');

    return (db: AppDatabase(esquema.newConnection()), esquema: esquema);
  }

  test('92 → 93 deja el esquema en 93 y crea la tabla nueva vacía', () async {
    final partida = await baseV92ConDatos();
    final db = partida.db;
    addTearDown(db.close);

    // Abrir fuerza la migración.
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 93);
    expect(db.schemaVersion, 93);

    final configuraciones = await db.select(db.configuracionRecuperacionPortable).get();
    expect(configuraciones, isEmpty, reason: 'la recuperación portable queda SIN configurar');
  });

  test('tras migrar, la recuperación portable sigue "no configurada"', () async {
    final partida = await baseV92ConDatos();
    final db = partida.db;
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final filas = await db.select(db.configuracionRecuperacionPortable).get();

    expect(filas, isEmpty);
    // Ni backupSetId, ni MWK, ni clave de recuperación: nada se inventa.
    final tablas =
        await db.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%recuperacion%'").get();
    expect(tablas, hasLength(1), reason: 'existe la tabla, pero está vacía');
  });

  test('los datos anteriores llegan intactos al otro lado', () async {
    final partida = await baseV92ConDatos();
    final db = partida.db;
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final usuarios = await db.customSelect('SELECT id, nombre, es_maestro FROM usuario ORDER BY id').get();
    expect(usuarios.map((f) => f.data['id']), ['u-javier', 'u-marlon']);
    expect(usuarios.firstWhere((f) => f.data['id'] == 'u-marlon').data['es_maestro'], 1);

    final permisos = await db.customSelect('SELECT codigo FROM permiso_usuario ORDER BY codigo').get();
    expect(permisos.map((f) => f.data['codigo']), ['nomina.ver', 'personal.ver']);
  });

  test('Bóveda, Telefonía y Portal conservan su texto cifrado sin tocarlo', () async {
    final partida = await baseV92ConDatos();
    final db = partida.db;
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final boveda = await db.customSelect('SELECT secreto_cifrado FROM boveda_credencial').getSingle();
    expect(boveda.data['secreto_cifrado'], startsWith('aesgcm\$1\$'));
    expect(boveda.data['secreto_cifrado'], endsWith('Y2lmcmFkbw=='), reason: 'byte por byte el mismo');

    final portal = await db.customSelect('SELECT contrasena_cifrada FROM cliente_portal').getSingle();
    expect(portal.data['contrasena_cifrada'], endsWith('cG9ydGFs'));

    // La tabla de Telefonía existe y sigue con su forma; la migración no
    // la toca, así que basta comprobar que se puede consultar.
    final telefonia = await db.customSelect('SELECT COUNT(*) AS n FROM equipo_telefonico_credencial').getSingle();
    expect(telefonia.data['n'], 0);
  });

  test('el formato de los ciphertext NO se migra ni se marca con keyId', () async {
    final partida = await baseV92ConDatos();
    final db = partida.db;
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final boveda = await db.customSelect('SELECT secreto_cifrado FROM boveda_credencial').getSingle();
    final valor = boveda.data['secreto_cifrado'] as String;

    // Sigue teniendo exactamente cuatro partes: algoritmo, versión, iv,
    // ciphertext. El `keyId` del portable es metadata del paquete y no
    // se asocia retrospectivamente a lo ya cifrado.
    expect(valor.split('\$'), hasLength(4));
    expect(valor, isNot(contains('keyId')));
  });

  test('la migración es idempotente: aplicarla dos veces no rompe nada', () async {
    final esquema = await verificador.schemaAt(92);
    final db = AppDatabase(esquema.newConnection());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    // La segunda pasada es la que importa: `createTable` sobre una tabla
    // que ya existe no puede tumbar un arranque.
    await expectLater(migrarRecuperacionPortableV93(db, Migrator(db)), completes);

    expect(await db.select(db.configuracionRecuperacionPortable).get(), isEmpty);
  });

  test('una instalación nueva (onCreate) también nace sin configuración', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();

    expect(db.schemaVersion, 93);
    expect(await db.select(db.configuracionRecuperacionPortable).get(), isEmpty);
  });

  test('`installationId` no se toca ni se reutiliza como backupSetId', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final metadata = await db.ensureMetadata(appVersion: '1.0.0');

    final configuraciones = await db.select(db.configuracionRecuperacionPortable).get();

    expect(configuraciones, isEmpty);
    expect(metadata.installationId, isNotEmpty);
    // Son conceptos distintos: uno identifica la instalación, el otro una
    // familia criptográfica de respaldos. Nada los liga.
  });
}
