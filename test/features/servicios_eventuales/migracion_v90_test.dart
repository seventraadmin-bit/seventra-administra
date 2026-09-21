// Migración 89 → 90 — el receptor fiscal, separado del solicitante.
//
// Lo que esta prueba vigila no es que la columna exista, sino que la
// migración NO haya rellenado nada: el hueco que corrige la v90 es
// precisamente haber tratado el nombre del solicitante como si fuera la
// razón social. Copiarlo en masa al migrar repetiría ese error sobre
// todo el histórico y lo dejaría indistinguible de un dato capturado.

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../generated_migrations/schema.dart';

const _t = 1700000000;

final _versionActual = GeneratedHelper.versions.last;

void main() {
  test('89 → 90: el histórico queda con receptor fiscal NULL, nunca inventado', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v89 = await verifier.schemaAt(89);
    final raw = v89.rawDatabase;

    // Un eventual con factura y un solicitante ocasional: el caso que
    // la prueba manual descubrió mal identificado.
    raw.execute('''
      INSERT INTO servicio_eventual (
        id, created_at, updated_at, ciclo_vida_registro, folio, nombre, fecha_hora_inicio,
        fecha_hora_fin, importe_acordado, estatus, tipo_solicitante, solicitante_nombre,
        solicitante_contacto, tratamiento_iva, requiere_factura
      ) VALUES (
        'evt-1', $_t, $_t, 'activo', 'EVT-000001', 'Posada', $_t, $_t, 800000,
        'finalizado', 'eventual', 'Juan del comité', 'Juan', 'masIva', 1
      );
    ''');
    raw.execute('''
      INSERT INTO cuenta_por_cobrar (
        id, created_at, updated_at, ciclo_vida_registro, servicio_eventual_id, tipo_documento, metodo,
        requiere_complemento, fecha_emision_real, importe_emitido, saldo_original, saldo_pendiente,
        moneda, estatus
      ) VALUES ('cxc-1', $_t, $_t, 'activo', 'evt-1', 'facturaCfdi', 'pue', 0, $_t,
        928000, 928000, 928000, 'MXN', 'pendiente');
    ''');
    // Y un CFDI ya emitido: su snapshot tampoco puede ganar un CP hoy.
    raw.execute('''
      INSERT INTO servicio_eventual_documento_fiscal (
        id, created_at, updated_at, ciclo_vida_registro, servicio_eventual_id, folio, fecha_emision,
        importe, metodo, requiere_complemento, snapshot_razon_social, snapshot_rfc, estatus
      ) VALUES ('doc-1', $_t, $_t, 'activo', 'evt-1', 'A-1001', $_t, 928000, 'pue', 0,
        'Administradora Bosques S.A. de C.V.', 'ABO010101AAA', 'registrado');
    ''');

    final db = AppDatabase(v89.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, _versionActual);

    // 1. El receptor fiscal del histórico: vacío, no adivinado.
    final eventual = (await db.select(db.servicioEventual).get()).single;
    expect(eventual.solicitanteRazonSocial, isNull,
        reason: 'el nombre del solicitante NO es la razón social');
    expect(eventual.solicitanteRfc, isNull);
    expect(eventual.solicitanteCodigoPostalFiscal, isNull);
    expect(eventual.entidadFiscalId, isNull);
    // Y lo que sí había sigue intacto.
    expect(eventual.solicitanteNombre, 'Juan del comité');
    expect(eventual.requiereFactura, isTrue);
    expect(eventual.tratamientoIva, 'masIva');

    // 2. El CFDI congelado sigue diciendo exactamente lo que decía.
    final documento = (await db.select(db.servicioEventualDocumentoFiscal).get()).single;
    expect(documento.snapshotCodigoPostalFiscal, isNull,
        reason: 'tomar el CP de hoy haría que un documento de ayer dijera algo que no decía');
    expect(documento.snapshotRazonSocial, 'Administradora Bosques S.A. de C.V.');
    expect(documento.snapshotRfc, 'ABO010101AAA');

    // 3. Ni un centavo se movió.
    final cuenta = (await db.select(db.cuentaPorCobrar).get()).single;
    expect(cuenta.importeEmitido, 928000);
    expect(cuenta.saldoPendiente, 928000);
    expect(cuenta.estatus, 'pendiente');

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
    expect(integridad.data.values.first, 'ok');
  });

  test('89 → 90 es idempotente: ninguna columna se agrega dos veces', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v89 = await verifier.schemaAt(89);
    final db = AppDatabase(v89.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, _versionActual);

    final columnas = await db.customSelect('PRAGMA table_info(servicio_eventual)').get();
    for (final nombre in [
      'entidad_fiscal_id',
      'solicitante_razon_social',
      'solicitante_rfc',
      'solicitante_codigo_postal_fiscal',
    ]) {
      expect(columnas.where((c) => c.data['name'] == nombre), hasLength(1), reason: nombre);
    }
  });

  test('una base NUEVA nace con las mismas columnas que una migrada', () async {
    // El hueco de "siembra dual": una base creada de cero no pasa por
    // la migración, y ya mordió antes en este módulo (el folio EVT).
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final columnas = await db.customSelect('PRAGMA table_info(servicio_eventual)').get();
    final nombres = {for (final c in columnas) c.data['name'] as String};
    expect(nombres, containsAll(<String>{
      'entidad_fiscal_id',
      'solicitante_razon_social',
      'solicitante_rfc',
      'solicitante_codigo_postal_fiscal',
    }));

    final documento = await db.customSelect('PRAGMA table_info(servicio_eventual_documento_fiscal)').get();
    expect(
      {for (final c in documento) c.data['name'] as String},
      contains('snapshot_codigo_postal_fiscal'),
    );
  });
}
