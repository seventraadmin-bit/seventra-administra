// Etapa 19 — "Deudas y crédito empresarial". Cubre los escenarios
// reales del pedido (Parte 12): tarjeta de crédito con pago parcial,
// préstamo con saldo histórico migrado (sin generar Egreso falso),
// préstamo liquidado a saldo 0, dos pagos parciales sucesivos, pago
// mayor al saldo bloqueado sin mutar ningún dato, cancelación que
// preserva el historial, el Egreso creado exactamente una vez por
// pago, y eliminación física sin dejar MovimientoDeuda/Egreso
// huérfano.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_deuda_fisicamente_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';

void main() {
  late AppDatabase db;
  late DeudaRepositoryImpl deudaRepo;
  late EgresoRepositoryImpl egresoRepo;
  late RegistrarDeudaUseCase registrarDeuda;
  late RegistrarPagoDeudaUseCase registrarPago;
  late CancelarDeudaUseCase cancelarDeuda;
  late EliminarDeudaFisicamenteUseCase eliminarFisicamente;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    registrarPago = RegistrarPagoDeudaUseCase(deudaRepo, generarCodigo);
    cancelarDeuda = CancelarDeudaUseCase(deudaRepo);
    eliminarFisicamente = EliminarDeudaFisicamenteUseCase(deudaRepo);
  });

  tearDown(() => db.close());

  Future<DeudaData> deudaDePrueba({
    String nombre = 'TDC BBVA',
    String tipo = 'tarjetaCredito',
    required int importeOriginal,
    int? saldoInicial,
  }) async {
    final resultado = await registrarDeuda.ejecutar(
      nombre: nombre,
      tipo: tipo,
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: importeOriginal,
      saldoInicial: saldoInicial ?? importeOriginal,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  Future<int> contarMovimientos(String deudaId) async {
    final movimientos = await deudaRepo.listarMovimientos(deudaId);
    return movimientos.length;
  }

  Future<int> contarEgresos() async {
    final egresos = await db.select(db.egreso).get();
    return egresos.length;
  }

  test('1. TDC BBVA: alta 36,000, pago 15,000, saldo 21,000 y el Egreso queda vinculado', () async {
    final deuda = await deudaDePrueba(importeOriginal: 3600000);
    expect(deuda.saldoActual, 3600000);
    expect(deuda.estatus, EstatusDeuda.activa.name);

    final resultado = await registrarPago.ejecutar(
      deudaId: deuda.id,
      fecha: DateTime(2026, 2, 1),
      importe: 1500000,
      formaPago: 'transferencia',
    );
    final actualizada = (resultado as RegistrarPagoDeudaExitoso).deuda;
    expect(actualizada.saldoActual, 2100000);
    expect(actualizada.estatus, EstatusDeuda.activa.name);

    final movimientos = await deudaRepo.listarMovimientos(deuda.id);
    expect(movimientos, hasLength(2), reason: 'altaInicial + pago');
    final pago = movimientos.last;
    expect(pago.tipo, TipoMovimientoDeuda.pago.name);
    expect(pago.saldoAnterior, 3600000);
    expect(pago.saldoPosterior, 2100000);
    expect(pago.egresoId, isNotNull);

    final egreso = await egresoRepo.obtenerPorId(pago.egresoId!);
    expect(egreso, isNotNull);
    expect(egreso!.monto, 1500000);
    expect(egreso.concepto, contains(deuda.folio));
  });

  test('2. Préstamo con saldo histórico migrado: el alta NO genera Egreso, y un pago posterior sí reduce el saldo real', () async {
    final deuda = await deudaDePrueba(nombre: 'Préstamo Jessica', tipo: 'prestamo', importeOriginal: 9000000, saldoInicial: 8000000);
    expect(deuda.saldoActual, 8000000, reason: 'saldo inicial migrado, no el importe original completo');
    expect(await contarEgresos(), 0, reason: 'incorporar una deuda histórica nunca debe crear un Egreso falso');

    final movimientosAlAlta = await deudaRepo.listarMovimientos(deuda.id);
    expect(movimientosAlAlta, hasLength(1));
    expect(movimientosAlAlta.single.tipo, TipoMovimientoDeuda.altaInicial.name);
    expect(movimientosAlAlta.single.egresoId, isNull, reason: 'el alta histórica nunca genera Egreso');
    expect(movimientosAlAlta.single.saldoAnterior, 0);
    expect(movimientosAlAlta.single.saldoPosterior, 8000000);

    final resultado = await registrarPago.ejecutar(
      deudaId: deuda.id,
      fecha: DateTime(2026, 3, 1),
      importe: 1000000,
      formaPago: 'efectivo',
    );
    final actualizada = (resultado as RegistrarPagoDeudaExitoso).deuda;
    expect(actualizada.saldoActual, 7000000);
    expect(await contarEgresos(), 1, reason: 'ahora sí hay exactamente un Egreso — el del pago real posterior');
  });

  test('3. Préstamo BBVA: pago total liquida la deuda a saldo 0 y cambia el estatus', () async {
    final deuda = await deudaDePrueba(nombre: 'Préstamo BBVA', tipo: 'prestamo', importeOriginal: 5700000);

    final resultado = await registrarPago.ejecutar(
      deudaId: deuda.id,
      fecha: DateTime(2026, 2, 1),
      importe: 5700000,
      formaPago: 'transferencia',
    );
    final actualizada = (resultado as RegistrarPagoDeudaExitoso).deuda;
    expect(actualizada.saldoActual, 0);
    expect(actualizada.estatus, EstatusDeuda.liquidada.name);
  });

  test('4. Dos pagos parciales sucesivos reducen el saldo correctamente en cada paso', () async {
    final deuda = await deudaDePrueba(importeOriginal: 10000000);

    final r1 = await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 2, 1), importe: 3000000, formaPago: 'efectivo');
    final d1 = (r1 as RegistrarPagoDeudaExitoso).deuda;
    expect(d1.saldoActual, 7000000);

    final r2 = await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 3, 1), importe: 2000000, formaPago: 'efectivo');
    final d2 = (r2 as RegistrarPagoDeudaExitoso).deuda;
    expect(d2.saldoActual, 5000000);

    final movimientos = await deudaRepo.listarMovimientos(deuda.id);
    expect(movimientos, hasLength(3), reason: 'altaInicial + 2 pagos');
    expect(await contarEgresos(), 2);
  });

  test('5. Un pago mayor al saldo actual se bloquea sin mutar ningún dato', () async {
    final deuda = await deudaDePrueba(importeOriginal: 1000000);

    final resultado = await registrarPago.ejecutar(
      deudaId: deuda.id,
      fecha: DateTime(2026, 2, 1),
      importe: 1000001,
      formaPago: 'efectivo',
    );
    expect(resultado, isA<RegistrarPagoDeudaSobrepasaSaldo>());
    expect((resultado as RegistrarPagoDeudaSobrepasaSaldo).saldoActual, 1000000);

    final sinCambios = await deudaRepo.obtenerPorId(deuda.id);
    expect(sinCambios!.saldoActual, 1000000, reason: 'nada debe mutarse cuando el pago se rechaza');
    expect(await contarMovimientos(deuda.id), 1, reason: 'solo el movimiento de altaInicial, ningún pago fantasma');
    expect(await contarEgresos(), 0, reason: 'ningún Egreso debe crearse cuando el pago se rechaza');
  });

  test('6. Cancelar una deuda con historial preserva todos los movimientos y condona el saldo restante', () async {
    final deuda = await deudaDePrueba(importeOriginal: 5000000);
    await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 2, 1), importe: 1000000, formaPago: 'efectivo');

    final resultado = await cancelarDeuda.ejecutar(deudaId: deuda.id, motivo: 'Negociación con el acreedor');
    final cancelada = (resultado as CancelarDeudaExitoso).deuda;
    expect(cancelada.saldoActual, 0);
    expect(cancelada.estatus, EstatusDeuda.cancelada.name);
    expect(cancelada.motivoCancelacion, 'Negociación con el acreedor');

    final movimientos = await deudaRepo.listarMovimientos(deuda.id);
    expect(movimientos, hasLength(3), reason: 'altaInicial + pago + cancelación — nada del historial se borra');
    expect(movimientos.last.tipo, TipoMovimientoDeuda.cancelacion.name);
    expect(movimientos.last.saldoAnterior, 4000000);
    expect(movimientos.last.saldoPosterior, 0);

    // No permite un pago posterior a una deuda ya cancelada.
    final intento = await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 3, 1), importe: 100000, formaPago: 'efectivo');
    expect(intento, isA<RegistrarPagoDeudaNoActiva>());
  });

  test('7. Cada pago genera exactamente un Egreso — nunca duplicado, nunca compartido entre pagos distintos', () async {
    final deuda = await deudaDePrueba(importeOriginal: 10000000);
    await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 2, 1), importe: 2000000, formaPago: 'efectivo');
    await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 3, 1), importe: 2000000, formaPago: 'efectivo');

    final movimientos = await deudaRepo.listarMovimientos(deuda.id);
    final pagos = movimientos.where((m) => m.tipo == TipoMovimientoDeuda.pago.name).toList();
    expect(pagos, hasLength(2));
    expect(pagos[0].egresoId, isNot(equals(pagos[1].egresoId)), reason: 'cada pago tiene su propio Egreso, nunca compartido');
    expect(await contarEgresos(), 2, reason: 'ni un Egreso de más ni de menos');
  });

  test('8. Eliminación física borra Deuda + MovimientoDeuda + sus Egresos, sin dejar huérfanos', () async {
    final deuda = await deudaDePrueba(importeOriginal: 5000000);
    final pagoResultado = await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 2, 1), importe: 1000000, formaPago: 'efectivo');
    final egresoId = (await deudaRepo.listarMovimientos(deuda.id)).last.egresoId!;
    expect(pagoResultado, isA<RegistrarPagoDeudaExitoso>());

    final resultado = await eliminarFisicamente.ejecutar(deudaId: deuda.id, motivo: 'Registro de prueba');
    expect(resultado, isA<EliminarDeudaFisicamenteExitoso>());

    expect(await deudaRepo.obtenerPorId(deuda.id), isNull);
    expect(await deudaRepo.listarMovimientos(deuda.id), isEmpty, reason: 'ningún MovimientoDeuda huérfano');
    expect(await egresoRepo.obtenerPorId(egresoId), isNull, reason: 'ningún Egreso huérfano');

    final snapshot = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(deuda.id))).getSingle();
    expect(snapshot.tipoEntidad, 'deuda');
    expect(snapshot.motivo, 'Registro de prueba');
  });

  test('registrarDeuda valida nombre/importe/saldoInicial antes de escribir cualquier dato', () async {
    final sinNombre = await registrarDeuda.ejecutar(
      nombre: '   ',
      tipo: 'otro',
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      saldoInicial: 100000,
    );
    expect(sinNombre, isA<RegistrarDeudaNombreRequerido>());

    final importeInvalido = await registrarDeuda.ejecutar(
      nombre: 'Deuda de prueba',
      tipo: 'otro',
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: 0,
      saldoInicial: 0,
    );
    expect(importeInvalido, isA<RegistrarDeudaImporteInvalido>());

    final saldoInvalido = await registrarDeuda.ejecutar(
      nombre: 'Deuda de prueba',
      tipo: 'otro',
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: 100000,
      saldoInicial: 200000,
    );
    expect(saldoInvalido, isA<RegistrarDeudaSaldoInicialInvalido>());

    expect((await deudaRepo.listar()), isEmpty, reason: 'ningún intento inválido debe llegar a persistirse');
  });

  test('listarEgresoIdsDePagosEnRango solo incluye los Egresos generados por pagos de deuda, filtrados por fecha', () async {
    final deuda = await deudaDePrueba(importeOriginal: 10000000);
    await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 1, 15), importe: 1000000, formaPago: 'efectivo');
    await registrarPago.ejecutar(deudaId: deuda.id, fecha: DateTime(2026, 3, 15), importe: 1000000, formaPago: 'efectivo');

    final idsEnero = await deudaRepo.listarEgresoIdsDePagosEnRango(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
    expect(idsEnero, hasLength(1));

    final idsTodos = await deudaRepo.listarEgresoIdsDePagosEnRango();
    expect(idsTodos, hasLength(2));
  });
}
