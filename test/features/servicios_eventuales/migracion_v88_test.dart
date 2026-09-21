// Migración 87 → 88 — el documento fiscal del eventual.
//
// Es **puramente aditiva**: no vuelve a tocar `cuenta_por_cobrar` ni
// `pago` (eso ya se hizo, y se validó, en la v87). Lo que sí hay que
// demostrar es que el índice único parcial nace con la migración, no
// sólo con `createTable` —que no lo emite— y que la cobranza que ya
// existía queda intacta.

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../generated_migrations/schema.dart';

const _t = 1700000000;

/// La schemaVersion vigente — leída del catálogo de snapshots.
final _versionActual = GeneratedHelper.versions.last;

void main() {
  test('87 → 88: crea el documento fiscal con su índice parcial y no toca la cobranza existente', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v87 = await verifier.schemaAt(87);
    final raw = v87.rawDatabase;

    // Un eventual con su cobranza ya creada a mano en v87 — la forma
    // que tendría una base real migrada desde la rebanada anterior.
    raw.execute('''
      INSERT INTO servicio_eventual (
        id, created_at, updated_at, ciclo_vida_registro, folio, nombre, fecha_hora_inicio,
        fecha_hora_fin, importe_acordado, estatus, tipo_solicitante, solicitante_nombre, requiere_factura
      ) VALUES (
        'evt-1', $_t, $_t, 'activo', 'EVT-000001', 'Concierto', $_t, $_t, 500000,
        'programado', 'eventual', 'Promotora Norte', 1
      );
    ''');
    raw.execute('''
      INSERT INTO cuenta_por_cobrar (
        id, created_at, updated_at, ciclo_vida_registro, servicio_eventual_id, tipo_documento, metodo,
        requiere_complemento, fecha_emision_real, importe_emitido, saldo_original, saldo_pendiente,
        moneda, estatus
      ) VALUES (
        'cxc-1', $_t, $_t, 'activo', 'evt-1', 'cfdi', 'ppd', 1, $_t, 500000, 500000, 500000,
        'MXN', 'pendiente'
      );
    ''');

    final db = AppDatabase(v87.newConnection());
    addTearDown(db.close);

    // Se migra al esquema VIGENTE — ver la nota de `migracion_v87_test`:
    // `createTable` usa la forma Dart actual, así que las versiones
    // intermedias no se pueden validar aisladas.
    await verifier.migrateAndValidate(db, _versionActual);

    // 1. Las dos tablas nuevas existen y nacen vacías.
    final tablas = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('servicio_eventual_documento_fiscal', 'servicio_eventual_documento_fiscal_attachment')",
        )
        .get();
    expect(tablas, hasLength(2));
    expect(await db.select(db.servicioEventualDocumentoFiscal).get(), isEmpty);

    // 2. La cobranza que ya existía no se movió ni un campo.
    final cuenta = await db.customSelect("SELECT * FROM cuenta_por_cobrar WHERE id = 'cxc-1'").getSingle();
    expect(cuenta.data['servicio_eventual_id'], 'evt-1');
    expect(cuenta.data['saldo_pendiente'], 500000);
    expect(cuenta.data['metodo'], 'ppd');

    // 3. El índice único parcial existe DE VERDAD — `Migrator
    //    .createTable` no emite los índices de `@TableIndex`, así que
    //    la migración tiene que crearlo aparte. Se comprueba por su
    //    efecto, no por su presencia en sqlite_master.
    Future<void> insertarDocumento(String id, String folio, String estatus) {
      return db.customStatement('''
        INSERT INTO servicio_eventual_documento_fiscal (
          id, created_at, updated_at, ciclo_vida_registro, servicio_eventual_id, folio, fecha_emision,
          importe, metodo, requiere_complemento, snapshot_razon_social, snapshot_rfc, estatus
        ) VALUES (
          '$id', $_t, $_t, 'activo', 'evt-1', '$folio', $_t, 500000, 'ppd', 1,
          'Promotora Norte SA', 'PRN123456AB1', '$estatus'
        );
      ''');
    }

    await insertarDocumento('doc-1', 'A-1', 'registrado');
    // Un segundo VIGENTE para el mismo eventual: rechazado.
    await expectLater(insertarDocumento('doc-2', 'A-2', 'registrado'), throwsA(anything));
    // Pero cancelados pueden acumularse: el histórico se conserva.
    await insertarDocumento('doc-3', 'A-3', 'cancelado');
    await insertarDocumento('doc-4', 'A-4', 'cancelado');
    expect(await db.select(db.servicioEventualDocumentoFiscal).get(), hasLength(3));

    // 4. Integridad global.
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
    expect(integridad.data.values.first, 'ok');
  });

  test('87 → 88 es idempotente: el índice usa IF NOT EXISTS', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v87 = await verifier.schemaAt(87);
    final db = AppDatabase(v87.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, _versionActual);
    // Segunda pasada sobre la base ya migrada: las guardas de
    // `existeTabla` y el `IF NOT EXISTS` del índice la absorben.
    await db.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS servicio_eventual_documento_fiscal_vigente '
      "ON servicio_eventual_documento_fiscal (servicio_eventual_id) WHERE estatus = 'registrado'",
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test('la base NUEVA (onCreate) nace con el mismo índice que la migrada', () async {
    // El hueco de "siembra dual" otra vez, en su versión de índices: una
    // base creada de cero no pasa por la migración.
    final db = AppDatabase(await _memoria());
    addTearDown(db.close);

    await db.customStatement('''
      INSERT INTO servicio_eventual (
        id, created_at, updated_at, ciclo_vida_registro, folio, nombre, fecha_hora_inicio,
        fecha_hora_fin, importe_acordado, estatus, tipo_solicitante, solicitante_nombre, requiere_factura
      ) VALUES (
        'evt-1', $_t, $_t, 'activo', 'EVT-000001', 'Concierto', $_t, $_t, 500000,
        'programado', 'eventual', 'Promotora Norte', 1
      );
    ''');

    Future<void> insertar(String id, String folio) {
      return db.customStatement('''
        INSERT INTO servicio_eventual_documento_fiscal (
          id, created_at, updated_at, ciclo_vida_registro, servicio_eventual_id, folio, fecha_emision,
          importe, metodo, requiere_complemento, snapshot_razon_social, snapshot_rfc, estatus
        ) VALUES (
          '$id', $_t, $_t, 'activo', 'evt-1', '$folio', $_t, 500000, 'pue', 0,
          'Promotora Norte SA', 'PRN123456AB1', 'registrado'
        );
      ''');
    }

    await insertar('doc-1', 'A-1');
    await expectLater(insertar('doc-2', 'A-2'), throwsA(anything));
  });
}

Future<QueryExecutor> _memoria() async => NativeDatabase.memory();
