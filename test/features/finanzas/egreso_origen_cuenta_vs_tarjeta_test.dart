// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" —
// pruebas de dominio/repositorio contra BD real (nunca mocks), en el
// orden del pedido de Marlon.
//
// Causa raíz que cubren: un gasto manual y su origen financiero son
// conceptos distintos. Hasta esta etapa "Registrar egreso" solo admitía
// una `CuentaFinanciera`, y `formaPago: 'tarjeta'` era una etiqueta sin
// FK: el caso real (gasolina $1,359.98 pagada con la TDC Konfío) quedó
// como Egreso descontando dinero de Klar, con la deuda de Konfío
// subestimada exactamente en ese monto.

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show TipoMovimientoDeuda;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_flujo_efectivo_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresoRepo;
  late DeudaRepositoryImpl deudaRepo;
  late CuentaFinancieraRepositoryImpl cuentaRepo;
  late RegistrarEgresoUseCase registrarEgreso;
  late CorregirEgresoUseCase corregirEgreso;
  late CancelarEgresoUseCase cancelarEgreso;
  late RegistrarDeudaUseCase registrarDeuda;
  late ObtenerFlujoEfectivoUseCase obtenerFlujo;
  late ClasificarEgresosPorOrigenUseCase clasificarEgresos;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaRepo = CuentaFinancieraRepositoryImpl(db);

    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo);

    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final descuentoRepo = DescuentoProgramadoRepositoryImpl(db, egresoRepo, CodigoSecuenciaService(db));
    final tiempoExtraRepo = TiempoExtraRepositoryImpl(
      db,
      egresoRepo,
      deudaRepo,
      CodigoSecuenciaService(db),
      EmpleadoRepositoryImpl(db, asignacionServicioRepo),
      ServicioRepositoryImpl(db, asignacionServicioRepo),
    );
    final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    final obtenerOrigenAutomatico = ObtenerOrigenAutomaticoEgresoUseCase(
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      deudaRepo,
      descuentoRepo,
      VehiculoMantenimientoRepositoryImpl(db),
      VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db)),
      RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
      LineaTelefonicaRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), LineaTelefonicaEquipoRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), AsignacionRepositoryImpl(db))),
      ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
    );

    corregirEgreso = CorregirEgresoUseCase(egresoRepo, obtenerOrigenAutomatico, deudaRepo);
    cancelarEgreso = CancelarEgresoUseCase(egresoRepo, obtenerOrigenAutomatico);
    obtenerFlujo = ObtenerFlujoEfectivoUseCase(IngresoRepositoryImpl(db), egresoRepo);
    clasificarEgresos = ClasificarEgresosPorOrigenUseCase(
      egresoRepo,
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
      deudaRepo,
      descuentoRepo,
      VehiculoMantenimientoRepositoryImpl(db),
      ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
    );
  });

  tearDown(() => db.close());

  Future<CuentaFinancieraData> crearCuenta(String nombre, String codigo, int saldoInicial) {
    return cuentaRepo.crear(
      codigo: codigo,
      nombre: nombre,
      tipo: 'banco',
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
  }

  Future<DeudaData> crearTarjeta(String nombre, {required int limite, int saldoInicial = 0}) async {
    final resultado = await registrarDeuda.ejecutar(
      nombre: nombre,
      tipo: 'tarjetaCredito',
      saldoInicial: saldoInicial,
      fechaSaldoInicial: saldoInicial > 0 ? DateTime(2026, 1, 1) : null,
      tarjetaLimiteCredito: limite,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  Future<EgresoData> registrarGasto({
    required int monto,
    required OrigenFinancieroGasto? origen,
    String concepto = 'gasolina',
    String formaPago = 'tarjeta',
    DateTime? fecha,
  }) async {
    final resultado = await registrarEgreso.ejecutar(
      monto: monto,
      fecha: fecha ?? DateTime(2026, 3, 5),
      formaPago: formaPago,
      concepto: concepto,
      origen: origen,
    );
    return (resultado as RegistrarEgresoExitoso).egreso;
  }

  int? disponibleDe(DeudaData tarjeta) =>
      creditoDisponibleTarjeta(limiteCredito: tarjeta.tarjetaLimiteCredito, saldoActual: tarjeta.saldoActual);

  group('Punto 1 — un gasto con TDC es gasto operativo sin salida de efectivo', () {
    test('gasolina \$1,359.98 con TDC: carga la tarjeta, NO toca Caja y bancos', () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);

      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      expect(egreso.deudaId, konfio.id, reason: 'FK real hacia la tarjeta, nunca inferida por texto');
      expect(egreso.cuentaFinancieraId, isNull, reason: 'mutuamente excluyente: no salió de ninguna cuenta');

      final tarjeta = await deudaRepo.obtenerPorId(konfio.id);
      expect(tarjeta!.saldoActual, 135998);
      expect(disponibleDe(tarjeta), 4000000 - 135998);

      expect(await cuentaRepo.calcularSaldo(klar.id), 1000000, reason: 'Caja y bancos intacta hasta pagar la tarjeta');

      // El cargo existe, es de tipo cargoCompra (nombre persistido que
      // ya comparten Compra/TiempoExtra) y apunta al Egreso que lo
      // originó — trazabilidad por FK en ambos sentidos.
      final movimientos = await deudaRepo.listarMovimientos(konfio.id);
      final cargo = movimientos.singleWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);
      expect(cargo.importe, 135998);
      expect(cargo.egresoGastoId, egreso.id);
      expect(cargo.compraId, isNull);
      expect(cargo.tiempoExtraId, isNull);
    });

    test('el mismo gasto desde una cuenta SÍ mueve Caja y bancos y no toca ninguna tarjeta', () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);

      await registrarGasto(monto: 135998, origen: OrigenFinancieroCuenta(klar.id), formaPago: 'transferencia');

      expect(await cuentaRepo.calcularSaldo(klar.id), 1000000 - 135998);
      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 0);
    });
  });

  group('Punto 10 — Resultado operativo vs. flujo, sin doble conteo', () {
    test('gasto con TDC: reconocido como gasto del periodo, ausente del flujo de efectivo', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final rangoInicio = DateTime(2026, 3, 1);
      final rangoFin = DateTime(2026, 3, 31);

      await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      // Flujo del periodo: NO hay salida todavía.
      final flujo = await obtenerFlujo.ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);
      expect(flujo.salidas, 0, reason: 'el peso no ha salido de ninguna cuenta');

      // Gasto operativo: se reconoce por la vía del cargo, exactamente
      // igual que una Compra o un Tiempo Extra financiados con TDC.
      final cargos = await deudaRepo.totalCargadoEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
      expect(cargos, 135998);

      // `egresosOperativos = egresosPeriodo - egresosDeuda + cargosTarjeta`
      // reconoce el gasto UNA sola vez: `egresosPeriodo` (totalEgresos)
      // ya lo excluye, así que la fórmula no lo cuenta dos veces.
      final egresosPeriodo = await egresoRepo.totalEgresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
      expect(egresosPeriodo, 0);
      expect(egresosPeriodo + cargos, 135998, reason: 'exactamente una vez, nunca dos veces');
    });

    test('la invariante de ClasificarEgresosPorOrigen sigue cuadrando con totalEgresos', () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final rangoInicio = DateTime(2026, 3, 1);
      final rangoFin = DateTime(2026, 3, 31);

      await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));
      await registrarGasto(monto: 50000, origen: OrigenFinancieroCuenta(klar.id), concepto: 'papelería');

      final resumen = await clasificarEgresos.ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);
      final suma = resumen.totalCompra +
          resumen.totalNomina +
          resumen.totalTiempoExtra +
          resumen.totalDeuda +
          resumen.totalDescuentoProgramado +
          resumen.totalManual;
      expect(suma, await egresoRepo.totalEgresos(rangoInicio: rangoInicio, rangoFin: rangoFin));
      expect(resumen.totalManual, 50000, reason: 'solo el gasto que sí fue salida de efectivo');
    });
  });

  group('Punto 4 — las 6 transiciones de origen', () {
    test('Cuenta → misma Cuenta (solo monto): mueve solo esa cuenta, sin tocar tarjetas', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final egreso = await registrarGasto(monto: 100000, origen: OrigenFinancieroCuenta(bbva.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroCuenta(bbva.id),
        motivo: 'Faltaba un cargo',
      );

      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000 - 150000);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });

    test('Cuenta → otra Cuenta: la primera recupera exactamente, la segunda disminuye exactamente', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 800000);
      final egreso = await registrarGasto(monto: 100000, origen: OrigenFinancieroCuenta(bbva.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        origen: OrigenFinancieroCuenta(klar.id),
        motivo: 'Salió de la otra cuenta',
      );

      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000);
      expect(await cuentaRepo.calcularSaldo(klar.id), 800000 - 100000);
    });

    test('Cuenta → TDC: la cuenta recupera todo, la tarjeta recibe el cargo, el gasto no cambia', () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroCuenta(klar.id));
      expect(await cuentaRepo.calcularSaldo(klar.id), 1000000 - 135998);

      final resultado = await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        origen: OrigenFinancieroTarjeta(konfio.id),
        motivo: 'Realmente se pagó con la TDC Konfío',
      );

      expect(resultado, isA<CorregirEgresoExitoso>());
      final corregido = (resultado as CorregirEgresoExitoso).egreso;
      expect(corregido.id, egreso.id, reason: 'MISMO Egreso: es el documento del gasto, nunca se cancela ni se recrea');
      expect(corregido.folioEgreso, egreso.folioEgreso);
      expect(corregido.estatus, 'registrado', reason: 'nunca queda un Egreso cancelado como residuo');
      expect(corregido.monto, 135998, reason: 'cambiar el origen no cambia cuánto se gastó');

      expect(await cuentaRepo.calcularSaldo(klar.id), 1000000, reason: 'Caja recupera EXACTAMENTE \$1,359.98');
      final tarjeta = await deudaRepo.obtenerPorId(konfio.id);
      expect(tarjeta!.saldoActual, 135998);
      expect(disponibleDe(tarjeta), 4000000 - 135998);
    });

    test('TDC → misma TDC (solo monto): ajuste-delta append-only, nunca reescribe el cargo original', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroTarjeta(konfio.id),
        motivo: 'El ticket real era mayor',
      );

      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 150000);

      final movimientos = await deudaRepo.listarMovimientos(konfio.id);
      final cargoOriginal = movimientos.firstWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);
      expect(cargoOriginal.importe, 135998, reason: 'el cargo original se conserva intacto');
      final ajuste = movimientos.singleWhere((m) => m.tipo == TipoMovimientoDeuda.ajustePositivo.name);
      expect(ajuste.importe, 150000 - 135998);
      expect(ajuste.egresoGastoId, egreso.id);
    });

    test('TDC → otra TDC: la primera devuelve crédito completo, la segunda lo toma completo', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final clara = await crearTarjeta('TDC Clara Empresarial', limite: 3000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroTarjeta(clara.id),
        motivo: 'Fue la Clara, y por otro monto',
      );

      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 0, reason: 'Konfío vuelve exactamente a su saldo previo');
      expect((await deudaRepo.obtenerPorId(clara.id))!.saldoActual, 150000);
      expect(await deudaRepo.netoAportadoPorEgreso(deudaId: konfio.id, egresoId: egreso.id), 0);
    });

    test('TDC → Cuenta: la tarjeta devuelve crédito, la cuenta paga, mismo Egreso', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        origen: OrigenFinancieroCuenta(bbva.id),
        motivo: 'En realidad salió de BBVA',
      );

      final tarjeta = await deudaRepo.obtenerPorId(konfio.id);
      expect(tarjeta!.saldoActual, 0);
      expect(disponibleDe(tarjeta), 4000000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000 - 135998);

      final actualizado = await egresoRepo.obtenerPorId(egreso.id);
      expect(actualizado!.deudaId, isNull);
      expect(actualizado.cuentaFinancieraId, bbva.id);
    });

    test('corregir solo el monto de un gasto con TDC conserva la tarjeta (no la desvincula en silencio)', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await corregirEgreso.ejecutar(egresoId: egreso.id, monto: 150000, motivo: 'Solo el monto');

      final actualizado = await egresoRepo.obtenerPorId(egreso.id);
      expect(actualizado!.deudaId, konfio.id);
      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 150000);
    });
  });

  group('Punto 8 — corrección simultánea de monto y origen', () {
    test('Konfío \$1,359.98 → Clara \$1,500: cada tarjeta exacta, Caja intacta, gasto +\$140.02', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final clara = await crearTarjeta('TDC Clara Empresarial', limite: 3000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroTarjeta(clara.id),
        motivo: 'Tarjeta y monto equivocados',
      );

      expect(disponibleDe((await deudaRepo.obtenerPorId(konfio.id))!), 4000000);
      expect(disponibleDe((await deudaRepo.obtenerPorId(clara.id))!), 3000000 - 150000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000, reason: 'Caja y bancos jamás participó');
      expect((await egresoRepo.obtenerPorId(egreso.id))!.monto, 150000);
    });

    test('Konfío \$1,359.98 → BBVA \$1,500: la tarjeta devuelve todo, BBVA paga \$1,500', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroCuenta(bbva.id),
        motivo: 'Salió de BBVA y por otro monto',
      );

      expect(disponibleDe((await deudaRepo.obtenerPorId(konfio.id))!), 4000000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000 - 150000);
    });
  });

  group('Punto 9 — cancelación revierte el mecanismo que realmente financió', () {
    test('gasto con TDC: la tarjeta recupera crédito, Caja no se mueve', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      final resultado = await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Gasto capturado por error');
      expect(resultado, isA<CancelarEgresoExitoso>());

      final tarjeta = await deudaRepo.obtenerPorId(konfio.id);
      expect(tarjeta!.saldoActual, 0);
      expect(disponibleDe(tarjeta), 4000000);
      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000);
      expect(await deudaRepo.netoAportadoPorEgreso(deudaId: konfio.id, egresoId: egreso.id), 0);

      final cancelado = await egresoRepo.obtenerPorId(egreso.id);
      expect(cancelado!.estatus, 'cancelado');
      expect(cancelado.deudaId, konfio.id, reason: 'el expediente conserva con qué tarjeta se financió');
    });

    test('una segunda cancelación nunca duplica la reversión', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Primera cancelación');
      final segunda = await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Segunda cancelación');

      expect(segunda, isA<CancelarEgresoYaCancelado>());
      final tarjeta = await deudaRepo.obtenerPorId(konfio.id);
      expect(tarjeta!.saldoActual, 0, reason: 'nunca queda en negativo por doble reversión');
      expect(
        (await deudaRepo.listarMovimientos(konfio.id)).where((m) => m.tipo == TipoMovimientoDeuda.ajusteNegativo.name).length,
        1,
      );
    });

    test('gasto desde cuenta: la cuenta recupera el monto, ninguna tarjeta participa', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final egreso = await registrarGasto(monto: 100000, origen: OrigenFinancieroCuenta(bbva.id));

      await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Se canceló');

      expect(await cuentaRepo.calcularSaldo(bbva.id), 1000000);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
    });
  });

  group('Punto 6 — el Egreso nunca queda con dos orígenes ni pierde el gasto', () {
    test('crear con cuenta Y tarjeta a la vez es un error tipado, no un estado inválido persistido', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);

      await expectLater(
        () => egresoRepo.crear(
          folioEgreso: 'EGR-INVALIDO',
          monto: 100000,
          fecha: DateTime(2026, 3, 5),
          cuentaFinancieraId: bbva.id,
          deudaId: konfio.id,
          formaPago: 'tarjeta',
          concepto: 'Imposible',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('un gasto con TDC sigue apareciendo en el listado de Egresos (nunca desaparece del módulo)', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));

      final todos = await egresoRepo.listar(estatus: 'registrado');
      expect(todos, hasLength(1), reason: 'la pantalla de Egresos lo muestra como cualquier otro gasto');

      final soloEfectivo = await egresoRepo.listar(estatus: 'registrado', soloSalidaDeEfectivo: true);
      expect(soloEfectivo, isEmpty, reason: 'pero no cuenta como salida de caja');
    });
  });

  group('Validación de crédito disponible', () {
    test('un gasto que excede el crédito disponible se rechaza con el monto exacto disponible', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 500000, saldoInicial: 400000);

      final resultado = await registrarEgreso.ejecutar(
        monto: 150000,
        fecha: DateTime(2026, 3, 5),
        formaPago: 'tarjeta',
        concepto: 'gasolina',
        origen: OrigenFinancieroTarjeta(konfio.id),
      );

      expect(resultado, isA<RegistrarEgresoTarjetaInvalida>());
      final rechazo = resultado as RegistrarEgresoTarjetaInvalida;
      expect(rechazo.error, ErrorOrigenTarjeta.excedeLimite);
      expect(rechazo.disponible, 100000);
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'nada se persistió');
    });

    test('subir el monto EN LA MISMA tarjeta descuenta lo que el gasto ya ocupaba (nunca lo compara ingenuamente)', () async {
      // Límite 5,000 con 4,000 ya usados por ESTE gasto: subirlo a
      // 4,500 debe permitirse (usa 500 más de los 1,000 libres),
      // aunque 4,500 > 1,000 disponible a secas.
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 500000);
      final egreso = await registrarGasto(monto: 400000, origen: OrigenFinancieroTarjeta(konfio.id));

      final resultado = await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 450000,
        origen: OrigenFinancieroTarjeta(konfio.id),
        motivo: 'El ticket real era mayor',
      );

      expect(resultado, isA<CorregirEgresoExitoso>());
      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 450000);
    });

    test('pero sí se rechaza cuando el monto nuevo realmente no cabe', () async {
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 500000);
      final egreso = await registrarGasto(monto: 400000, origen: OrigenFinancieroTarjeta(konfio.id));

      final resultado = await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 600000,
        origen: OrigenFinancieroTarjeta(konfio.id),
        motivo: 'Monto imposible',
      );

      expect(resultado, isA<CorregirEgresoTarjetaInvalida>());
      expect((resultado as CorregirEgresoTarjetaInvalida).disponible, 500000, reason: 'crédito libre + lo que el gasto ya ocupaba');
      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 400000, reason: 'nada cambió');
    });
  });

  group('Punto 14 — caso integral contra BD real', () {
    test('BBVA/Klar/Konfío/Clara recorren alta → 2 correcciones → cancelación con cifras exactas', () async {
      final bbva = await crearCuenta('BBVA Empresarial', 'CTA-0003', 1000000);
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 800000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 500000);
      final clara = await crearTarjeta('TDC Clara Empresarial', limite: 700000);

      Future<void> verificar({
        required int esperadoBbva,
        required int esperadoKlar,
        required int esperadoKonfio,
        required int esperadoClara,
        required String etapa,
      }) async {
        final saldos = await cuentaRepo.calcularSaldos([bbva.id, klar.id]);
        expect(saldos[bbva.id], esperadoBbva, reason: '$etapa — BBVA');
        expect(saldos[klar.id], esperadoKlar, reason: '$etapa — Klar');
        expect(disponibleDe((await deudaRepo.obtenerPorId(konfio.id))!), esperadoKonfio, reason: '$etapa — Konfío disponible');
        expect(disponibleDe((await deudaRepo.obtenerPorId(clara.id))!), esperadoClara, reason: '$etapa — Clara disponible');
        expect(saldos[bbva.id]! + saldos[klar.id]!, esperadoBbva + esperadoKlar, reason: '$etapa — Caja y bancos');
      }

      // Registrar: Gasolina $1,359.98 → Konfío.
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroTarjeta(konfio.id));
      await verificar(
        esperadoBbva: 1000000,
        esperadoKlar: 800000,
        esperadoKonfio: 500000 - 135998,
        esperadoClara: 700000,
        etapa: 'tras registrar con Konfío',
      );

      // Corregir: Konfío $1,359.98 → Clara $1,500.
      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroTarjeta(clara.id),
        motivo: 'Fue la Clara y por otro monto',
      );
      await verificar(
        esperadoBbva: 1000000,
        esperadoKlar: 800000,
        esperadoKonfio: 500000,
        esperadoClara: 700000 - 150000,
        etapa: 'tras mover a Clara',
      );

      // Corregir: Clara $1,500 → BBVA $1,500.
      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        origen: OrigenFinancieroCuenta(bbva.id),
        motivo: 'En realidad salió de BBVA',
      );
      await verificar(
        esperadoBbva: 1000000 - 150000,
        esperadoKlar: 800000,
        esperadoKonfio: 500000,
        esperadoClara: 700000,
        etapa: 'tras mover a BBVA',
      );

      // Cancelar: todo vuelve exactamente al inicio.
      await cancelarEgreso.ejecutar(egresoId: egreso.id, motivo: 'Gasto cancelado');
      await verificar(
        esperadoBbva: 1000000,
        esperadoKlar: 800000,
        esperadoKonfio: 500000,
        esperadoClara: 700000,
        etapa: 'tras cancelar',
      );

      // Efecto operativo neto del gasto cancelado = 0. Se mide sin
      // acotar el rango a propósito: la reversión de un cargo se
      // reconoce con la fecha en que ocurre (`DateTime.now()`, mismo
      // criterio que Compra/TiempoExtra), así que acotar a marzo
      // mediría el cargo sin su reversión — que es contabilidad
      // correcta por periodo, no un residuo. Lo que debe dar cero es el
      // efecto acumulado.
      final egresosTotales = await egresoRepo.totalEgresos();
      final cargosNetos = await deudaRepo.totalCargadoEnRango();
      expect(egresosTotales, 0, reason: 'el Egreso cancelado no cuenta como salida de efectivo');
      expect(cargosNetos, 0, reason: 'cargo y reversión se netean: cero gasto operativo vivo');
    });
  });

  group('Punto 12 — auditoría de la corrección', () {
    test('el evento corregido registra actor, motivo y el antes/después de monto, cuenta y tarjeta', () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final actorId = await db.into(db.usuario).insertReturning(
            UsuarioCompanion.insert(
              nombre: 'Auditor de prueba',
              nombreUsuario: 'auditor',
              passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            ),
          );

      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroCuenta(klar.id));
      await corregirEgreso.ejecutar(
        egresoId: egreso.id,
        monto: 150000,
        origen: OrigenFinancieroTarjeta(konfio.id),
        motivo: 'Realmente se pagó con la TDC Konfío',
        actorUsuarioId: actorId.id,
      );

      final eventos = await egresoRepo.listarEventos(egreso.id);
      final corregido = eventos.lastWhere((e) => e.tipoEvento == 'corregido');
      expect(corregido.observacion, 'Realmente se pagó con la TDC Konfío');
      expect(corregido.actorUsuarioId, actorId.id);
      expect(corregido.estadoAnterior, contains('"monto":135998'));
      expect(corregido.estadoNuevo, contains('"monto":150000'));
      expect(corregido.estadoAnterior, contains('"cuentaFinancieraId":"${klar.id}"'));
      expect(corregido.estadoNuevo, contains('"deudaId":"${konfio.id}"'));

      // El ledger de la tarjeta también guarda al actor real.
      final cargo = (await deudaRepo.listarMovimientos(konfio.id))
          .singleWhere((m) => m.tipo == TipoMovimientoDeuda.cargoCompra.name);
      expect(cargo.actorUsuarioId, actorId.id);
    });
  });

  group('Atomicidad', () {
    test('un fallo real a mitad de la corrección deja Egreso, cuenta y tarjeta exactamente como estaban', () async {
      final klar = await crearCuenta('Klar Empresarial', 'CTA-0002', 1000000);
      final konfio = await crearTarjeta('TDC Konfío Empresarial', limite: 4000000);
      final egreso = await registrarGasto(monto: 135998, origen: OrigenFinancieroCuenta(klar.id));

      final saldoCuentaAntes = await cuentaRepo.calcularSaldo(klar.id);
      final movimientosAntes = (await deudaRepo.listarMovimientos(konfio.id)).length;
      final eventosAntes = (await egresoRepo.listarEventos(egreso.id)).length;

      // Falla DENTRO de la misma transacción, después de que la
      // corrección ya escribió Egreso + MovimientoDeuda.
      await expectLater(
        () => db.transaction(() async {
          await corregirEgreso.ejecutar(
            egresoId: egreso.id,
            monto: 150000,
            origen: OrigenFinancieroTarjeta(konfio.id),
            motivo: 'Corrección que se va a revertir',
          );
          throw StateError('Fallo real provocado a mitad de la transacción');
        }),
        throwsA(isA<StateError>()),
      );

      final despues = await egresoRepo.obtenerPorId(egreso.id);
      expect(despues!.monto, 135998, reason: 'rollback completo del monto');
      expect(despues.cuentaFinancieraId, klar.id, reason: 'rollback completo del origen');
      expect(despues.deudaId, isNull);
      expect(await cuentaRepo.calcularSaldo(klar.id), saldoCuentaAntes);
      expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 0);
      expect((await deudaRepo.listarMovimientos(konfio.id)).length, movimientosAntes);
      expect((await egresoRepo.listarEventos(egreso.id)).length, eventosAntes);
    });
  });
}
