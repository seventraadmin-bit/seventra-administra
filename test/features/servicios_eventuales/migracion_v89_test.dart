// Migración 88 → 89 — el tratamiento de IVA del precio acordado.
//
// La pregunta que esta prueba contesta es una sola, y es aritmética:
//
//   ¿el total de venta de CADA eventual histórico es el mismo antes y
//   después de la migración?
//
// En la v88 `importeAcordado` ERA el total. Después de la v89 el total
// se DERIVA. Si la derivación diera otro número, la deuda del cliente
// habría cambiado sola — por eso se comprueba fila por fila, y no de
// palabra.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';

import '../../generated_migrations/schema.dart';

const _t = 1700000000;

/// La schemaVersion vigente — leída del catálogo de snapshots.
final _versionActual = GeneratedHelper.versions.last;

/// Importes deliberadamente feos: redondos, con centavos, primos y el
/// caso de un solo centavo. Si alguno cambiara de total, se ve aquí.
const _importesLegacy = [1000000, 1160000, 777777, 33333, 1, 999999, 250050];

void main() {
  test('88 → 89: el total de venta de TODOS los eventuales históricos no se mueve ni un centavo', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v88 = await verifier.schemaAt(88);
    final raw = v88.rawDatabase;

    // Cada eventual con su Cuenta por cobrar, tal como los dejó la v88:
    // `importeAcordado` == `importeEmitido` == el total a cobrar.
    for (var i = 0; i < _importesLegacy.length; i++) {
      final importe = _importesLegacy[i];
      raw.execute('''
        INSERT INTO servicio_eventual (
          id, created_at, updated_at, ciclo_vida_registro, folio, nombre, fecha_hora_inicio,
          fecha_hora_fin, importe_acordado, estatus, tipo_solicitante, solicitante_nombre, requiere_factura
        ) VALUES (
          'evt-$i', $_t, $_t, 'activo', 'EVT-00000$i', 'Evento $i', $_t, $_t, $importe,
          'programado', 'eventual', 'Promotora $i', 0
        );
      ''');
      raw.execute('''
        INSERT INTO cuenta_por_cobrar (
          id, created_at, updated_at, ciclo_vida_registro, servicio_eventual_id, tipo_documento, metodo,
          requiere_complemento, fecha_emision_real, importe_emitido, saldo_original, saldo_pendiente,
          moneda, estatus
        ) VALUES (
          'cxc-$i', $_t, $_t, 'activo', 'evt-$i', 'reciboDePago', 'noAplica', 0, $_t,
          $importe, $importe, $importe, 'MXN', 'pendiente'
        );
      ''');
    }

    // Uno con cobro parcial: su saldo tampoco se puede tocar.
    raw.execute('''
      INSERT INTO pago (
        id, created_at, updated_at, ciclo_vida_registro, folio_pago, servicio_eventual_id, monto_total,
        monto_aplicado, fecha_pago, forma_pago, estatus
      ) VALUES ('pago-1', $_t, $_t, 'activo', 'PAG-000001', 'evt-0', 400000, 400000, $_t,
        'transferencia', 'registrado');
    ''');
    raw.execute('''
      INSERT INTO aplicacion_pago (
        id, created_at, updated_at, ciclo_vida_registro, pago_id, cuenta_por_cobrar_id,
        monto, saldo_antes, saldo_despues, estatus
      ) VALUES ('apl-1', $_t, $_t, 'activo', 'pago-1', 'cxc-0', 400000, 1000000, 600000, 'aplicada');
    ''');
    raw.execute("UPDATE cuenta_por_cobrar SET saldo_pendiente = 600000, estatus = 'parcial' WHERE id = 'cxc-0';");

    // --- El total ANTES: en la v88 era el importe capturado ---------
    final antes = {
      for (final fila in raw.select('SELECT id, importe_acordado FROM servicio_eventual'))
        fila['id'] as String: fila['importe_acordado'] as int,
    };
    final cxcAntes = {
      for (final fila in raw.select('SELECT id, importe_emitido, saldo_original, saldo_pendiente, estatus FROM cuenta_por_cobrar'))
        fila['id'] as String: {
          'importe_emitido': fila['importe_emitido'],
          'saldo_original': fila['saldo_original'],
          'saldo_pendiente': fila['saldo_pendiente'],
          'estatus': fila['estatus'],
        },
    };

    final db = AppDatabase(v88.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, _versionActual);

    // --- 1. La demostración: total antes == total después -----------
    final eventuales = await db.select(db.servicioEventual).get();
    expect(eventuales, hasLength(_importesLegacy.length));
    for (final eventual in eventuales) {
      final totalDespues = totalVentaEventual(
        importeAcordado: eventual.importeAcordado,
        tratamientoIva: TratamientoIva.values.byName(eventual.tratamientoIva),
      );
      expect(
        totalDespues,
        antes[eventual.id],
        reason: '${eventual.folio}: el total de venta cambió al migrar',
      );
    }

    // --- 2. Y el tratamiento asignado es el que NO inventa desglose --
    for (final eventual in eventuales) {
      expect(eventual.tratamientoIva, tratamientoIvaLegacyEventual.name);
      final desglose = calcularTotalesVentaEventual(
        importeAcordado: eventual.importeAcordado,
        tratamientoIva: TratamientoIva.values.byName(eventual.tratamientoIva),
      );
      expect(
        desglose.iva,
        0,
        reason: 'un histórico sin IVA capturado no debe empezar a mostrar uno',
      );
      expect(desglose.subtotal, eventual.importeAcordado);
    }

    // --- 3. §6: la cobranza histórica quedó CONGELADA ---------------
    final cuentas = await db.select(db.cuentaPorCobrar).get();
    for (final cuenta in cuentas) {
      final esperado = cxcAntes[cuenta.id]!;
      expect(cuenta.importeEmitido, esperado['importe_emitido'], reason: '${cuenta.id}.importeEmitido');
      expect(cuenta.saldoOriginal, esperado['saldo_original'], reason: '${cuenta.id}.saldoOriginal');
      expect(cuenta.saldoPendiente, esperado['saldo_pendiente'], reason: '${cuenta.id}.saldoPendiente');
      expect(cuenta.estatus, esperado['estatus'], reason: '${cuenta.id}.estatus');
    }
    // Pagos, aplicaciones e ingresos, intactos.
    expect(await db.select(db.pago).get(), hasLength(1));
    expect((await db.select(db.aplicacionPago).get()).single.monto, 400000);

    // --- 4. Integridad global --------------------------------------
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
    expect(integridad.data.values.first, 'ok');
  });

  test('88 → 89 es idempotente: la columna no se agrega dos veces', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v88 = await verifier.schemaAt(88);
    final db = AppDatabase(v88.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, _versionActual);
    // La guarda de `columnasDe` absorbe una segunda pasada.
    final columnas = await db.customSelect('PRAGMA table_info(servicio_eventual)').get();
    expect(
      columnas.where((c) => c.data['name'] == 'tratamiento_iva'),
      hasLength(1),
    );
  });

  test('una base NUEVA nace con la misma semántica que una migrada', () async {
    // El hueco de "siembra dual" en su versión de defaults: una base
    // creada de cero no pasa por la migración.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final eventual = await db.into(db.servicioEventual).insertReturning(
          ServicioEventualCompanion.insert(
            folio: 'EVT-000001',
            nombre: 'Evento',
            fechaHoraInicio: DateTime(2026, 5, 1),
            fechaHoraFin: DateTime(2026, 5, 2),
            importeAcordado: 500000,
            tipoSolicitante: 'eventual',
            solicitanteNombre: const Value('Promotora'),
          ),
        );
    expect(eventual.tratamientoIva, tratamientoIvaLegacyEventual.name);
  });
}
