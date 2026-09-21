// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC).
// Sustituye a `corregir_compra_forma_pago_modelo_test.dart`, que
// probaba el bloqueo artificial retirado en esta etapa. Cubre las 6
// transiciones de origen (A-F), el cambio simultáneo de monto+origen,
// el rechazo por crédito insuficiente y la atomicidad real (rollback
// de una transición D a mitad de operación) — todo contra BD real
// (`NativeDatabase.memory()`), nunca mocks.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late DeudaRepositoryImpl deudaRepo;
  late EgresoRepositoryImpl egresoRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CorregirCompraUseCase corregirCompra;
  var contadorCuenta = 0;
  var contadorTarjeta = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo);
  });

  tearDown(() => db.close());

  Future<CuentaFinancieraData> crearCuenta({String nombre = 'BBVA', int saldoInicial = 5000000}) {
    contadorCuenta++;
    return cuentaFinancieraRepo.crear(
      codigo: 'CTA-${contadorCuenta.toString().padLeft(6, '0')}',
      nombre: nombre,
      tipo: TipoCuentaFinanciera.banco.name,
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
  }

  Future<DeudaData> crearTarjeta({String nombre = 'Konfío', int limiteCredito = 4000000}) async {
    contadorTarjeta++;
    final resultado = await RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
      nombre: '$nombre $contadorTarjeta',
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: 0,
      tarjetaLimiteCredito: limiteCredito,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  List<PartidaCompraInput> partidasDe(int costoUnitario) =>
      [PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: costoUnitario)];

  Future<int> netoEnDeuda(String deudaId, String compraId) => deudaRepo.netoAportadoPorCompra(deudaId: deudaId, compraId: compraId);

  test('A. Cuenta -> misma Cuenta: corrige el monto del Egreso existente, nunca crea un segundo', () async {
    final cuenta = await crearCuenta();
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
      partidas: partidasDe(50000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(
      compraId: creada.id,
      cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: (await compraRepo.listarPartidas(creada.id)).single.id, nuevoCostoUnitario: 65000)],
      nuevaCuentaFinancieraId: cuenta.id,
      motivo: 'Monto real de la factura',
    );

    expect(resultado, isA<CorregirCompraExitosa>());
    final actual = (resultado as CorregirCompraExitosa).compra;
    expect(actual.egresoId, creada.egresoId, reason: 'reutiliza el mismo Egreso, nunca crea un segundo');
    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1));
    expect(egresos.single.monto, 65000);
  });

  test('B. Cuenta A -> Cuenta B: reutiliza el mismo Egreso vía cuentaFinancieraId, no cancela+crea', () async {
    final cuentaA = await crearCuenta(nombre: 'BBVA');
    final cuentaB = await crearCuenta(nombre: 'Clara');
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuentaA.id,
      partidas: partidasDe(150000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(compraId: creada.id, nuevaCuentaFinancieraId: cuentaB.id, motivo: 'Se pagó realmente con Clara');

    expect(resultado, isA<CorregirCompraExitosa>());
    final actual = (resultado as CorregirCompraExitosa).compra;
    expect(actual.egresoId, creada.egresoId, reason: 'mismo Egreso, solo cambia cuentaFinancieraId');
    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1));
    expect(egresos.single.cuentaFinancieraId, cuentaB.id);
    expect(egresos.single.estatus, 'registrado');
    expect(egresos.single.monto, 150000, reason: 'el gasto reconocido no cambia solo por mover de cuenta');
  });

  test('C. TDC -> misma TDC, monto aumenta: ajuste positivo por la diferencia, nunca reescribe el cargo original', () async {
    final tarjeta = await crearTarjeta();
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.tarjeta.name,
      deudaId: tarjeta.id,
      partidas: partidasDe(200000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(
      compraId: creada.id,
      cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: (await compraRepo.listarPartidas(creada.id)).single.id, nuevoCostoUnitario: 250000)],
      nuevaDeudaId: tarjeta.id,
      motivo: 'El monto real fue mayor',
    );

    expect(resultado, isA<CorregirCompraExitosa>());
    expect((resultado as CorregirCompraExitosa).compra.deudaId, tarjeta.id);
    final movimientos = await (db.select(db.movimientoDeuda)..where((t) => t.compraId.equals(creada.id))).get();
    expect(movimientos.map((m) => m.tipo), containsAll(['cargoCompra', 'ajustePositivo']));
    expect(movimientos.firstWhere((m) => m.tipo == 'cargoCompra').importe, 200000, reason: 'el cargo original nunca se reescribe');
    final tarjetaTras = await deudaRepo.obtenerPorId(tarjeta.id);
    expect(tarjetaTras!.saldoActual, 250000);
    expect(await netoEnDeuda(tarjeta.id, creada.id), 250000);
  });

  test('C. TDC -> misma TDC, monto disminuye: ajuste negativo por la diferencia', () async {
    final tarjeta = await crearTarjeta();
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.tarjeta.name,
      deudaId: tarjeta.id,
      partidas: partidasDe(200000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(
      compraId: creada.id,
      cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: (await compraRepo.listarPartidas(creada.id)).single.id, nuevoCostoUnitario: 120000)],
      nuevaDeudaId: tarjeta.id,
      motivo: 'Se aplicó un descuento no capturado',
    );

    expect(resultado, isA<CorregirCompraExitosa>());
    final tarjetaTras = await deudaRepo.obtenerPorId(tarjeta.id);
    expect(tarjetaTras!.saldoActual, 120000);
    expect(await netoEnDeuda(tarjeta.id, creada.id), 120000);
  });

  test(
    'Ejemplo explícito de la Sección 5: límite \$10,000, saldo \$9,000 (de los cuales \$2,000 son de la propia '
    'Compra) — corregir esa Compra a \$2,500 en la MISMA TDC no debe compararse contra solo \$1,000 disponible',
    () async {
      final tarjeta = await crearTarjeta(limiteCredito: 1000000);
      final otraCompra = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 1),
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjeta.id,
        partidas: partidasDe(700000),
      ) as RegistrarCompraExitosa)
          .compra;
      final creada = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjeta.id,
        partidas: partidasDe(200000),
      ) as RegistrarCompraExitosa)
          .compra;
      final tarjetaAntes = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(tarjetaAntes!.saldoActual, 900000, reason: 'saldo de \$9,000 = \$7,000 (otra compra) + \$2,000 (la propia)');

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: (await compraRepo.listarPartidas(creada.id)).single.id, nuevoCostoUnitario: 250000)],
        nuevaDeudaId: tarjeta.id,
        motivo: 'Ajuste al alza',
      );

      expect(resultado, isA<CorregirCompraExitosa>(), reason: '250000 <= (1000000-700000)+200000=500000 disponible neteando la propia compra');
      final tarjetaTras = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(tarjetaTras!.saldoActual, 950000, reason: '700000 (otra compra) + 250000 (la propia, corregida)');
      expect(await netoEnDeuda(tarjeta.id, otraCompra.id), 700000, reason: 'la otra Compra nunca se toca');
    },
  );

  test('D. TDC X -> TDC Y: revierte completamente en X, registra cargo completo en Y, una sola operación', () async {
    final tarjetaX = await crearTarjeta(nombre: 'Konfío');
    final tarjetaY = await crearTarjeta(nombre: 'Clara');
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.tarjeta.name,
      deudaId: tarjetaX.id,
      partidas: partidasDe(300000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: tarjetaY.id, motivo: 'Se pagó realmente con Clara');

    expect(resultado, isA<CorregirCompraExitosa>());
    expect((resultado as CorregirCompraExitosa).compra.deudaId, tarjetaY.id);
    final tarjetaXTras = await deudaRepo.obtenerPorId(tarjetaX.id);
    final tarjetaYTras = await deudaRepo.obtenerPorId(tarjetaY.id);
    expect(tarjetaXTras!.saldoActual, 0, reason: 'X queda en neto cero por esta Compra');
    expect(tarjetaYTras!.saldoActual, 300000);
    expect(await netoEnDeuda(tarjetaX.id, creada.id), 0);
    expect(await netoEnDeuda(tarjetaY.id, creada.id), 300000);
  });

  test('E. Cuenta -> TDC: cancela el Egreso, egresoId->null, registra cargo, deudaId->nueva tarjeta', () async {
    final cuenta = await crearCuenta();
    final tarjeta = await crearTarjeta();
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
      partidas: partidasDe(180000),
    ) as RegistrarCompraExitosa)
        .compra;
    final egresoOriginalId = creada.egresoId!;

    final resultado = await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: tarjeta.id, motivo: 'En realidad se pagó con tarjeta');

    expect(resultado, isA<CorregirCompraExitosa>());
    final actual = (resultado as CorregirCompraExitosa).compra;
    expect(actual.egresoId, isNull);
    expect(actual.deudaId, tarjeta.id);
    final egresoOriginal = await egresoRepo.obtenerPorId(egresoOriginalId);
    expect(egresoOriginal!.estatus, 'cancelado', reason: 'el Egreso original se conserva cancelado, nunca se borra');
    final tarjetaTras = await deudaRepo.obtenerPorId(tarjeta.id);
    expect(tarjetaTras!.saldoActual, 180000);
  });

  test('F. TDC -> Cuenta: revierte el cargo, deudaId->null, crea Egreso nuevo, egresoId->nuevo', () async {
    final tarjeta = await crearTarjeta();
    final cuenta = await crearCuenta();
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.tarjeta.name,
      deudaId: tarjeta.id,
      partidas: partidasDe(220000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(compraId: creada.id, nuevaCuentaFinancieraId: cuenta.id, motivo: 'En realidad se pagó de contado');

    expect(resultado, isA<CorregirCompraExitosa>());
    final actual = (resultado as CorregirCompraExitosa).compra;
    expect(actual.deudaId, isNull);
    expect(actual.egresoId, isNotNull);
    expect(actual.egresoId, isNot(equals(creada.egresoId)));
    final tarjetaTras = await deudaRepo.obtenerPorId(tarjeta.id);
    expect(tarjetaTras!.saldoActual, 0);
    final egresoNuevo = await egresoRepo.obtenerPorId(actual.egresoId!);
    expect(egresoNuevo!.cuentaFinancieraId, cuenta.id);
    expect(egresoNuevo.monto, 220000);
    expect(egresoNuevo.estatus, 'registrado');
  });

  test('Cambio simultáneo de monto y origen: BBVA \$1,500 -> Clara \$1,800, sin residual de la captura errónea', () async {
    final bbva = await crearCuenta(nombre: 'BBVA');
    final clara = await crearTarjeta(nombre: 'Clara');
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: bbva.id,
      partidas: partidasDe(150000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(
      compraId: creada.id,
      cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: (await compraRepo.listarPartidas(creada.id)).single.id, nuevoCostoUnitario: 180000)],
      nuevaDeudaId: clara.id,
      motivo: 'Monto y origen mal capturados',
    );

    expect(resultado, isA<CorregirCompraExitosa>());
    final actual = (resultado as CorregirCompraExitosa).compra;
    expect(actual.deudaId, clara.id);
    expect(actual.egresoId, isNull);
    final egresoOriginal = await egresoRepo.obtenerPorId(creada.egresoId!);
    expect(egresoOriginal!.estatus, 'cancelado');
    final claraTras = await deudaRepo.obtenerPorId(clara.id);
    expect(claraTras!.saldoActual, 180000, reason: 'nunca queda un residual de los \$1,500 originales');
  });

  test('Rechazo por crédito insuficiente al mover a otra TDC — nada cambia', () async {
    final origen = await crearTarjeta(nombre: 'Konfío', limiteCredito: 5000000);
    final destino = await crearTarjeta(nombre: 'Clara', limiteCredito: 100000);
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.tarjeta.name,
      deudaId: origen.id,
      partidas: partidasDe(300000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: destino.id, motivo: 'Intento de mover a tarjeta sin cupo');

    expect(resultado, isA<CorregirCompraTarjetaExcedeLimite>());
    final actual = await compraRepo.obtenerPorId(creada.id);
    expect(actual!.deudaId, origen.id, reason: 'nada cambia si la corrección se rechaza');
    final origenTras = await deudaRepo.obtenerPorId(origen.id);
    final destinoTras = await deudaRepo.obtenerPorId(destino.id);
    expect(origenTras!.saldoActual, 300000);
    expect(destinoTras!.saldoActual, 0, reason: 'la tarjeta destino nunca recibe un cargo por un intento rechazado');
  });

  test('Atomicidad real: si el paso final de una transición D falla a mitad de operación, no queda mutación parcial', () async {
    final origen = await crearTarjeta(nombre: 'Konfío');
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.tarjeta.name,
      deudaId: origen.id,
      partidas: partidasDe(180000),
    ) as RegistrarCompraExitosa)
        .compra;

    // Se invoca el repositorio DIRECTAMENTE (sin pasar por el caso de
    // uso, que ya rechazaría un `deudaId` inexistente antes de tocar
    // la BD) con un destino que no existe — el paso "revertir en la
    // vieja" alcanza a ejecutarse antes de que "cargar en la nueva"
    // falle por la FK de `MovimientoDeuda.deudaId`. Ambos pasos viven
    // en la MISMA transacción: la falla debe revertir TODO, incluido
    // el paso que ya había corrido.
    await expectLater(
      () => compraRepo.corregir(compraId: creada.id, nuevaDeudaId: 'deuda-inexistente', motivo: 'Forzar fallo a mitad de operación'),
      throwsA(anything),
    );

    final actual = await compraRepo.obtenerPorId(creada.id);
    expect(actual!.deudaId, origen.id, reason: 'la Compra sigue apuntando a la tarjeta original — el cambio de FK nunca se confirmó');
    final origenTras = await deudaRepo.obtenerPorId(origen.id);
    expect(origenTras!.saldoActual, 180000, reason: 'el paso de reversión en la tarjeta original también se revirtió — cero mutación parcial');
    final movimientos = await (db.select(db.movimientoDeuda)..where((t) => t.compraId.equals(creada.id))).get();
    expect(movimientos, hasLength(1), reason: 'solo el cargo original — ningún ajuste/reversión huérfano quedó persistido');
  });

  test('Motivo obligatorio: una corrección sin motivo se rechaza y no toca nada', () async {
    final cuenta = await crearCuenta();
    final creada = (await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
      partidas: partidasDe(50000),
    ) as RegistrarCompraExitosa)
        .compra;

    final resultado = await corregirCompra.ejecutar(compraId: creada.id, nuevaCuentaFinancieraId: cuenta.id, motivo: '   ');
    expect(resultado, isA<CorregirCompraMotivoRequerido>());
  });
}
