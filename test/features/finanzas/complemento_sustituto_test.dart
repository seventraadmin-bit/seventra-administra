// Etapa "Complemento sustituto" (schemaVersion 79).
//
// GAP QUE CIERRA: `ComplementoPago.pagoId` era UNIQUE, así que cancelar
// un Complemento reactivaba la obligación pero hacía IMPOSIBLE
// registrar el sustituto — la fila cancelada seguía ocupando el único
// lugar. El Pago quedaba pendiente para siempre.
//
// INVARIANTE NUEVO: un Pago tiene N Complementos históricos y a lo más
// UNO vigente (`estatus == 'registrado'`), garantizado por el índice
// único PARCIAL `complemento_pago_vigente_por_pago`.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';

const _uuidA = 'aaaaaaaa-1111-2222-3333-444444444444';
const _uuidB = 'bbbbbbbb-1111-2222-3333-444444444444';
const _uuidC = 'cccccccc-1111-2222-3333-444444444444';

void main() {
  late AppDatabase db;
  late PagoRepositoryImpl pagoRepo;
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late ComplementoPagoRepositoryImpl complementoRepo;
  late ObtenerComplementosPendientesUseCase obtenerPendientes;
  late RegistrarComplementoPagoUseCase registrar;
  late CancelarComplementoPagoUseCase cancelar;
  late String clienteId;

  void montarSobre(AppDatabase base) {
    pagoRepo = PagoRepositoryImpl(base);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(base);
    complementoRepo = ComplementoPagoRepositoryImpl(base);
    obtenerPendientes = ObtenerComplementosPendientesUseCase(pagoRepo, cuentaRepo, complementoRepo);
    registrar = RegistrarComplementoPagoUseCase(complementoRepo, pagoRepo);
    cancelar = CancelarComplementoPagoUseCase(complementoRepo);
  }

  Future<CuentaPorCobrarData> crearCuenta({String folio = 'MORGAN-SEP-2026', int importe = 10000000}) async {
    await db.into(db.documentoPorEmitir).insertOnConflictUpdate(
          DocumentoPorEmitirCompanion.insert(
            id: Value('doc-$folio'),
            codigo: 'DPE-$folio',
            generationKey: 'gk-$folio',
            clienteId: clienteId,
            tipoDocumento: 'cfdi',
            metodo: 'ppd',
            requiereComplemento: const Value(true),
            periodoInicio: DateTime(2026, 9, 1),
            periodoFin: DateTime(2026, 9, 30),
            agrupacion: 'porServicio',
            importeBaseEsperado: importe,
            importeFinalEsperado: importe,
          ),
        );
    return cuentaRepo.crear(
      documentoPorEmitirId: 'doc-$folio',
      clienteId: clienteId,
      tipoDocumento: 'cfdi',
      metodo: 'ppd',
      requiereComplemento: true,
      folioDocumento: folio,
      fechaEmisionReal: DateTime(2026, 9, 3),
      importeEmitido: importe,
    );
  }

  /// El Pago real de MORGAN: 12/10/2026, $100,000.00.
  Future<PagoData> crearPagoDeMorgan() async {
    final cuenta = await crearCuenta();
    final pago = await pagoRepo.crear(
      folioPago: 'PAG-000300',
      clienteId: clienteId,
      montoTotal: 10000000,
      fechaPago: DateTime(2026, 10, 12),
      formaPago: 'transferencia',
    );
    await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 10000000);
    return pago;
  }

  Future<bool> sigueOblig(String pagoId) async {
    final proyeccion = await obtenerPendientes.ejecutar();
    return proyeccion.pendientes.any((p) => p.pago.id == pagoId);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    montarSobre(db);
    final cliente = await ClienteRepositoryImpl(db).crear(
      ClienteCompanion.insert(codigo: 'CLI-000060', nombreComercial: 'MORGAN ATLACOMULCO'),
    );
    clienteId = cliente.id;
  });

  tearDown(() => db.close());

  group('Ciclo completo A → cancelar → B (caso MORGAN real)', () {
    test('los 9 pasos del ciclo, en orden', () async {
      final pago = await crearPagoDeMorgan();

      // 1. Pago sin Complemento → pendiente.
      expect(await sigueOblig(pago.id), isTrue);

      // 2. Registrar A → no pendiente.
      final a = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;
      expect(await sigueOblig(pago.id), isFalse);

      // 3. Cancelar A → pendiente otra vez.
      expect(
        await cancelar.ejecutar(complementoPagoId: a.id, motivo: 'Timbrado con RFC incorrecto'),
        isA<CancelarComplementoPagoExitoso>(),
      );
      expect(await sigueOblig(pago.id), isTrue);

      // 4. Registrar B (sustituto) → PERMITIDO, y deja de estar
      //    pendiente. Esto es exactamente lo que antes era imposible.
      final registroB = await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidB,
        fechaTimbrado: DateTime(2026, 10, 20),
        montoTotal: 10000000,
      );
      expect(
        registroB,
        isA<RegistrarComplementoPagoExitoso>(),
        reason: 'el sustituto es la razón de ser de esta etapa',
      );
      final b = (registroB as RegistrarComplementoPagoExitoso).complemento;
      expect(await sigueOblig(pago.id), isFalse);

      // 5. A sigue en el histórico, cancelado — nunca se borró ni se
      //    reusó.
      final historial = await complementoRepo.listarPorPagoId(pago.id);
      expect(historial, hasLength(2));
      final aPersistido = historial.firstWhere((c) => c.id == a.id);
      expect(aPersistido.estatus, EstatusComplementoPago.cancelado.name);
      expect(aPersistido.uuid, _uuidA, reason: 'su UUID original se conserva como evidencia');
      expect(aPersistido.motivoCancelacion, 'Timbrado con RFC incorrecto');

      // 6. B queda registrado y es el vigente.
      expect(historial.firstWhere((c) => c.id == b.id).estatus, EstatusComplementoPago.registrado.name);
      expect((await complementoRepo.obtenerVigentePorPagoId(pago.id))!.id, b.id);

      // 7. Intentar C mientras B está vigente → rechazado.
      expect(
        await registrar.ejecutar(
          pagoId: pago.id,
          uuid: _uuidC,
          fechaTimbrado: DateTime(2026, 10, 25),
          montoTotal: 10000000,
        ),
        isA<RegistrarComplementoPagoYaExiste>(),
      );
      expect(await complementoRepo.listarPorPagoId(pago.id), hasLength(2), reason: 'C no se creó');

      // 8. Cancelar B → pendiente otra vez.
      await cancelar.ejecutar(complementoPagoId: b.id, motivo: 'Monto mal capturado');
      expect(await sigueOblig(pago.id), isTrue);
      expect(await complementoRepo.obtenerVigentePorPagoId(pago.id), isNull);

      // 9. Registrar C después → permitido. Tres en el histórico, uno
      //    vigente.
      final c = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidC,
        fechaTimbrado: DateTime(2026, 10, 28),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;
      expect(await sigueOblig(pago.id), isFalse);

      final historialFinal = await complementoRepo.listarPorPagoId(pago.id);
      expect(historialFinal, hasLength(3));
      expect(
        historialFinal.map((h) => h.uuid).toSet(),
        {_uuidA, _uuidB, _uuidC},
        reason: 'ningún UUID histórico se perdió ni se reusó',
      );
      expect((await complementoRepo.obtenerVigentePorPagoId(pago.id))!.id, c.id);
      expect(
        historialFinal.where((h) => h.estatus == EstatusComplementoPago.registrado.name),
        hasLength(1),
        reason: 'jamás dos vigentes simultáneos',
      );
    });

    test('la BASE DE DATOS rechaza dos vigentes, aunque se salte el caso de uso', () async {
      final pago = await crearPagoDeMorgan();
      await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      );

      // Inserción directa, saltándose toda validación de dominio: el
      // índice único parcial es el candado final.
      await expectLater(
        db.into(db.complementoPago).insert(
              ComplementoPagoCompanion.insert(
                pagoId: pago.id,
                uuid: _uuidB,
                fechaTimbrado: DateTime(2026, 10, 20),
                montoTotal: 10000000,
              ),
            ),
        throwsA(anything),
      );
    });

    test('pero SÍ admite varios cancelados para el mismo Pago', () async {
      final pago = await crearPagoDeMorgan();
      for (final uuid in [_uuidA, _uuidB]) {
        final c = (await registrar.ejecutar(
          pagoId: pago.id,
          uuid: uuid,
          fechaTimbrado: DateTime(2026, 10, 15),
          montoTotal: 10000000,
        ) as RegistrarComplementoPagoExitoso)
            .complemento;
        await cancelar.ejecutar(complementoPagoId: c.id, motivo: 'Error');
      }

      final historial = await complementoRepo.listarPorPagoId(pago.id);
      expect(historial, hasLength(2));
      expect(historial.every((h) => h.estatus == EstatusComplementoPago.cancelado.name), isTrue);
      expect(await sigueOblig(pago.id), isTrue, reason: 'dos cancelados no documentan nada');
    });
  });

  group('complementoPendiente sobre el histórico', () {
    test('sólo un VIGENTE satisface la obligación', () async {
      final pago = await crearPagoDeMorgan();
      final a = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;

      var historial = await complementoRepo.listarPorPagoId(pago.id);
      expect(complementoPendiente(requiereComplemento: true, complementosDelPago: historial), isFalse);
      expect(complementoVigente(historial)!.id, a.id);

      await cancelar.ejecutar(complementoPagoId: a.id, motivo: 'Error');
      historial = await complementoRepo.listarPorPagoId(pago.id);
      expect(
        complementoPendiente(requiereComplemento: true, complementosDelPago: historial),
        isTrue,
        reason: 'si sólo existen cancelados, sigue pendiente',
      );
      expect(complementoVigente(historial), isNull);
    });

    test('sin obligación, el histórico da igual', () async {
      expect(complementoPendiente(requiereComplemento: false, complementosDelPago: const []), isFalse);
    });
  });

  group('Cero efectos financieros en todo el ciclo de sustitución', () {
    test('registrar A, cancelar A y registrar B dejan Caja/CxC/Pago/Ingreso idénticos', () async {
      final pago = await crearPagoDeMorgan();
      final cuentaId = (await pagoRepo.listarAplicacionesPorPago(pago.id)).first.cuentaPorCobrarId;

      Future<Map<String, Object?>> foto() async {
        final p = await pagoRepo.obtenerPorId(pago.id);
        final c = await cuentaRepo.obtenerPorId(cuentaId);
        return {
          'pago.montoTotal': p!.montoTotal,
          'pago.montoAplicado': p.montoAplicado,
          'pago.estatus': p.estatus,
          'pago.fechaPago': p.fechaPago,
          'cxc.saldoPendiente': c!.saldoPendiente,
          'cxc.estatus': c.estatus,
          'aplicaciones': (await pagoRepo.listarAplicacionesPorPago(pago.id)).map((a) => '${a.id}:${a.monto}:${a.estatus}').join('|'),
          'ingresos': (await db.select(db.ingreso).get()).length,
          'egresos': (await db.select(db.egreso).get()).length,
          'cuentasFinancieras': (await db.select(db.cuentaFinanciera).get()).length,
        };
      }

      final antes = await foto();

      final a = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;
      expect(await foto(), antes, reason: 'registrar A no mueve dinero');

      await cancelar.ejecutar(complementoPagoId: a.id, motivo: 'Error');
      expect(await foto(), antes, reason: 'cancelar A tampoco');

      await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidB,
        fechaTimbrado: DateTime(2026, 10, 20),
        montoTotal: 10000000,
      );
      expect(await foto(), antes, reason: 'el sustituto B tampoco');
    });
  });

  group('Reglas de bloqueo sobre el Pago, con el modelo nuevo', () {
    test('un Complemento CANCELADO ya no bloquea corregir ni cancelar el Pago', () async {
      final pago = await crearPagoDeMorgan();
      final corregir = CorregirPagoUseCase(pagoRepo, cuentaRepo, complementoRepo);
      final cancelarPago = CancelarPagoUseCase(pagoRepo, complementoRepo);

      final a = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;

      // Con A vigente: bloqueado (regla preexistente, intacta).
      expect(
        await corregir.ejecutar(pagoId: pago.id, fechaPago: DateTime(2026, 10, 13), motivo: 'Ajuste de fecha'),
        isA<CorregirPagoComplementoVigente>(),
      );
      expect(
        await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Devolución'),
        isA<CancelarPagoComplementoVigente>(),
      );

      // Cancelado A: ya no hay nada fiscal que congelar.
      await cancelar.ejecutar(complementoPagoId: a.id, motivo: 'Error');
      expect(
        await corregir.ejecutar(pagoId: pago.id, fechaPago: DateTime(2026, 10, 13), motivo: 'Ajuste de fecha'),
        isA<CorregirPagoExitoso>(),
        reason: 'un CFDI cancelado no documenta nada, así que no puede bloquear',
      );
    });

    test('la eliminación física sigue bloqueada por CUALQUIER Complemento histórico, sin reventar', () async {
      final pago = await crearPagoDeMorgan();
      // Dos Complementos históricos: antes esta consulta usaba
      // `getSingleOrNull()` y habría lanzado con el segundo.
      final a = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;
      await cancelar.ejecutar(complementoPagoId: a.id, motivo: 'Error');
      final b = (await registrar.ejecutar(
        pagoId: pago.id,
        uuid: _uuidB,
        fechaTimbrado: DateTime(2026, 10, 20),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;

      // El Pago debe estar cancelado para llegar al chequeo de
      // Complementos (el bloqueo por "Pago activo" va primero), y para
      // cancelarlo hay que cancelar antes su Complemento vigente.
      await cancelar.ejecutar(complementoPagoId: b.id, motivo: 'Error');
      expect(
        await CancelarPagoUseCase(pagoRepo, complementoRepo).ejecutar(pagoId: pago.id, motivo: 'Depósito devuelto'),
        isA<CancelarPagoExitoso>(),
      );

      final resumen = await pagoRepo.obtenerResumenEliminacionFisica(pago.id);
      expect(resumen.existe, isTrue);
      expect(
        resumen.detalleBloqueo,
        contains('2 Complementos de pago'),
        reason: 'dos CFDI cancelados siguen siendo historia real: bloquean el borrado y no revientan la consulta',
      );
    });
  });

  test('persistencia: reabrir SQLite conserva A/B/C e identifica el vigente', () async {
    await db.close();
    final dir = Directory.systemTemp.createTempSync('riseg_sustituto_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final archivo = File('${dir.path}/riseg.sqlite');

    final primera = AppDatabase(NativeDatabase(archivo));
    db = primera;
    montarSobre(primera);
    final cliente = await ClienteRepositoryImpl(primera).crear(
      ClienteCompanion.insert(codigo: 'CLI-000060', nombreComercial: 'MORGAN ATLACOMULCO'),
    );
    clienteId = cliente.id;

    final pago = await crearPagoDeMorgan();
    final a = (await registrar.ejecutar(
      pagoId: pago.id,
      uuid: _uuidA,
      fechaTimbrado: DateTime(2026, 10, 15),
      montoTotal: 10000000,
    ) as RegistrarComplementoPagoExitoso)
        .complemento;
    await cancelar.ejecutar(complementoPagoId: a.id, motivo: 'Error A');
    final b = (await registrar.ejecutar(
      pagoId: pago.id,
      uuid: _uuidB,
      fechaTimbrado: DateTime(2026, 10, 20),
      montoTotal: 10000000,
    ) as RegistrarComplementoPagoExitoso)
        .complemento;
    await cancelar.ejecutar(complementoPagoId: b.id, motivo: 'Error B');
    await registrar.ejecutar(
      pagoId: pago.id,
      uuid: _uuidC,
      fechaTimbrado: DateTime(2026, 10, 28),
      montoTotal: 10000000,
    );
    await primera.close();

    final segunda = AppDatabase(NativeDatabase(archivo));
    addTearDown(segunda.close);
    db = segunda;
    montarSobre(segunda);

    final historial = await complementoRepo.listarPorPagoId(pago.id);
    expect(historial, hasLength(3));
    expect(historial.map((h) => h.uuid).toSet(), {_uuidA, _uuidB, _uuidC});
    final vigente = await complementoRepo.obtenerVigentePorPagoId(pago.id);
    expect(vigente!.uuid, _uuidC);
    expect(await sigueOblig(pago.id), isFalse);

    // Y el índice parcial sobrevivió al cierre/apertura.
    final indices = await segunda
        .customSelect("SELECT name FROM sqlite_master WHERE type='index' AND name='complemento_pago_vigente_por_pago'")
        .get();
    expect(indices, hasLength(1), reason: 'el invariante vive en el esquema, no sólo en el código');
  });
}
