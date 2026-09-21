// Etapa "Complemento de pago dependiente del Pago real".
//
// Regla central: la obligación de Complemento **no nace de una fecha
// del calendario comercial**, nace de un Pago REAL aplicado a una
// Cuenta por cobrar PPD-con-complemento. "Pendiente" es una proyección
// derivada, nunca una fila de `ComplementoPago` ni un booleano cacheado.
//
// Deliberadamente NO existe "vencido": el sistema no tiene regla de
// plazo fiscal, y Marlon decidió no modelarla como preferencia
// comercial por cliente.

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
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';

/// UUIDs con el formato que exige `esUuidFormatoValido`.
const _uuidA = 'aaaaaaaa-1111-2222-3333-444444444444';
const _uuidB = 'bbbbbbbb-1111-2222-3333-444444444444';

void main() {
  late AppDatabase db;
  late PagoRepositoryImpl pagoRepo;
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late ComplementoPagoRepositoryImpl complementoRepo;
  late ObtenerComplementosPendientesUseCase obtenerPendientes;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late CancelarComplementoPagoUseCase cancelarComplemento;
  late String clienteId;
  var folioSecuencia = 0;

  void montarSobre(AppDatabase base) {
    pagoRepo = PagoRepositoryImpl(base);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(base);
    complementoRepo = ComplementoPagoRepositoryImpl(base);
    obtenerPendientes = ObtenerComplementosPendientesUseCase(pagoRepo, cuentaRepo, complementoRepo);
    registrarComplemento = RegistrarComplementoPagoUseCase(complementoRepo, pagoRepo);
    cancelarComplemento = CancelarComplementoPagoUseCase(complementoRepo);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    montarSobre(db);
    folioSecuencia = 0;
    final cliente = await ClienteRepositoryImpl(db).crear(
      ClienteCompanion.insert(codigo: 'CLI-000020', nombreComercial: 'MORGAN'),
    );
    clienteId = cliente.id;
  });

  tearDown(() => db.close());

  /// Una Cuenta por cobrar real. `documentoPorEmitirId` es FK, así que
  /// se crea el documento mínimo que la sostiene.
  Future<CuentaPorCobrarData> crearCuenta({
    required int importe,
    String metodo = 'ppd',
    bool requiereComplemento = true,
    String folio = 'A-001',
  }) async {
    final documentoId = 'doc-${folio.hashCode.abs()}';
    await db.into(db.documentoPorEmitir).insertOnConflictUpdate(
          DocumentoPorEmitirCompanion.insert(
            id: Value(documentoId),
            codigo: 'DPE-$folio',
            generationKey: 'gk-$folio',
            clienteId: clienteId,
            tipoDocumento: 'cfdi',
            metodo: metodo,
            requiereComplemento: Value(requiereComplemento),
            periodoInicio: DateTime(2026, 9, 1),
            periodoFin: DateTime(2026, 9, 30),
            agrupacion: 'porServicio',
            importeBaseEsperado: importe,
            importeFinalEsperado: importe,
          ),
        );

    return cuentaRepo.crear(
      documentoPorEmitirId: documentoId,
      clienteId: clienteId,
      tipoDocumento: 'cfdi',
      metodo: metodo,
      requiereComplemento: requiereComplemento,
      folioDocumento: folio,
      fechaEmisionReal: DateTime(2026, 9, 3),
      importeEmitido: importe,
    );
  }

  Future<PagoData> crearPagoAplicado({
    required int monto,
    required String cuentaId,
    DateTime? fecha,
  }) async {
    folioSecuencia++;
    final pago = await pagoRepo.crear(
      folioPago: 'PAG-${folioSecuencia.toString().padLeft(6, '0')}',
      clienteId: clienteId,
      montoTotal: monto,
      fechaPago: fecha ?? DateTime(2026, 10, 12),
      formaPago: 'transferencia',
    );
    await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: cuentaId, monto: monto);
    return pago;
  }

  group('La obligación nace del Pago real, no del calendario', () {
    test('PPD emitida SIN Pago → cero pendientes', () async {
      await crearCuenta(importe: 10000000);

      final proyeccion = await obtenerPendientes.ejecutar();

      expect(
        proyeccion.pendientes,
        isEmpty,
        reason: 'que exista la factura y llegue su fecha de pago esperado no crea ninguna obligación fiscal',
      );
      expect(await db.select(db.complementoPago).get(), isEmpty, reason: 'jamás una fila ficticia');
    });

    test('registrar el Pago real → nace UN pendiente, sin crear fila alguna', () async {
      final cuenta = await crearCuenta(importe: 10000000);
      final pago = await crearPagoAplicado(monto: 10000000, cuentaId: cuenta.id);

      final proyeccion = await obtenerPendientes.ejecutar();

      expect(proyeccion.pendientes, hasLength(1));
      expect(proyeccion.pendientes.single.pago.id, pago.id);
      expect(proyeccion.pendientes.single.cuentas.map((c) => c.id), [cuenta.id]);
      expect(
        await db.select(db.complementoPago).get(),
        isEmpty,
        reason: 'pendiente es una proyección: no persiste nada',
      );
    });

    test('registrar el Complemento → deja de estar pendiente', () async {
      final cuenta = await crearCuenta(importe: 10000000);
      final pago = await crearPagoAplicado(monto: 10000000, cuentaId: cuenta.id);

      final r = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 13),
        montoTotal: 10000000,
      );
      expect(r, isA<RegistrarComplementoPagoExitoso>());

      final proyeccion = await obtenerPendientes.ejecutar();
      expect(proyeccion.pendientes, isEmpty);
      expect(proyeccion.registrados, hasLength(1));
      expect(proyeccion.registrados.single.pago!.id, pago.id, reason: 'el Complemento conserva su vínculo al Pago');
      expect(proyeccion.registrados.single.cuentas.map((c) => c.id), [cuenta.id]);
    });

    test('cancelar el Complemento → vuelve a estar pendiente, y el Pago no cambia', () async {
      final cuenta = await crearCuenta(importe: 10000000);
      final pago = await crearPagoAplicado(monto: 10000000, cuentaId: cuenta.id);
      final registrado = (await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 13),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;

      final antes = await pagoRepo.obtenerPorId(pago.id);

      final cancelado = await cancelarComplemento.ejecutar(
        complementoPagoId: registrado.id,
        motivo: 'Timbrado con datos incorrectos',
      );
      expect(cancelado, isA<CancelarComplementoPagoExitoso>());

      final proyeccion = await obtenerPendientes.ejecutar();
      expect(proyeccion.pendientes, hasLength(1), reason: 'un Complemento cancelado no cumple la obligación');

      final despues = await pagoRepo.obtenerPorId(pago.id);
      expect(despues!.montoTotal, antes!.montoTotal);
      expect(despues.montoAplicado, antes.montoAplicado);
      expect(despues.estatus, antes.estatus);
      expect(despues.fechaPago, antes.fechaPago);

    });

    // GAP CERRADO en schemaVersion 79. Esta prueba nació fijando el
    // callejón sin salida ("tras cancelar NO se puede registrar un
    // sustituto") y falló en cuanto se corrigió — exactamente lo que se
    // esperaba de ella. Ahora fija el comportamiento correcto.
    //
    // El ciclo completo (A → cancelar → B → rechazo de C → cancelar B →
    // C permitido), la persistencia y los efectos financieros viven en
    // `complemento_sustituto_test.dart`; aquí sólo se comprueba que la
    // proyección de pendientes acompaña la sustitución.
    test('tras cancelar SÍ se puede registrar un sustituto, y la obligación queda cumplida', () async {
      final cuenta = await crearCuenta(importe: 10000000);
      final pago = await crearPagoAplicado(monto: 10000000, cuentaId: cuenta.id);
      final registrado = (await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 13),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;
      await cancelarComplemento.ejecutar(complementoPagoId: registrado.id, motivo: 'Timbrado incorrecto');

      final sustituto = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidB,
        fechaTimbrado: DateTime(2026, 10, 20),
        montoTotal: 10000000,
      );

      expect(
        sustituto,
        isA<RegistrarComplementoPagoExitoso>(),
        reason: 'una fila cancelada ya no ocupa el lugar del vigente',
      );
      expect(
        (await obtenerPendientes.ejecutar()).pendientes,
        isEmpty,
        reason: 'el sustituto cumple la obligación que la cancelación había reactivado',
      );
      // Y el cancelado sigue en el histórico, no se reusó ni se borró.
      expect(await complementoRepo.listarPorPagoId(pago.id), hasLength(2));
    });

    test('PUE jamás genera pendiente, aunque el dato traiga requiereComplemento', () async {
      // Combinación contradictoria forzada a mano: aunque exista en
      // datos viejos, `cuentaRequiereComplemento` exige PPD.
      final cuenta = await crearCuenta(importe: 5000000, metodo: 'pue', requiereComplemento: true, folio: 'B-001');
      await crearPagoAplicado(monto: 5000000, cuentaId: cuenta.id);

      expect((await obtenerPendientes.ejecutar()).pendientes, isEmpty);
    });

    test('un Pago cancelado no sostiene ninguna obligación', () async {
      final cuenta = await crearCuenta(importe: 10000000);
      final pago = await crearPagoAplicado(monto: 10000000, cuentaId: cuenta.id);
      expect((await obtenerPendientes.ejecutar()).pendientes, hasLength(1));

      await pagoRepo.cancelar(pagoId: pago.id, motivo: 'Depósito devuelto');

      expect((await obtenerPendientes.ejecutar()).pendientes, isEmpty);
    });
  });

  group('Cardinalidad — la obligación es POR PAGO', () {
    test('pago parcial: A y B generan DOS obligaciones independientes', () async {
      final cuenta = await crearCuenta(importe: 10000000); // $100,000.00

      final pagoA = await crearPagoAplicado(monto: 4000000, cuentaId: cuenta.id, fecha: DateTime(2026, 10, 12));
      expect(
        (await obtenerPendientes.ejecutar()).pendientes.map((p) => p.pago.id),
        [pagoA.id],
        reason: 'la obligación nace con el primer pago, sin esperar a que la factura quede liquidada',
      );

      await registrarComplemento.ejecutar(
        pagoId: pagoA.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 13),
        montoTotal: 4000000,
      );
      expect((await obtenerPendientes.ejecutar()).pendientes, isEmpty);

      final pagoB = await crearPagoAplicado(monto: 6000000, cuentaId: cuenta.id, fecha: DateTime(2026, 11, 10));
      expect((await obtenerPendientes.ejecutar()).pendientes.map((p) => p.pago.id), [pagoB.id]);

      await registrarComplemento.ejecutar(
        pagoId: pagoB.id,
        uuid: _uuidB,
        fechaTimbrado: DateTime(2026, 11, 11),
        montoTotal: 6000000,
      );

      final proyeccion = await obtenerPendientes.ejecutar();
      expect(proyeccion.pendientes, isEmpty);
      expect(proyeccion.registrados, hasLength(2), reason: 'trazabilidad independiente por Pago');
      expect(
        proyeccion.registrados.map((c) => c.pago!.id).toSet(),
        {pagoA.id, pagoB.id},
      );

      // La Cuenta quedó saldada por los dos pagos.
      final cuentaFinal = await cuentaRepo.obtenerPorId(cuenta.id);
      expect(cuentaFinal!.saldoPendiente, 0);
    });

    test('un Pago aplicado a VARIAS CxC = UNA obligación, con todas las cuentas visibles', () async {
      final cuentaA = await crearCuenta(importe: 1000000, folio: 'F-A');
      final cuentaB = await crearCuenta(importe: 2000000, folio: 'F-B');

      folioSecuencia++;
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000900',
        clienteId: clienteId,
        montoTotal: 3000000,
        fechaPago: DateTime(2026, 10, 12),
        formaPago: 'transferencia',
      );
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: cuentaA.id, monto: 1000000);
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: cuentaB.id, monto: 2000000);

      final proyeccion = await obtenerPendientes.ejecutar();

      expect(proyeccion.pendientes, hasLength(1), reason: 'un Pago = una obligación, nunca una por factura');
      expect(
        proyeccion.pendientes.single.cuentas.map((c) => c.folioDocumento).toSet(),
        {'F-A', 'F-B'},
        reason: 'las dos facturas cubiertas se ven, derivadas de las aplicaciones activas',
      );

      // Y el Complemento registrado presenta las mismas dos.
      await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 13),
        montoTotal: 3000000,
      );
      final despues = await obtenerPendientes.ejecutar();
      expect(despues.registrados.single.cuentas.map((c) => c.folioDocumento).toSet(), {'F-A', 'F-B'});
      expect(await db.select(db.complementoPago).get(), hasLength(1), reason: 'nunca dos documentos por un Pago');
    });

    test('basta UNA cuenta PPD entre las aplicadas para que nazca la obligación', () async {
      final ppd = await crearCuenta(importe: 1000000, folio: 'G-PPD');
      final pue = await crearCuenta(importe: 1000000, metodo: 'pue', requiereComplemento: false, folio: 'G-PUE');

      final pago = await pagoRepo.crear(
        folioPago: 'PAG-000901',
        clienteId: clienteId,
        montoTotal: 2000000,
        fechaPago: DateTime(2026, 10, 12),
        formaPago: 'transferencia',
      );
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: ppd.id, monto: 1000000);
      await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: pue.id, monto: 1000000);

      final proyeccion = await obtenerPendientes.ejecutar();
      expect(proyeccion.pendientes, hasLength(1));
      expect(proyeccion.pendientes.single.cuentasQueExigenComplemento.map((c) => c.folioDocumento), ['G-PPD']);
      expect(proyeccion.pendientes.single.cuentas, hasLength(2), reason: 'el documento reporta el Pago completo');
    });
  });

  group('Cero efectos financieros — el Complemento sólo documenta', () {
    test('registrar y cancelar no tocan Caja, CxC, Ingreso, Egreso ni el Pago', () async {
      final cuenta = await crearCuenta(importe: 10000000);
      final pago = await crearPagoAplicado(monto: 10000000, cuentaId: cuenta.id);

      Future<Map<String, Object?>> foto() async {
        final p = await pagoRepo.obtenerPorId(pago.id);
        final c = await cuentaRepo.obtenerPorId(cuenta.id);
        return {
          'pago.montoTotal': p!.montoTotal,
          'pago.montoAplicado': p.montoAplicado,
          'pago.estatus': p.estatus,
          'cxc.saldoPendiente': c!.saldoPendiente,
          'cxc.estatus': c.estatus,
          'aplicaciones': (await pagoRepo.listarAplicacionesPorPago(pago.id)).length,
          'ingresos': (await db.select(db.ingreso).get()).length,
          'egresos': (await db.select(db.egreso).get()).length,
          'cuentasFinancieras': (await db.select(db.cuentaFinanciera).get()).length,
        };
      }

      final antes = await foto();

      final registrado = (await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 13),
        montoTotal: 10000000,
      ) as RegistrarComplementoPagoExitoso)
          .complemento;
      expect(await foto(), antes, reason: 'registrar un Complemento es documentación fiscal, no un movimiento');

      await cancelarComplemento.ejecutar(complementoPagoId: registrado.id, motivo: 'Error de captura');
      expect(await foto(), antes, reason: 'cancelarlo tampoco mueve dinero');
    });
  });

  group('CASO MORGAN — esperado 09/10, real 12/10', () {
    test('el pago esperado y el pago real conviven sin incoherencia', () async {
      // La fecha comercial 09/10/2026 vive en la Configuración de cobro
      // y en el documento; no interviene aquí para nada. La obligación
      // sólo mira el Pago real.
      final cuenta = await crearCuenta(importe: 10000000, folio: 'MORGAN-SEP-2026');

      // Antes del Pago: nada pendiente, ni siquiera pasado el 09/10.
      expect((await obtenerPendientes.ejecutar()).pendientes, isEmpty);

      final pago = await crearPagoAplicado(
        monto: 10000000,
        cuentaId: cuenta.id,
        fecha: DateTime(2026, 10, 12),
      );

      final pendiente = (await obtenerPendientes.ejecutar()).pendientes.single;
      expect(pendiente.pago.fechaPago, DateTime(2026, 10, 12), reason: 'la obligación se ancla al pago REAL');
      expect(pendiente.cuentas.single.folioDocumento, 'MORGAN-SEP-2026');

      // Timbrar: sale de pendientes, permanece en historial ligado al Pago.
      await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: _uuidA,
        fechaTimbrado: DateTime(2026, 10, 15),
        montoTotal: 10000000,
      );
      final despues = await obtenerPendientes.ejecutar();
      expect(despues.pendientes, isEmpty);
      expect(despues.registrados.single.pago!.fechaPago, DateTime(2026, 10, 12));
      expect(despues.registrados.single.complemento.fechaTimbrado, DateTime(2026, 10, 15));
    });

    test('no existe ninguna noción de "vencido"', () {
      // El enum persistido sólo tiene dos valores. Si alguna vez se
      // agrega "vencido", esta prueba obliga a revisar la decisión de
      // producto que lo prohibió (no hay regla de plazo fiscal).
      expect(EstatusComplementoPago.values.map((e) => e.name), ['registrado', 'cancelado']);
    });
  });

  test('persistencia: reabrir la base conserva pendientes y registrados', () async {
    await db.close();
    final dir = Directory.systemTemp.createTempSync('riseg_complemento_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final archivo = File('${dir.path}/riseg.sqlite');

    final primera = AppDatabase(NativeDatabase(archivo));
    montarSobre(primera);
    final cliente = await ClienteRepositoryImpl(primera).crear(
      ClienteCompanion.insert(codigo: 'CLI-000020', nombreComercial: 'MORGAN'),
    );
    clienteId = cliente.id;
    db = primera;

    final cuentaA = await crearCuenta(importe: 4000000, folio: 'P-A');
    final cuentaB = await crearCuenta(importe: 6000000, folio: 'P-B');
    final pagoA = await crearPagoAplicado(monto: 4000000, cuentaId: cuentaA.id);
    await crearPagoAplicado(monto: 6000000, cuentaId: cuentaB.id);
    await registrarComplemento.ejecutar(
      pagoId: pagoA.id,
      uuid: _uuidA,
      fechaTimbrado: DateTime(2026, 10, 13),
      montoTotal: 4000000,
    );
    await primera.close();

    final segunda = AppDatabase(NativeDatabase(archivo));
    addTearDown(segunda.close);
    montarSobre(segunda);
    db = segunda;

    final proyeccion = await obtenerPendientes.ejecutar();
    expect(proyeccion.pendientes, hasLength(1), reason: 'el pago B sigue sin complemento');
    expect(proyeccion.pendientes.single.cuentas.single.folioDocumento, 'P-B');
    expect(proyeccion.registrados, hasLength(1));
    expect(proyeccion.registrados.single.complemento.uuid, _uuidA);
  });
}
