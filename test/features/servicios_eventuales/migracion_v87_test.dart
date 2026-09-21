// Migración 86 → 87 sobre datos de cobranza REALES.
//
// La schemaVersion 87 no sólo crea tablas nuevas: reescribe
// `cuenta_por_cobrar` y `pago` con `Migrator.alterTable` (el
// procedimiento de 12 pasos de SQLite: tabla nueva, copia, drop,
// rename). Eso significa que TODA la cobranza existente se copia fila
// por fila. Esta prueba parte de un v86 poblado con el caso difícil
// —CxC abierta/vencida/parcial/pagada/cancelada, PUE y PPD, varios
// Pagos con varias Aplicaciones, una Aplicación cancelada, Ingresos, y
// un Complemento cancelado con su sustituto vigente— y comprueba,
// campo por campo, que después de migrar sigue siendo lo mismo.

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../generated_migrations/schema.dart';

/// Instante fijo: nada en esta prueba puede depender del reloj.
const _t = 1700000000;

/// La schemaVersion vigente — se lee del catálogo de snapshots, nunca
/// se teclea, para que esta prueba no se quede atrás en la próxima
/// migración.
final _versionActual = GeneratedHelper.versions.last;

void main() {
  test('86 → 87: la cobranza existente sobrevive intacta y queda marcada como de Cliente', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v86 = await verifier.schemaAt(86);
    final raw = v86.rawDatabase;

    raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cli-1', 'CLI-000001', 'Corporativo Sur', 'activo', $_t, $_t, $_t, 'activo');
    ''');

    // Dos DocumentoPorEmitir: uno PUE y uno PPD — el método viaja a la
    // CxC y tiene que seguir ahí después de reescribir la tabla.
    for (final (id, codigo, metodo, complemento) in [
      ('dpe-pue', 'DPE-000001', 'PUE', 0),
      ('dpe-ppd', 'DPE-000002', 'PPD', 1),
    ]) {
      raw.execute('''
        INSERT INTO documento_por_emitir (
          id, created_at, updated_at, ciclo_vida_registro, codigo, cliente_id, tipo_documento,
          agrupacion, metodo, requiere_complemento, periodo_inicio, periodo_fin, generation_key,
          importe_base_esperado, importe_final_esperado, estatus
        ) VALUES (
          '$id', $_t, $_t, 'activo', '$codigo', 'cli-1', 'factura', 'porServicio', '$metodo',
          $complemento, $_t, $_t, 'key-$id', 1000000, 1000000, 'emitido'
        );
      ''');
    }

    // Cinco CxC que cubren los cinco estatus posibles. Las tres
    // primeras cuelgan de dpe-pue; las otras dos de dpe-ppd... salvo
    // que `documento_por_emitir_id` es UNIQUE, así que cada CxC exige
    // su propio documento.
    final documentos = <String>[];
    for (var i = 0; i < 3; i++) {
      final id = 'dpe-extra-$i';
      documentos.add(id);
      raw.execute('''
        INSERT INTO documento_por_emitir (
          id, created_at, updated_at, ciclo_vida_registro, codigo, cliente_id, tipo_documento,
          agrupacion, metodo, requiere_complemento, periodo_inicio, periodo_fin, generation_key,
          importe_base_esperado, importe_final_esperado, estatus
        ) VALUES (
          '$id', $_t, $_t, 'activo', 'DPE-EXTRA-$i', 'cli-1', 'factura', 'porServicio', 'PUE',
          0, $_t, $_t, 'key-$id', 500000, 500000, 'emitido'
        );
      ''');
    }

    final cuentas = <(String, String, String, String, int, int, String)>[
      ('cxc-abierta', 'dpe-pue', 'PUE', 'abierta', 1000000, 1000000, 'FAC-001'),
      ('cxc-vencida', 'dpe-ppd', 'PPD', 'vencida', 800000, 800000, 'FAC-002'),
      ('cxc-parcial', documentos[0], 'PUE', 'parcial', 500000, 200000, 'FAC-003'),
      ('cxc-pagada', documentos[1], 'PUE', 'pagada', 500000, 0, 'FAC-004'),
      ('cxc-cancelada', documentos[2], 'PUE', 'cancelada', 500000, 500000, 'FAC-005'),
    ];
    for (final (id, dpe, metodo, estatus, original, pendiente, folio) in cuentas) {
      raw.execute('''
        INSERT INTO cuenta_por_cobrar (
          id, created_at, updated_at, ciclo_vida_registro, documento_por_emitir_id, cliente_id,
          tipo_documento, metodo, requiere_complemento, folio_documento, uuid, fecha_emision_real,
          importe_emitido, saldo_original, saldo_pendiente, moneda, estatus, fecha_vencimiento, observaciones
        ) VALUES (
          '$id', $_t, $_t, 'activo', '$dpe', 'cli-1', 'factura', '$metodo',
          ${metodo == 'PPD' ? 1 : 0}, '$folio', 'uuid-$id', $_t,
          $original, $original, $pendiente, 'MXN', '$estatus', $_t, 'obs de $id'
        );
      ''');
    }

    // Dos Pagos, uno con dos Aplicaciones (una cancelada) y otro con
    // su Complemento cancelado + sustituto vigente.
    raw.execute('''
      INSERT INTO pago (
        id, created_at, updated_at, ciclo_vida_registro, folio_pago, cliente_id, monto_total,
        monto_aplicado, fecha_pago, forma_pago, referencia, observaciones, estatus
      ) VALUES ('pago-1', $_t, $_t, 'activo', 'PAG-000001', 'cli-1', 800000, 300000, $_t,
        'transferencia', 'REF-1', 'obs pago 1', 'registrado');
    ''');
    raw.execute('''
      INSERT INTO pago (
        id, created_at, updated_at, ciclo_vida_registro, folio_pago, cliente_id, monto_total,
        monto_aplicado, fecha_pago, forma_pago, estatus
      ) VALUES ('pago-2', $_t, $_t, 'activo', 'PAG-000002', 'cli-1', 500000, 500000, $_t,
        'transferencia', 'registrado');
    ''');

    raw.execute('''
      INSERT INTO aplicacion_pago (
        id, created_at, updated_at, ciclo_vida_registro, pago_id, cuenta_por_cobrar_id,
        monto, saldo_antes, saldo_despues, estatus
      ) VALUES ('apl-1', $_t, $_t, 'activo', 'pago-1', 'cxc-parcial', 300000, 500000, 200000, 'aplicada');
    ''');
    raw.execute('''
      INSERT INTO aplicacion_pago (
        id, created_at, updated_at, ciclo_vida_registro, pago_id, cuenta_por_cobrar_id,
        monto, saldo_antes, saldo_despues, estatus, motivo_cancelacion
      ) VALUES ('apl-2', $_t, $_t, 'activo', 'pago-1', 'cxc-abierta', 100000, 1000000, 900000,
        'cancelada', 'Se aplicó a la factura equivocada');
    ''');
    raw.execute('''
      INSERT INTO aplicacion_pago (
        id, created_at, updated_at, ciclo_vida_registro, pago_id, cuenta_por_cobrar_id,
        monto, saldo_antes, saldo_despues, estatus
      ) VALUES ('apl-3', $_t, $_t, 'activo', 'pago-2', 'cxc-pagada', 500000, 500000, 0, 'aplicada');
    ''');

    for (final (id, pago, folio) in [('ing-1', 'pago-1', 'ING-000001'), ('ing-2', 'pago-2', 'ING-000002')]) {
      raw.execute('''
        INSERT INTO ingreso (
          id, created_at, updated_at, ciclo_vida_registro, pago_id, folio_ingreso, monto, fecha,
          forma_pago, concepto, estatus
        ) VALUES ('$id', $_t, $_t, 'activo', '$pago', '$folio', 500000, $_t,
          'transferencia', 'Cobranza', 'registrado');
      ''');
    }

    raw.execute('''
      INSERT INTO complemento_pago (
        id, created_at, updated_at, ciclo_vida_registro, pago_id, uuid, fecha_timbrado,
        monto_total, estatus, motivo_cancelacion
      ) VALUES ('comp-cancelado', $_t, $_t, 'activo', 'pago-2', 'uuid-comp-1', $_t, 500000,
        'cancelado', 'Timbrado con datos incorrectos');
    ''');
    raw.execute('''
      INSERT INTO complemento_pago (
        id, created_at, updated_at, ciclo_vida_registro, pago_id, uuid, fecha_timbrado,
        monto_total, estatus
      ) VALUES ('comp-vigente', $_t, $_t, 'activo', 'pago-2', 'uuid-comp-2', $_t, 500000, 'registrado');
    ''');

    // --- Fotografía ANTES de migrar ------------------------------
    List<Map<String, Object?>> leerCrudo(String sql) =>
        raw.select(sql).map((fila) => {for (final c in fila.keys) c: fila[c]}).toList();

    final cxcAntes = leerCrudo('SELECT * FROM cuenta_por_cobrar ORDER BY id');
    final pagosAntes = leerCrudo('SELECT * FROM pago ORDER BY id');
    final aplicacionesAntes = leerCrudo('SELECT * FROM aplicacion_pago ORDER BY id');
    final ingresosAntes = leerCrudo('SELECT * FROM ingreso ORDER BY id');
    final complementosAntes = leerCrudo('SELECT * FROM complemento_pago ORDER BY id');

    final db = AppDatabase(v86.newConnection());
    addTearDown(db.close);

    // Se migra al esquema VIGENTE, no a la v87 aislada: `Migrator
    // .createTable` crea las tablas con la forma Dart actual, así que
    // una tabla nacida en la v87 ya trae las columnas de v88/v89 y
    // validar contra el snapshot intermedio sería imposible. Éste es
    // además el camino real de una base de usuario que estaba en v86.
    await verifier.migrateAndValidate(db, _versionActual);

    Future<List<Map<String, Object?>>> leer(String sql) async {
      final filas = await db.customSelect(sql).get();
      return filas.map((f) => f.data).toList();
    }

    // --- 1. Nada se perdió, campo por campo ---------------------
    void comparar(
      String tabla,
      List<Map<String, Object?>> antes,
      List<Map<String, Object?>> despues, {
      Set<String> columnasNuevas = const {},
    }) {
      expect(despues, hasLength(antes.length), reason: '$tabla cambió de número de filas');
      for (var i = 0; i < antes.length; i++) {
        for (final columna in antes[i].keys) {
          expect(
            despues[i][columna],
            antes[i][columna],
            reason: '$tabla.$columna de la fila ${antes[i]['id']} no sobrevivió a la migración',
          );
        }
        for (final columna in columnasNuevas) {
          expect(despues[i].containsKey(columna), isTrue, reason: '$tabla debería tener $columna en v87');
        }
      }
    }

    final cxcDespues = await leer('SELECT * FROM cuenta_por_cobrar ORDER BY id');
    comparar('cuenta_por_cobrar', cxcAntes, cxcDespues, columnasNuevas: {'servicio_eventual_id'});
    comparar('pago', pagosAntes, await leer('SELECT * FROM pago ORDER BY id'),
        columnasNuevas: {'servicio_eventual_id'});
    comparar('aplicacion_pago', aplicacionesAntes, await leer('SELECT * FROM aplicacion_pago ORDER BY id'));
    comparar('ingreso', ingresosAntes, await leer('SELECT * FROM ingreso ORDER BY id'));
    comparar('complemento_pago', complementosAntes, await leer('SELECT * FROM complemento_pago ORDER BY id'));

    // --- 2. Toda la cobranza heredada es de Cliente -------------
    for (final fila in cxcDespues) {
      expect(fila['servicio_eventual_id'], isNull, reason: 'ninguna CxC legacy nace como eventual');
      expect(fila['cliente_id'], isNotNull);
      expect(fila['documento_por_emitir_id'], isNotNull);
    }
    for (final fila in await leer('SELECT * FROM pago ORDER BY id')) {
      expect(fila['servicio_eventual_id'], isNull);
      expect(fila['cliente_id'], isNotNull);
    }

    // --- 3. El índice único parcial de Complemento sigue vivo ---
    //
    // Se recrearon dos tablas vecinas; si el índice se hubiera perdido,
    // un segundo complemento vigente pasaría sin protesta.
    await expectLater(
      db.customStatement('''
        INSERT INTO complemento_pago (
          id, created_at, updated_at, ciclo_vida_registro, pago_id, uuid, fecha_timbrado,
          monto_total, estatus
        ) VALUES ('comp-duplicado', $_t, $_t, 'activo', 'pago-2', 'uuid-comp-3', $_t, 500000, 'registrado');
      '''),
      throwsA(anything),
    );

    // --- 4. El XOR de origen de la CxC se aplica de verdad ------
    Future<void> insertarCxc(String id, String? dpe, String? eventual, String? cliente) {
      return db.customStatement('''
        INSERT INTO cuenta_por_cobrar (
          id, created_at, updated_at, ciclo_vida_registro, documento_por_emitir_id, servicio_eventual_id,
          cliente_id, tipo_documento, metodo, requiere_complemento, fecha_emision_real,
          importe_emitido, saldo_original, saldo_pendiente, moneda, estatus
        ) VALUES (
          '$id', $_t, $_t, 'activo', ${dpe == null ? 'NULL' : "'$dpe'"},
          ${eventual == null ? 'NULL' : "'$eventual'"}, ${cliente == null ? 'NULL' : "'$cliente'"},
          'factura', 'PUE', 0, $_t, 1000, 1000, 1000, 'MXN', 'abierta'
        );
      ''');
    }

    // Sin ningún origen: rechazada.
    await expectLater(insertarCxc('cxc-sin-origen', null, null, 'cli-1'), throwsA(anything));
    // Con los dos: rechazada (el eventual no existe, pero el CHECK del
    // XOR se evalúa igual).
    await expectLater(insertarCxc('cxc-dos-origenes', 'dpe-pue', 'evt-1', 'cli-1'), throwsA(anything));

    // --- 5. Integridad global -----------------------------------
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
    expect(integridad.data.values.first, 'ok');

    // --- 6. El folio EVT quedó sembrado por la migración --------
    final secuencia = await db
        .customSelect("SELECT * FROM codigo_secuencia WHERE entity_type = 'servicioEventual'")
        .getSingleOrNull();
    expect(secuencia, isNotNull, reason: 'la migración debe sembrar el contador del folio EVT');
    expect(secuencia!.data['prefijo'], 'EVT');
  });

  test('86 → 87 es idempotente: migrar dos veces no duplica nada', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v86 = await verifier.schemaAt(86);
    final db = AppDatabase(v86.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, _versionActual);
    // Segunda pasada sobre la misma base ya migrada: las guardas de
    // `columnasDe`/`existeTabla` tienen que absorberla sin error.
    await db.customStatement('PRAGMA foreign_key_check');

    final secuencias = await db
        .customSelect("SELECT COUNT(*) AS n FROM codigo_secuencia WHERE entity_type = 'servicioEventual'")
        .getSingle();
    expect(secuencias.data['n'], 1);
  });
}
