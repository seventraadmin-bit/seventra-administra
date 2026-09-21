// Reconciliación de Servicios Eventuales cancelados antes de la v90.
//
// Por qué una herramienta y no una migración: mover dinero hacia atrás
// sobre una base de usuario es una decisión operativa, no un cambio de
// esquema. Una migración correría sola y en silencio al abrir la app;
// esto se ejecuta a propósito, primero en diagnóstico, y deja escrito en
// el historial de cada evento por qué se revirtió su cobranza.
//
// Uso (con `flutter test`, no `dart run`: la cadena de imports del
// dominio arrastra Flutter, y éste es el mismo entorno en el que corren
// las pruebas contra SQLite nativo):
//
//   RISEG_DB=<ruta.sqlite> flutter test tool/reconciliar_anulaciones_eventuales.dart
//   RISEG_DB=<ruta.sqlite> RISEG_APLICAR=1 flutter test tool/reconciliar_anulaciones_eventuales.dart
//
// Con la app CERRADA: SQLite no admite dos escritores a la vez, y la app
// tendría en memoria saldos que dejarían de ser ciertos.
//
// La detección y la reversión viven en el dominio
// (`ReconciliarAnulacionesServicioEventualUseCase`); este archivo sólo
// abre la base, elige al actor y reporta.

// ignore_for_file: avoid_print — script de línea de comandos.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/reconciliar_anulaciones_servicio_eventual_usecase.dart';

void main() {
  test('reconciliar anulaciones de eventuales', () async {
    final ruta = Platform.environment['RISEG_DB'];
    expect(ruta, isNotNull, reason: 'falta RISEG_DB=<ruta.sqlite>');
    expect(File(ruta!).existsSync(), isTrue, reason: 'no existe: $ruta');
    await _correr(ruta, aplicar: Platform.environment['RISEG_APLICAR'] == '1');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _correr(String ruta, {required bool aplicar}) async {

  final db = AppDatabase(NativeDatabase(File(ruta)));
  try {
    final egresoRepo = EgresoRepositoryImpl(db);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    final pagoRepo = PagoRepositoryImpl(db);
    final complementoRepo = ComplementoPagoRepositoryImpl(db);
    final repo = ServicioEventualRepositoryImpl(
      db,
      egresoRepo,
      DeudaRepositoryImpl(db, egresoRepo),
      CodigoSecuenciaService(db),
      cuentaRepo,
      pagoRepo,
    );
    final reconciliar = ReconciliarAnulacionesServicioEventualUseCase(
      repo,
      ServicioEventualDocumentoFiscalRepositoryImpl(db, cuentaRepo, repo),
      complementoRepo,
    );
    final cuentasFinancieras = CuentaFinancieraRepositoryImpl(db);

    // El actor es el Usuario Maestro: es una facultad extraordinaria
    // sobre dinero ya asentado, y la bitácora tiene que decir quién.
    final maestros = await (db.select(db.usuario)..where((t) => t.esMaestro.equals(true))).get();
    final actor = maestros.length == 1 ? maestros.single.id : null;

    // Diagnóstico primero, siempre: qué se tocaría y qué cuentas.
    final diagnostico = await reconciliar.ejecutar(aplicar: false);
    print('schemaVersion: ${(await db.customSelect('PRAGMA user_version').getSingle()).data.values.first}');
    print('Eventuales a reconciliar: ${diagnostico.length}');

    final cuentasAfectadas = <String>{};
    for (final r in diagnostico) {
      final e = r.servicioEventual;
      switch (r) {
        case EventualReconciliable(:final cobros, :final cuenta):
          print('  ${e.folio}  CxC ${cuenta.estatus} saldo ${cuenta.saldoPendiente}');
          for (final c in cobros) {
            final ingresos = await (db.select(db.ingreso)..where((t) => t.pagoId.equals(c.pago.id))).get();
            for (final i in ingresos) {
              if (i.cuentaFinancieraId != null) cuentasAfectadas.add(i.cuentaFinancieraId!);
            }
            print('    ${c.pago.folioPago} ${c.monto} '
                '${c.exclusivoDeEstaVenta ? 'EXCLUSIVO -> se cancela el Pago y su Ingreso' : 'COMPARTIDO -> sólo la aplicación'}'
                ' | ingresos: ${ingresos.map((i) => '${i.folioIngreso}(${i.estatus})').join(', ')}');
          }
        case EventualBloqueadoPorFiscal(:final folioDocumento, :final uuidComplemento):
          print('  ${e.folio}  BLOQUEADO: CFDI ${folioDocumento ?? '-'} / Complemento ${uuidComplemento ?? '-'}');
      }
    }

    Future<Map<String, int>> saldos() async => {
          for (final id in cuentasAfectadas) id: await cuentasFinancieras.calcularSaldo(id),
        };
    final nombres = {
      for (final c in await db.select(db.cuentaFinanciera).get()) c.id: c.nombre,
    };
    final antes = await saldos();

    if (!aplicar) {
      for (final e in antes.entries) {
        print('Saldo actual ${nombres[e.key]}: ${e.value}');
      }
      // El interruptor real es la variable de entorno, no un flag:
      // decirlo mal en una herramienta que mueve dinero es peor que
      // no decir nada.
      print('\nDIAGNÓSTICO: no se escribió nada. Repite con RISEG_APLICAR=1 para reconciliar.');
      return;
    }

    await reconciliar.ejecutar(aplicar: true, actorUsuarioId: actor);
    final despues = await saldos();
    for (final id in cuentasAfectadas) {
      print('Saldo ${nombres[id]}: antes ${antes[id]}  después ${despues[id]}');
    }

    // Idempotencia comprobada en la misma corrida.
    final segunda = await reconciliar.ejecutar(aplicar: false);
    print('Pendientes tras aplicar: ${segunda.whereType<EventualReconciliable>().length} '
        '(bloqueados por fiscal: ${segunda.whereType<EventualBloqueadoPorFiscal>().length})');
  } finally {
    await db.close();
  }
}
