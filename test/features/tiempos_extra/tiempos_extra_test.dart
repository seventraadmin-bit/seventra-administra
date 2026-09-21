// Tiempos Extra (cobertura operativa por ausencia, pedido explícito de
// Marlon): registrar cobre interno/externo, validación de cobertura
// (exactamente uno de los dos), múltiples costos adicionales sumados
// en un solo Egreso, cancelación cancela también el Egreso vinculado,
// filtro por rango de fecha.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_credito_disponible_tarjetas_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_state.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/cancelar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/tiempo_extra_validator.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';

void main() {
  late AppDatabase db;
  late TiempoExtraRepositoryImpl tiempoExtraRepo;
  late RegistrarTiempoExtraUseCase registrar;
  late CancelarTiempoExtraUseCase cancelar;
  late DeudaRepositoryImpl deudaRepo;
  late EgresoRepositoryImpl egresoRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late RegistrarDeudaUseCase registrarDeuda;
  late ObtenerPosicionDeCajaUseCase obtenerPosicionCaja;
  late ObtenerCreditoDisponibleTarjetasUseCase obtenerCreditoDisponible;
  late ObtenerResumenTiemposExtraUseCase obtenerResumenTiemposExtra;
  late String servicioId;
  late String empleadoAusenteId;
  late String empleadoCubreId;
  late String turnoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    egresoRepo = EgresoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);

    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(codigoSecuencia));
    obtenerPosicionCaja = ObtenerPosicionDeCajaUseCase(cuentaFinancieraRepo);
    obtenerCreditoDisponible = ObtenerCreditoDisponibleTarjetasUseCase(deudaRepo);
    tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    registrar = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
    cancelar = CancelarTiempoExtraUseCase(tiempoExtraRepo);
    obtenerResumenTiemposExtra = ObtenerResumenTiemposExtraUseCase(tiempoExtraRepo, servicioRepo);

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final servicioCreado = await CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(codigoSecuencia), ServicioValidator(clienteRepo, catalogoRepo))
        .ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    Future<String> crearEmpleado(int numero, String nombre) async {
      final n = numero.toString().padLeft(2, '0');
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: numero,
              nombres: nombre,
              apellidoPaterno: 'Apellido$n',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX$n',
              rfc: 'PEXJ900101$n',
              nss: '100000000$n',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      return empleado.id;
    }

    empleadoAusenteId = await crearEmpleado(1, 'Monica');
    empleadoCubreId = await crearEmpleado(2, 'Juan');
    turnoId = SeedIds.modalidadTurno24x24;
  });

  tearDown(() => db.close());

  test('registrar con cobertura interna crea el Egreso con el monto correcto y el servicioId del Servicio cubierto', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 50000,
      formaPago: 'efectivo',
    );

    expect(resultado, isA<RegistrarTiempoExtraExitoso>());
    final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
    expect(tiempoExtra.egresoId, isNotNull);

    final egreso = await (db.select(db.egreso)..where((t) => t.id.equals(tiempoExtra.egresoId!))).getSingle();
    expect(egreso.monto, 50000);
    expect(egreso.servicioId, servicioId);
    expect(egreso.estatus, 'registrado');
  });

  test('registrar con cobertura externa usa el nombre externo como beneficiario del Egreso', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.problemasMedicos.name,
      nombreExternoCubre: 'Pedro Externo',
      turnoId: turnoId,
      montoTiempoExtra: 30000,
      formaPago: 'transferencia',
    );

    expect(resultado, isA<RegistrarTiempoExtraExitoso>());
    final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
    final egreso = await (db.select(db.egreso)..where((t) => t.id.equals(tiempoExtra.egresoId!))).getSingle();
    expect(egreso.beneficiario, 'Pedro Externo');
  });

  test('rechaza registrar sin indicar quién cubre (ni Empleado ni externo)', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaJustificada.name,
      turnoId: turnoId,
      montoTiempoExtra: 30000,
      formaPago: 'efectivo',
    );

    expect(resultado, isA<RegistrarTiempoExtraCoberturaInvalida>());
    expect((resultado as RegistrarTiempoExtraCoberturaInvalida).validacion, TiempoExtraCoberturaValidacion.faltaCobertura);
  });

  test('rechaza registrar con Empleado y externo a la vez (cobertura ambigua)', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.permisoOtorgado.name,
      empleadoCubreId: empleadoCubreId,
      nombreExternoCubre: 'Pedro Externo',
      turnoId: turnoId,
      montoTiempoExtra: 30000,
      formaPago: 'efectivo',
    );

    expect(resultado, isA<RegistrarTiempoExtraCoberturaInvalida>());
    expect((resultado as RegistrarTiempoExtraCoberturaInvalida).validacion, TiempoExtraCoberturaValidacion.coberturaAmbigua);
  });

  test(
    'múltiples costos adicionales tienen su PROPIO origen financiero independiente — cada uno genera '
    'su propio Egreso, nunca combinado con el pago base ni entre sí (Etapa "origen financiero unificado")',
    () async {
      final resultado = await registrar.ejecutar(
        fecha: DateTime(2026, 9, 3),
        servicioId: servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubreId: empleadoCubreId,
        turnoId: turnoId,
        montoTiempoExtra: 50000,
        formaPago: 'efectivo',
        costosAdicionales: const [
          CostoAdicionalInput(concepto: 'Traslado', monto: 10000, formaPago: 'efectivo'),
          CostoAdicionalInput(concepto: 'Recarga telefónica', monto: 5000, formaPago: 'efectivo'),
        ],
      );

      expect(resultado, isA<RegistrarTiempoExtraExitoso>());
      final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;

      final egresoPagoBase = await (db.select(db.egreso)..where((t) => t.id.equals(tiempoExtra.egresoId!))).getSingle();
      expect(egresoPagoBase.monto, 50000, reason: 'el pago base nunca se combina con los costos adicionales');

      final costos = await tiempoExtraRepo.listarCostosAdicionales(tiempoExtra.id);
      expect(costos, hasLength(2));
      expect(costos.map((c) => c.concepto), containsAll(['Traslado', 'Recarga telefónica']));

      final traslado = costos.singleWhere((c) => c.concepto == 'Traslado');
      final recarga = costos.singleWhere((c) => c.concepto == 'Recarga telefónica');
      expect(traslado.egresoId, isNotNull);
      expect(recarga.egresoId, isNotNull);
      expect(traslado.egresoId, isNot(equals(recarga.egresoId)), reason: 'cada costo genera su PROPIO Egreso, nunca compartido');
      expect(traslado.egresoId, isNot(equals(tiempoExtra.egresoId)), reason: 'nunca combinado con el Egreso del pago base');

      final egresoTraslado = await (db.select(db.egreso)..where((t) => t.id.equals(traslado.egresoId!))).getSingle();
      expect(egresoTraslado.monto, 10000);
      final egresoRecarga = await (db.select(db.egreso)..where((t) => t.id.equals(recarga.egresoId!))).getSingle();
      expect(egresoRecarga.monto, 5000);

      final totalEgresos = await db.select(db.egreso).get();
      expect(
        totalEgresos.fold<int>(0, (s, e) => s + e.monto),
        65000,
        reason: '50000 + 10000 + 5000 — la suma total nunca cambia, solo la cantidad de movimientos que la representan',
      );
    },
  );

  test('cancelar cancela también el Egreso vinculado', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 50000,
      formaPago: 'efectivo',
    );
    final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;

    final cancelado = await cancelar.ejecutar(tiempoExtraId: tiempoExtra.id, motivo: 'Registro de prueba');
    expect(cancelado, isA<CancelarTiempoExtraExitoso>());

    final egreso = await (db.select(db.egreso)..where((t) => t.id.equals(tiempoExtra.egresoId!))).getSingle();
    expect(egreso.estatus, 'cancelado');

    final segundaCancelacion = await cancelar.ejecutar(tiempoExtraId: tiempoExtra.id, motivo: 'De nuevo');
    expect(segundaCancelacion, isA<CancelarTiempoExtraYaCancelado>());
  });

  test('listar filtra por rango de fecha', () async {
    await registrar.ejecutar(
      fecha: DateTime(2026, 8, 1),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 10000,
      formaPago: 'efectivo',
    );
    await registrar.ejecutar(
      fecha: DateTime(2026, 9, 15),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 20000,
      formaPago: 'efectivo',
    );

    final soloSeptiembre = await tiempoExtraRepo.listar(rangoInicio: DateTime(2026, 9, 1), rangoFin: DateTime(2026, 9, 30));
    expect(soloSeptiembre, hasLength(1));
    expect(soloSeptiembre.single.montoTiempoExtra, 20000);
  });

  group('Etapa "origen financiero unificado" — caso real (pago BBVA + Uber Konfío + comida Clara)', () {
    Future<CuentaFinancieraData> crearCuenta({required int saldoInicial, String nombre = 'BBVA Empresarial', String codigo = 'CTA-000001'}) {
      return cuentaFinancieraRepo.crear(
        codigo: codigo,
        nombre: nombre,
        tipo: TipoCuentaFinanciera.banco.name,
        saldoInicial: saldoInicial,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
    }

    Future<DeudaData> crearTarjeta({required int limite, required int saldoInicial, required String nombre}) async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: nombre,
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: saldoInicial,
        fechaSaldoInicial: saldoInicial > 0 ? DateTime(2026, 1, 1) : null,
        tarjetaLimiteCredito: limite,
      );
      return (resultado as RegistrarDeudaExitoso).deuda;
    }

    test('1. Tiempo extra \$1,620 pagado desde BBVA: gasto +1,620, BBVA -1,620, Caja y bancos -1,620', () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000); // $10,000
      final posicionInicial = await obtenerPosicionCaja.ejecutar();
      expect(posicionInicial.saldoDisponible, 1000000);

      final resultado = await registrar.ejecutar(
        fecha: DateTime(2026, 9, 3),
        servicioId: servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubreId: empleadoCubreId,
        turnoId: turnoId,
        montoTiempoExtra: 162000, // $1,620
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta.id,
      );
      expect(resultado, isA<RegistrarTiempoExtraExitoso>());
      final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
      expect(tiempoExtra.egresoId, isNotNull);
      expect(tiempoExtra.deudaId, isNull);

      final egreso = await (db.select(db.egreso)..where((t) => t.id.equals(tiempoExtra.egresoId!))).getSingle();
      expect(egreso.monto, 162000);
      expect(egreso.cuentaFinancieraId, cuenta.id);

      final posicionDespues = await obtenerPosicionCaja.ejecutar();
      expect(posicionDespues.saldoDisponible, 1000000 - 162000);
    });

    test('2. Uber \$350 con TDC Konfío: saldo Konfío +350, disponible -350, Caja y bancos SIN CAMBIO', () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000);
      final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 3326608, nombre: 'Konfío');
      final posicionInicial = await obtenerPosicionCaja.ejecutar();
      final creditoInicial = await obtenerCreditoDisponible.ejecutar();

      final resultado = await registrar.ejecutar(
        fecha: DateTime(2026, 9, 3),
        servicioId: servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubreId: empleadoCubreId,
        turnoId: turnoId,
        montoTiempoExtra: 162000,
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta.id,
        costosAdicionales: [
          CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
        ],
      );
      expect(resultado, isA<RegistrarTiempoExtraExitoso>());
      final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;

      final costos = await tiempoExtraRepo.listarCostosAdicionales(tiempoExtra.id);
      final uber = costos.single;
      expect(uber.deudaId, konfio.id);
      expect(uber.egresoId, isNull, reason: 'un costo pagado con TDC nunca genera Egreso');

      final konfioTrasCargo = await deudaRepo.obtenerPorId(konfio.id);
      expect(konfioTrasCargo!.saldoActual, 3326608 + 35000);

      final creditoDespues = await obtenerCreditoDisponible.ejecutar();
      expect(creditoDespues.totalDisponible, creditoInicial.totalDisponible - 35000);

      final posicionDespues = await obtenerPosicionCaja.ejecutar();
      expect(
        posicionDespues.saldoDisponible,
        posicionInicial.saldoDisponible - 162000,
        reason: 'Caja y bancos solo cambia por el pago base — el Uber con TDC nunca la toca',
      );
    });

    test(
      '3. Pago posterior de \$350 de Konfío desde BBVA: BBVA -350, saldo Konfío -350, disponible +350, '
      'egresosOperativos NO vuelve a sumar el gasto',
      () async {
        final cuenta = await crearCuenta(saldoInicial: 1000000);
        final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 0, nombre: 'Konfío');

        await registrar.ejecutar(
          fecha: DateTime(2026, 9, 3),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          empleadoCubreId: empleadoCubreId,
          turnoId: turnoId,
          montoTiempoExtra: 1,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuenta.id,
          costosAdicionales: [
            CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
          ],
        );

        final registrarPagoDeuda = RegistrarPagoDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
        final pago = await registrarPagoDeuda.ejecutar(
          deudaId: konfio.id,
          fecha: DateTime(2026, 9, 10),
          importe: 35000,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuenta.id,
        );
        expect(pago, isA<RegistrarPagoDeudaExitoso>());

        final konfioTrasPago = await deudaRepo.obtenerPorId(konfio.id);
        expect(konfioTrasPago!.saldoActual, 0);

        final posicion = await obtenerPosicionCaja.ejecutar();
        expect(posicion.saldoDisponible, 1000000 - 1 - 35000);

        // egresosOperativos = egresosPeriodo − egresosDeuda + cargosTarjetaPeriodo
        // — misma fórmula exacta de `ResumenFinancieroState`, ya
        // probada con Compras; aquí se demuestra con datos reales
        // producidos por Tiempos Extra.
        final egresos = await db.select(db.egreso).get();
        final egresosPeriodo = egresos.fold<int>(0, (s, e) => s + e.monto);
        final egresoIdsDeuda = (await deudaRepo.listarEgresoIdsDePagosEnRango()).toSet();
        final egresosDeuda = egresos.where((e) => egresoIdsDeuda.contains(e.id)).fold<int>(0, (s, e) => s + e.monto);
        final cargosTarjetaPeriodo = await deudaRepo.totalCargadoEnRango();

        final resumen = ResumenFinancieroState(
          egresosPeriodo: egresosPeriodo,
          egresosDeuda: egresosDeuda,
          cargosTarjetaPeriodo: cargosTarjetaPeriodo,
        );
        expect(
          resumen.egresosOperativos,
          1 + 35000,
          reason: r'el gasto real sigue siendo pago base ($0.01) + Uber ($350) — el pago de la tarjeta NUNCA se cuenta una segunda vez',
        );
      },
    );

    test(
      '4. Cobertura completa: pago BBVA + Uber Konfío + comida Clara — 3 orígenes independientes, cada uno trazable por FK',
      () async {
        final cuenta = await crearCuenta(saldoInicial: 5000000);
        final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 3326608, nombre: 'Konfío');
        final clara = await crearTarjeta(limite: 2000000, saldoInicial: 500000, nombre: 'Clara');

        final resultado = await registrar.ejecutar(
          fecha: DateTime(2026, 9, 3),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          empleadoCubreId: empleadoCubreId,
          turnoId: turnoId,
          montoTiempoExtra: 162000,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuenta.id,
          costosAdicionales: [
            CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
            CostoAdicionalInput(concepto: 'Comida', monto: 20000, formaPago: 'tarjeta', deudaIdTarjeta: clara.id),
          ],
        );
        expect(resultado, isA<RegistrarTiempoExtraExitoso>());
        final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;

        final costos = await tiempoExtraRepo.listarCostosAdicionales(tiempoExtra.id);
        final uber = costos.singleWhere((c) => c.concepto == 'Uber');
        final comida = costos.singleWhere((c) => c.concepto == 'Comida');
        expect(uber.deudaId, konfio.id);
        expect(comida.deudaId, clara.id);

        final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
        final claraTras = await deudaRepo.obtenerPorId(clara.id);
        expect(konfioTras!.saldoActual, 3326608 + 35000);
        expect(claraTras!.saldoActual, 500000 + 20000);

        final movimientosKonfio = await deudaRepo.listarMovimientos(konfio.id);
        expect(movimientosKonfio.where((m) => m.costoAdicionalId == uber.id), hasLength(1));
        final movimientosClara = await deudaRepo.listarMovimientos(clara.id);
        expect(movimientosClara.where((m) => m.costoAdicionalId == comida.id), hasLength(1));

        final posicion = await obtenerPosicionCaja.ejecutar();
        expect(
          posicion.saldoDisponible,
          5000000 - 162000,
          reason: 'solo el pago base salió de BBVA — Uber/Comida nunca tocaron ninguna CuentaFinanciera',
        );
      },
    );

    test(
      '5. Error intermedio (un costo apunta a una tarjeta inexistente) revierte TODA la transacción — '
      'cero TiempoExtra/Egreso parcial, ni siquiera el pago base que ya se había procesado',
      () async {
        await expectLater(
          tiempoExtraRepo.crear(
            fecha: DateTime(2026, 9, 3),
            servicioId: servicioId,
            origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
            empleadoAusenteId: empleadoAusenteId,
            empleadoCubreId: empleadoCubreId,
            motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
            turnoId: turnoId,
            montoTiempoExtra: 1,
            formaPago: 'efectivo',
            costosAdicionales: const [
              CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: 'no-existe'),
            ],
            beneficiarioEgreso: 'Juan',
          ),
          throwsA(isA<StateError>()),
        );

        final tiemposExtra = await db.select(db.tiempoExtra).get();
        expect(tiemposExtra, isEmpty, reason: 'rollback total — nunca queda un TiempoExtra registrado parcialmente');
        final egresos = await db.select(db.egreso).get();
        expect(egresos, isEmpty, reason: 'ni siquiera el Egreso del pago base (procesado primero) sobrevive el rollback');
      },
    );

    test('6. Cancelar y volver a registrar con un origen distinto no duplica movimientos ni deja residuos', () async {
      final cuenta = await crearCuenta(saldoInicial: 1000000);
      final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 0, nombre: 'Konfío');

      final primero = await registrar.ejecutar(
        fecha: DateTime(2026, 9, 3),
        servicioId: servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubreId: empleadoCubreId,
        turnoId: turnoId,
        montoTiempoExtra: 50000,
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta.id,
      );
      final tiempoExtra1 = (primero as RegistrarTiempoExtraExitoso).tiempoExtra;

      final cancelado = await cancelar.ejecutar(tiempoExtraId: tiempoExtra1.id, motivo: 'Origen equivocado');
      expect(cancelado, isA<CancelarTiempoExtraExitoso>());
      final posicionTrasCancelar = await obtenerPosicionCaja.ejecutar();
      expect(posicionTrasCancelar.saldoDisponible, 1000000, reason: 'cancelar revierte el Egreso — la cuenta vuelve a su saldo original');

      final segundo = await registrar.ejecutar(
        fecha: DateTime(2026, 9, 3),
        servicioId: servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubreId: empleadoCubreId,
        turnoId: turnoId,
        montoTiempoExtra: 50000,
        formaPago: 'tarjeta',
        deudaIdTarjeta: konfio.id,
      );
      final tiempoExtra2 = (segundo as RegistrarTiempoExtraExitoso).tiempoExtra;
      expect(tiempoExtra2.deudaId, konfio.id);

      final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
      expect(konfioTras!.saldoActual, 50000, reason: 'nunca se duplica — el segundo registro es el único cargo real a Konfío');

      final posicionFinal = await obtenerPosicionCaja.ejecutar();
      expect(posicionFinal.saldoDisponible, 1000000, reason: 'BBVA nunca se tocó en el segundo registro (fue pagado con TDC)');
    });

    test(
      '7. "Gasto total" (ObtenerResumenTiemposExtraUseCase) suma pago base + TODOS los costos adicionales '
      'sin importar su origen — \$1,620 BBVA + Uber \$350 Konfío + comida \$200 Clara = \$2,170 (mismo valor que consume Dashboard '
      'y Personal > Tiempos Extra, misma clase de resultado)',
      () async {
        final cuenta = await crearCuenta(saldoInicial: 5000000);
        final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 0, nombre: 'Konfío');
        final clara = await crearTarjeta(limite: 2000000, saldoInicial: 0, nombre: 'Clara');

        final resultado = await registrar.ejecutar(
          fecha: DateTime(2026, 9, 3),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          empleadoCubreId: empleadoCubreId,
          turnoId: turnoId,
          montoTiempoExtra: 162000, // $1,620
          formaPago: 'transferencia',
          cuentaFinancieraId: cuenta.id,
          costosAdicionales: [
            CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id), // $350
            CostoAdicionalInput(concepto: 'Comida', monto: 20000, formaPago: 'tarjeta', deudaIdTarjeta: clara.id), // $200
          ],
        );
        expect(resultado, isA<RegistrarTiempoExtraExitoso>());

        final resumen = await obtenerResumenTiemposExtra.ejecutar();
        expect(
          resumen.gastoTotal,
          217000, // $2,170.00
          reason: 'gastoTotal = montoTiempoExtra + Σcostos, independiente de que cada ítem tenga su propio egresoId o deudaId',
        );
        expect(resumen.totalRegistros, 1);
      },
    );

    test(
      '8. Cancelación completa de una cobertura mixta (\$1,620 BBVA + Uber \$350 Konfío + comida \$200 Clara): '
      'revierte los 3 orígenes exactamente, y una segunda cancelación no duplica ni deshace nada adicional',
      () async {
        final cuenta = await crearCuenta(saldoInicial: 5000000);
        final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 3326608, nombre: 'Konfío');
        final clara = await crearTarjeta(limite: 2000000, saldoInicial: 500000, nombre: 'Clara');

        final posicionPrevia = await obtenerPosicionCaja.ejecutar();
        final creditoPrevio = await obtenerCreditoDisponible.ejecutar();
        final resumenPrevio = await obtenerResumenTiemposExtra.ejecutar();

        final resultado = await registrar.ejecutar(
          fecha: DateTime(2026, 9, 3),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          empleadoCubreId: empleadoCubreId,
          turnoId: turnoId,
          montoTiempoExtra: 162000,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuenta.id,
          costosAdicionales: [
            CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
            CostoAdicionalInput(concepto: 'Comida', monto: 20000, formaPago: 'tarjeta', deudaIdTarjeta: clara.id),
          ],
        );
        final tiempoExtra = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;

        // --- Estado tras registrar: los 3 orígenes deben moverse exactamente lo esperado.
        expect((await obtenerPosicionCaja.ejecutar()).saldoDisponible, posicionPrevia.saldoDisponible - 162000, reason: 'Cuenta financiera -1,620');
        final konfioTrasRegistro = await deudaRepo.obtenerPorId(konfio.id);
        expect(konfioTrasRegistro!.saldoActual, 3326608 + 35000, reason: 'Konfío saldo +350');
        final claraTrasRegistro = await deudaRepo.obtenerPorId(clara.id);
        expect(claraTrasRegistro!.saldoActual, 500000 + 20000, reason: 'Clara saldo +200');
        expect(
          (await obtenerCreditoDisponible.ejecutar()).totalDisponible,
          creditoPrevio.totalDisponible - 35000 - 20000,
          reason: 'crédito disponible combinado -550 (Konfío -350, Clara -200)',
        );
        expect(
          (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal,
          resumenPrevio.gastoTotal + 217000,
          reason: 'gasto operativo total +2,170',
        );

        // --- Cancelar: los 3 orígenes deben volver EXACTAMENTE al valor previo.
        final movimientosAntesDeCancelar = await db.select(db.movimientoDeuda).get();
        final cancelado = await cancelar.ejecutar(tiempoExtraId: tiempoExtra.id, motivo: 'Cancelación de auditoría');
        expect(cancelado, isA<CancelarTiempoExtraExitoso>());

        expect((await obtenerPosicionCaja.ejecutar()).saldoDisponible, posicionPrevia.saldoDisponible, reason: 'Cuenta financiera recupera exactamente su saldo previo');
        final konfioTrasCancelar = await deudaRepo.obtenerPorId(konfio.id);
        expect(konfioTrasCancelar!.saldoActual, 3326608, reason: 'Konfío vuelve exactamente a su saldo previo');
        final claraTrasCancelar = await deudaRepo.obtenerPorId(clara.id);
        expect(claraTrasCancelar!.saldoActual, 500000, reason: 'Clara vuelve exactamente a su saldo previo');
        expect((await obtenerCreditoDisponible.ejecutar()).totalDisponible, creditoPrevio.totalDisponible, reason: 'crédito disponible combinado recupera su valor previo');
        expect((await obtenerResumenTiemposExtra.ejecutar()).gastoTotal, resumenPrevio.gastoTotal, reason: 'gasto operativo total recupera su valor previo (el TEX cancelado ya no cuenta)');

        final movimientosTrasCancelar = await db.select(db.movimientoDeuda).get();
        expect(
          movimientosTrasCancelar.length,
          movimientosAntesDeCancelar.length + 2,
          reason: 'exactamente 1 ajuste de reversión por cada cargo con TDC (Konfío, Clara) — nunca más',
        );

        // --- Segunda cancelación: cero efectos adicionales (idempotencia).
        final segundaCancelacion = await cancelar.ejecutar(tiempoExtraId: tiempoExtra.id, motivo: 'De nuevo');
        expect(segundaCancelacion, isA<CancelarTiempoExtraYaCancelado>());

        expect((await obtenerPosicionCaja.ejecutar()).saldoDisponible, posicionPrevia.saldoDisponible);
        expect((await deudaRepo.obtenerPorId(konfio.id))!.saldoActual, 3326608);
        expect((await deudaRepo.obtenerPorId(clara.id))!.saldoActual, 500000);
        expect((await obtenerResumenTiemposExtra.ejecutar()).gastoTotal, resumenPrevio.gastoTotal);
        final movimientosTrasSegundaCancelacion = await db.select(db.movimientoDeuda).get();
        expect(
          movimientosTrasSegundaCancelacion.length,
          movimientosTrasCancelar.length,
          reason: 'una segunda cancelación/reversión no puede duplicar efectos — cero movimientos nuevos',
        );
      },
    );

    test('9. Crédito disponible y Caja y bancos son conceptos independientes — nunca se mezclan, ni con una TDC muy grande', () async {
      await crearCuenta(saldoInicial: 500000);
      await crearTarjeta(limite: 100000000, saldoInicial: 0, nombre: 'Konfío');

      final posicion = await obtenerPosicionCaja.ejecutar();
      final credito = await obtenerCreditoDisponible.ejecutar();

      expect(posicion.saldoDisponible, 500000, reason: 'Caja y bancos nunca incluye una línea de crédito');
      expect(credito.totalDisponible, 100000000, reason: 'Crédito disponible se calcula de forma completamente independiente');
    });
  });

  group('Política de saldo (v91) — Tiempo Extra', () {
    Future<CuentaFinancieraData> cuentaCon(int saldo) => cuentaFinancieraRepo.crear(
          codigo: 'CTA-SALDO',
          nombre: 'Cuenta acotada',
          tipo: TipoCuentaFinanciera.banco.name,
          saldoInicial: saldo,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );

    Future<RegistrarTiempoExtraResultado> pagar(String cuentaId, int monto) => registrar.ejecutar(
          fecha: DateTime(2026, 9, 3),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          empleadoCubreId: empleadoCubreId,
          turnoId: turnoId,
          montoTiempoExtra: monto,
          formaPago: 'transferencia',
          cuentaFinancieraId: cuentaId,
        );

    test('A) con saldo suficiente: se registra completo', () async {
      final cuenta = await cuentaCon(100000);
      expect(await pagar(cuenta.id, 100000), isA<RegistrarTiempoExtraExitoso>());
      expect(await cuentaFinancieraRepo.calcularSaldo(cuenta.id), 0);
    });

    test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
      final cuenta = await cuentaCon(50000);
      await expectLater(pagar(cuenta.id, 100000), throwsA(isA<SaldoInsuficienteException>()));

      expect(await db.select(db.tiempoExtra).get(), isEmpty, reason: 'ni el Tiempo Extra');
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'ni el Egreso');
      expect(await db.select(db.egresoFuente).get(), isEmpty, reason: 'ni su fuente');
      expect(await db.select(db.movimientoDeuda).get(), isEmpty, reason: 'ni ningún movimiento de deuda');
      expect(await cuentaFinancieraRepo.calcularSaldo(cuenta.id), 50000);
    });
  });
}
