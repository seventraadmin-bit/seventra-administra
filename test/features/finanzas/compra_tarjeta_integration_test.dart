// Etapa 19B — "Compra ↔ Tarjeta de crédito ↔ Deuda". Ejercita la
// cadena REAL de providers (nunca construcción directa de repos/casos
// de uso) para probar, con BD real, la regla financiera crítica del
// pedido: una Compra pagada con tarjeta reconoce el gasto operativo
// UNA sola vez, en el momento de comprar — el pago posterior de la
// tarjeta nunca lo cuenta una segunda vez.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/compras_providers.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/eliminar_cadena_prueba_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'usuario-maestro',
            passwordHash: 'x',
          ),
        );
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
    ]);
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<DeudaData> crearTarjeta({
    required int limite,
    required int saldoInicial,
    String nombre = 'TDC BBVA',
  }) async {
    final resultado = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: nombre,
      tipo: TipoDeuda.tarjetaCredito.name,
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: limite,
      saldoInicial: saldoInicial,
      tarjetaLimiteCredito: limite,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  Future<RegistrarCompraResultado> comprarConTarjeta({
    required String deudaId,
    required int monto,
    String concepto = 'Uniformes',
  }) {
    return container.read(comprasControllerProvider.notifier).registrarCompra(
          fecha: DateTime.now(),
          formaPago: 'tarjeta',
          deudaId: deudaId,
          partidas: [PartidaCompraInput(destino: 'gastoDirecto', concepto: concepto, cantidad: 1, costoUnitario: monto)],
        );
  }

  test('Compra con TDC: saldo/disponible se actualizan y NO se crea Egreso', () async {
    final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 2000000); // límite $50,000, saldo $20,000

    final resultado = await comprarConTarjeta(deudaId: tarjeta.id, monto: 500000); // $5,000
    final compra = (resultado as RegistrarCompraExitosa).compra;

    expect(compra.egresoId, isNull, reason: 'una Compra con tarjeta nunca genera Egreso');
    expect(compra.deudaId, tarjeta.id);

    final deudaTrasCompra = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deudaTrasCompra!.saldoActual, 2500000, reason: r'saldo $20,000 + $5,000 = $25,000');
    final disponible = deudaTrasCompra.tarjetaLimiteCredito! - deudaTrasCompra.saldoActual;
    expect(disponible, 2500000, reason: r'disponible $50,000 - $25,000 = $25,000');

    final egresos = await db.select(db.egreso).get();
    expect(egresos, isEmpty, reason: 'ninguna fila Egreso debe existir todavía');

    final movimientos = await container.read(deudaRepositoryProvider).listarMovimientos(tarjeta.id);
    final cargo = movimientos.singleWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);
    expect(cargo.compraId, compra.id);
    expect(cargo.importe, 500000);
    expect(cargo.saldoAnterior, 2000000);
    expect(cargo.saldoPosterior, 2500000);
    expect(cargo.egresoId, isNull);
  });

  test(
    'Compra con TDC genera gasto operativo UNA sola vez; el pago posterior NO lo duplica '
    '(demostración matemática: Compra + Pago nunca suman el doble)',
    () async {
      // saldoInicial: 1 (nunca 0) — `MovimientoDeuda` exige `importe >
      // 0` incluso en su `altaInicial` (limitación preexistente de la
      // Etapa 19, ajena a esta prueba).
      final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 1);
      final hoy = DateTime.now();
      // `DateTime(año, mes+1, 0)` da medianoche del último día del mes
      // — se necesita 23:59:59.999 explícita para no excluir un pago
      // capturado más tarde ese mismo día (hallazgo real de esta
      // etapa, expuesto por coincidencia de calendario).
      final rangoInicio = DateTime(hoy.year, hoy.month, 1);
      final rangoFin = DateTime(hoy.year, hoy.month + 1, 0, 23, 59, 59, 999);

      final resultado = await comprarConTarjeta(deudaId: tarjeta.id, monto: 500000); // $5,000
      final compra = (resultado as RegistrarCompraExitosa).compra;

      // Tras la Compra: el gasto YA se reconoce en egresosOperativos,
      // aunque no exista ningún Egreso todavía.
      await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
      final resumenTrasCompra = container.read(resumenFinancieroControllerProvider);
      expect(resumenTrasCompra.egresosPeriodo, 0, reason: 'sin Egreso, el total crudo sigue en 0');
      expect(resumenTrasCompra.egresosOperativos, 500000, reason: 'el gasto se reconoce vía el cargo a la tarjeta');
      expect(resumenTrasCompra.cargosTarjetaPeriodo, 500000);

      // Se paga la tarjeta por el mismo monto.
      final pago = await container.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: tarjeta.id,
        fecha: hoy,
        importe: 500000,
        formaPago: 'transferencia',
      );
      expect(pago, isA<RegistrarPagoDeudaExitoso>());

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1), reason: 'el pago SÍ genera exactamente un Egreso — la salida de caja real');
      expect(egresos.single.monto, 500000);

      await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
      final resumenTrasPago = container.read(resumenFinancieroControllerProvider);

      // LA DEMOSTRACIÓN MATEMÁTICA CENTRAL: ni el total crudo ni el
      // operativo llegan jamás a $10,000 — Compra ($5,000) + Pago
      // ($5,000) nunca se cuentan dos veces.
      expect(resumenTrasPago.egresosPeriodo, 500000, reason: 'el total crudo es SOLO el pago (la única fila Egreso real)');
      expect(resumenTrasPago.egresosOperativos, 500000, reason: 'el operativo NO sube por el pago — ya estaba contado desde la Compra');
      expect(resumenTrasPago.egresosDeuda, 500000);
      expect(resumenTrasPago.resultadoOperativo, -500000, reason: 'ingresos 0 - operativo 5,000');

      // Y el clasificador nunca bucket-ea el pago como "manual".
      final clasificado = await container.read(clasificarEgresosPorOrigenUseCaseProvider).ejecutar(
            rangoInicio: rangoInicio,
            rangoFin: rangoFin,
          );
      expect(clasificado.totalManual, 0);
      expect(clasificado.totalDeuda, 500000);
      // La Compra en sí nunca aparece como origen "compra" (no generó Egreso).
      expect(clasificado.detalle.where((d) => d.egreso.concepto.contains(compra.folioCompra)), isEmpty);
    },
  );

  test('Compra que excede el crédito disponible es rechazada sin ninguna mutación', () async {
    final tarjeta = await crearTarjeta(limite: 1000000, saldoInicial: 900000); // disponible $1,000

    final resultado = await comprarConTarjeta(deudaId: tarjeta.id, monto: 200000); // $2,000 > disponible

    expect(resultado, isA<RegistrarCompraTarjetaExcedeLimite>());
    expect((resultado as RegistrarCompraTarjetaExcedeLimite).disponible, 100000);

    final deudaTrasIntento = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deudaTrasIntento!.saldoActual, 900000, reason: 'cero mutación — el saldo no cambia');
    final compras = await db.select(db.compra).get();
    expect(compras, isEmpty, reason: 'cero mutación — ninguna Compra se crea');
    final movimientos = await container.read(deudaRepositoryProvider).listarMovimientos(tarjeta.id);
    expect(movimientos, hasLength(1), reason: 'solo el altaInicial preexistente, ningún cargoCompra');
  });

  test('Compra con una tarjeta sin límite de crédito capturado se rechaza con un mensaje distinto de "excede el límite"', () async {
    final creada = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'TDC sin límite',
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: 0,
    );
    final tarjeta = (creada as RegistrarDeudaExitoso).deuda;
    expect(tarjeta.tarjetaLimiteCredito, isNull);

    final resultado = await comprarConTarjeta(deudaId: tarjeta.id, monto: 100000);

    expect(resultado, isA<RegistrarCompraTarjetaSinLimiteConfigurado>());
    final deudaTrasIntento = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deudaTrasIntento!.saldoActual, 0, reason: 'cero mutación — nunca se confunde "sin límite" con "excede el límite"');
  });

  test('Dos compras consecutivas consumen correctamente el límite', () async {
    final tarjeta = await crearTarjeta(limite: 1000000, saldoInicial: 50000);

    final r1 = await comprarConTarjeta(deudaId: tarjeta.id, monto: 400000);
    expect(r1, isA<RegistrarCompraExitosa>());
    var deuda = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deuda!.saldoActual, 450000);

    final r2 = await comprarConTarjeta(deudaId: tarjeta.id, monto: 500000);
    expect(r2, isA<RegistrarCompraExitosa>());
    deuda = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deuda!.saldoActual, 950000, reason: '50,000 + 400,000 + 500,000 = 950,000');
    expect(deuda.tarjetaLimiteCredito! - deuda.saldoActual, 50000, reason: r'disponible $500');

    final r3 = await comprarConTarjeta(deudaId: tarjeta.id, monto: 200000); // excede el disponible restante
    expect(r3, isA<RegistrarCompraTarjetaExcedeLimite>());
    deuda = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deuda!.saldoActual, 950000, reason: 'la tercera compra rechazada no debe mutar nada');
  });

  test('Pago parcial libera crédito disponible', () async {
    final tarjeta = await crearTarjeta(limite: 1000000, saldoInicial: 800000);
    await container.read(registrarPagoDeudaAutorizadoProvider)(
      deudaId: tarjeta.id,
      fecha: DateTime.now(),
      importe: 300000,
      formaPago: 'transferencia',
    );
    final deuda = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deuda!.saldoActual, 500000);
    expect(deuda.tarjetaLimiteCredito! - deuda.saldoActual, 500000, reason: r'disponible sube de $2,000 a $5,000');
  });

  test('Tarjeta que llega a saldo 0 permanece ACTIVA (revolvente)', () async {
    final tarjeta = await crearTarjeta(limite: 1000000, saldoInicial: 500000);
    await container.read(registrarPagoDeudaAutorizadoProvider)(
      deudaId: tarjeta.id,
      fecha: DateTime.now(),
      importe: 500000,
      formaPago: 'transferencia',
    );
    final deuda = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deuda!.saldoActual, 0);
    expect(deuda.estatus, EstatusDeuda.activa.name, reason: r'una tarjeta en $0 sigue activa y reutilizable');
  });

  test('Préstamo que llega a saldo 0 SÍ queda liquidado (regla sin cambios para no-tarjetas)', () async {
    final prestamo = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'Préstamo refacción',
      tipo: TipoDeuda.prestamo.name,
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      saldoInicial: 500000,
    );
    final deudaPrestamo = (prestamo as RegistrarDeudaExitoso).deuda;

    await container.read(registrarPagoDeudaAutorizadoProvider)(
      deudaId: deudaPrestamo.id,
      fecha: DateTime.now(),
      importe: 500000,
      formaPago: 'transferencia',
    );
    final deuda = await container.read(deudaRepositoryProvider).obtenerPorId(deudaPrestamo.id);
    expect(deuda!.saldoActual, 0);
    expect(deuda.estatus, EstatusDeuda.liquidada.name);
  });

  test('Corrección de Compra ajusta el saldo de la tarjeta de forma auditable (nunca reescribe el cargo original)', () async {
    final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 50000);
    final resultado = await comprarConTarjeta(deudaId: tarjeta.id, monto: 500000);
    final compra = (resultado as RegistrarCompraExitosa).compra;

    final partida = (await container.read(compraRepositoryProvider).listarPartidas(compra.id)).single;
    final corregido = await container.read(comprasControllerProvider.notifier).corregirCompra(
          compraId: compra.id,
          cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partida.id, nuevoCostoUnitario: 450000)],
          motivo: 'Ajuste de prueba',
        );
    expect(corregido, isA<CorregirCompraExitosa>());

    final deudaTrasCorreccion = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
    expect(deudaTrasCorreccion!.saldoActual, 500000, reason: r'saldo 50,000 + $5,000 corregido a $4,500 = 500,000');

    final movimientos = await container.read(deudaRepositoryProvider).listarMovimientos(tarjeta.id);
    final cargoOriginal = movimientos.singleWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);
    expect(cargoOriginal.importe, 500000, reason: 'el cargo original NUNCA se reescribe');
    final ajuste = movimientos.singleWhere((m) => m.tipo == TipoMovimientoDeuda.ajusteNegativo.name);
    expect(ajuste.compraId, compra.id);
    expect(ajuste.importe, 50000);
    expect(ajuste.saldoAnterior, 550000);
    expect(ajuste.saldoPosterior, 500000);
  });

  test(
    'Eliminación física de cadena de prueba: revierte el cargo sin dejar saldo/movimiento huérfano; '
    'bloqueada si la tarjeta ya tiene movimientos posteriores',
    () async {
      final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 20000);
      final resultado = await comprarConTarjeta(deudaId: tarjeta.id, monto: 500000);
      final compra = (resultado as RegistrarCompraExitosa).compra;

      // Caso bloqueado: la tarjeta ya tiene un movimiento posterior (un
      // pago) — no es seguro borrar el cargo de en medio del historial.
      await container.read(registrarPagoDeudaAutorizadoProvider)(
        deudaId: tarjeta.id,
        fecha: DateTime.now(),
        importe: 100000,
        formaPago: 'transferencia',
      );
      final bloqueado = await container.read(eliminarCadenaPruebaCompraAutorizadoProvider)(
        compraId: compra.id,
        motivo: MotivoCadenaPruebaCompra.pruebaFuncional,
      );
      expect(bloqueado, isA<EliminarCadenaPruebaCompraTieneDependencias>());
      final deudaTrasBloqueo = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
      expect(deudaTrasBloqueo!.saldoActual, 420000, reason: 'el intento bloqueado no debe mutar nada');

      // Caso permitido: una Compra cuyo cargo SÍ es el último
      // movimiento de su propia tarjeta.
      final tarjetaLimpia = await crearTarjeta(limite: 5000000, saldoInicial: 10000, nombre: 'TDC de prueba');
      final resultado2 = await comprarConTarjeta(deudaId: tarjetaLimpia.id, monto: 300000);
      final compra2 = (resultado2 as RegistrarCompraExitosa).compra;

      final eliminado = await container.read(eliminarCadenaPruebaCompraAutorizadoProvider)(
        compraId: compra2.id,
        motivo: MotivoCadenaPruebaCompra.pruebaFuncional,
      );
      expect(eliminado, isA<EliminarCadenaPruebaCompraExitoso>());

      final compraTrasEliminar = await container.read(compraRepositoryProvider).obtenerPorId(compra2.id);
      expect(compraTrasEliminar, isNull);
      final movimientosTrasEliminar = await container.read(deudaRepositoryProvider).listarMovimientos(tarjetaLimpia.id);
      expect(movimientosTrasEliminar.where((m) => m.compraId == compra2.id), isEmpty, reason: 'ningún movimiento huérfano');
      final tarjetaLimpiaTrasEliminar = await container.read(deudaRepositoryProvider).obtenerPorId(tarjetaLimpia.id);
      expect(tarjetaLimpiaTrasEliminar!.saldoActual, 10000, reason: 'saldo revertido al valor previo al cargo eliminado');
    },
  );

  group(
    'Etapa "Dashboard: posición financiera" — auditoría banco vs. TDC: '
    'una Compra bancaria reduce la cuenta, una Compra con TDC nunca la toca, '
    'y un pago posterior de TDC desde esa misma cuenta reduce AMBAS sin duplicar el gasto',
    () {
      test('Compra pagada de banco reduce CuentaFinanciera; la misma Compra con TDC nunca la toca', () async {
        final cuenta = await container.read(cuentaFinancieraRepositoryProvider).crear(
              codigo: 'CTA-000001',
              nombre: 'BBVA Principal',
              tipo: TipoCuentaFinanciera.banco.name,
              saldoInicial: 1000000,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            );
        final posicionInicial = await container.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar();
        expect(posicionInicial.saldoDisponible, 1000000);

        final compraBanco = await container.read(comprasControllerProvider.notifier).registrarCompra(
              fecha: DateTime.now(),
              formaPago: FormaPago.transferencia.name,
              cuentaFinancieraId: cuenta.id,
              partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 200000)],
            );
        expect(compraBanco, isA<RegistrarCompraExitosa>());
        final posicionTrasCompraBanco = await container.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar();
        expect(posicionTrasCompraBanco.saldoDisponible, 800000, reason: r'la Compra bancaria SÍ reduce la cuenta — $10,000 - $2,000');

        final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 50000, nombre: 'TDC Konfío');
        final compraTdc = await comprarConTarjeta(deudaId: tarjeta.id, monto: 300000);
        expect(compraTdc, isA<RegistrarCompraExitosa>());
        final posicionTrasCompraTdc = await container.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar();
        expect(posicionTrasCompraTdc.saldoDisponible, 800000,
            reason: 'una Compra pagada con TDC nunca toca ninguna CuentaFinanciera — el saldo de caja no cambia ni un centavo');
      });

      test(
        'Un pago posterior de la TDC desde la cuenta bancaria reduce banco Y saldo de TDC — '
        'sin duplicar el gasto que la Compra original ya reconoció',
        () async {
          final cuenta = await container.read(cuentaFinancieraRepositoryProvider).crear(
                codigo: 'CTA-000001',
                nombre: 'BBVA Principal',
                tipo: TipoCuentaFinanciera.banco.name,
                saldoInicial: 1000000,
                fechaSaldoInicial: DateTime(2026, 1, 1),
              );
          final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 1, nombre: 'TDC Konfío');

          final compra = await comprarConTarjeta(deudaId: tarjeta.id, monto: 500000);
          expect(compra, isA<RegistrarCompraExitosa>());

          await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
          expect(container.read(resumenFinancieroControllerProvider).egresosOperativos, 500000,
              reason: 'la Compra ya reconoció el gasto — antes de cualquier pago de la tarjeta');

          final pago = await container.read(registrarPagoDeudaAutorizadoProvider)(
            deudaId: tarjeta.id,
            fecha: DateTime.now(),
            importe: 500000,
            formaPago: 'transferencia',
            cuentaFinancieraId: cuenta.id,
          );
          expect(pago, isA<RegistrarPagoDeudaExitoso>());

          final posicionTrasPago = await container.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar();
          expect(posicionTrasPago.saldoDisponible, 500000, reason: r'el pago SÍ reduce el banco — $10,000 - $5,000');

          final tarjetaTrasPago = await container.read(deudaRepositoryProvider).obtenerPorId(tarjeta.id);
          expect(tarjetaTrasPago!.saldoActual, 1, reason: 'el saldo de la TDC vuelve al saldo inicial — el pago liquidó el cargo');

          await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
          final resumenTrasPago = container.read(resumenFinancieroControllerProvider);
          expect(resumenTrasPago.egresosOperativos, 500000,
              reason: 'el gasto operativo NO sube por el pago — la liquidación de la TDC es un movimiento de pasivo, no un segundo gasto');
          expect(resumenTrasPago.resultadoOperativo, -500000, reason: r'ingresos 0 - operativo $5,000, nunca -$10,000');
        },
      );
    },
  );
}
