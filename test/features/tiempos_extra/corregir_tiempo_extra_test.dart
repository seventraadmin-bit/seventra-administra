// Etapa "corrección real de Tiempo Extra" — edición real de una
// cobertura ya registrada, reemplazando "cancelar y volver a
// registrar" como única estrategia. Casos A-E del pedido explícito de
// Marlon: monto en la misma cuenta, cambio de cuenta, cambio de tipo
// de origen (Cuenta↔TDC), cambio de tarjeta, y edición de un costo
// adicional (monto/eliminar/agregar). Verifica también atomicidad,
// historial (antes/después) y ausencia de doble conteo.

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
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/corregir_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';

void main() {
  late AppDatabase db;
  late TiempoExtraRepositoryImpl tiempoExtraRepo;
  late RegistrarTiempoExtraUseCase registrar;
  late CorregirTiempoExtraUseCase corregir;
  late DeudaRepositoryImpl deudaRepo;
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
    final egresoRepo = EgresoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);

    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(codigoSecuencia));
    obtenerPosicionCaja = ObtenerPosicionDeCajaUseCase(cuentaFinancieraRepo);
    obtenerCreditoDisponible = ObtenerCreditoDisponibleTarjetasUseCase(deudaRepo);
    tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    registrar = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
    corregir = CorregirTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
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

  Future<CuentaFinancieraData> crearCuenta({required int saldoInicial, required String nombre, required String codigo}) {
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

  Future<TiempoExtraData> registrarBase({
    required int monto,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: monto,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
    );
    return (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
  }

  test('Caso A: \$1,620 BBVA -> \$1,800 BBVA: gasto operativo +180, BBVA disminuye otros 180, nunca duplica los 1,620 anteriores', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);

    final posicionAntes = await obtenerPosicionCaja.ejecutar();
    final gastoAntes = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 180000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      motivo: 'Corrección de monto',
    );
    expect(resultado, isA<CorregirTiempoExtraExitoso>());

    final posicionDespues = await obtenerPosicionCaja.ejecutar();
    expect(posicionDespues.saldoDisponible, posicionAntes.saldoDisponible - 18000, reason: 'BBVA disminuye únicamente los 180 adicionales');

    final gastoDespues = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    expect(gastoDespues, gastoAntes + 18000, reason: 'gasto operativo +180, nunca +1,800 (los 1,620 anteriores no se duplican)');

    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1), reason: 'nunca se crea un segundo Egreso — el mismo se sobreescribe');
    expect(egresos.single.monto, 180000);
  });

  test('Caso B: \$1,620 BBVA -> \$1,620 Klar: BBVA recupera 1,620, Klar disminuye 1,620, gasto operativo permanece 1,620', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final klar = await crearCuenta(saldoInicial: 3000000, nombre: 'Klar', codigo: 'CTA-000002');
    final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);

    final gastoAntes = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: klar.id,
      motivo: 'Cuenta equivocada',
    );
    expect(resultado, isA<CorregirTiempoExtraExitoso>());

    final saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
    expect(saldos[bbva.id], 5000000, reason: 'BBVA recupera exactamente los 1,620');
    expect(saldos[klar.id], 3000000 - 162000, reason: 'Klar disminuye exactamente 1,620');

    final gastoDespues = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    expect(gastoDespues, gastoAntes, reason: 'el gasto operativo total permanece sin cambio — solo cambió el origen');

    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1), reason: 'el mismo Egreso cambia de cuenta, nunca se crea uno nuevo');
  });

  test('CuentaFinanciera -> TDC: la cuenta recupera el monto, la tarjeta recibe el cargo completo', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 0, nombre: 'Konfío');
    final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'tarjeta',
      deudaIdTarjeta: konfio.id,
      motivo: 'En realidad se pagó con TDC',
    );
    final corregido = (resultado as CorregirTiempoExtraExitoso).tiempoExtra;
    expect(corregido.egresoId, isNull, reason: 'el origen ya no es una Cuenta — el puntero se limpia');
    expect(corregido.deudaId, konfio.id);

    final posicion = await obtenerPosicionCaja.ejecutar();
    expect(posicion.saldoDisponible, 5000000, reason: 'BBVA recupera el monto — el Egreso viejo se canceló');

    final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
    expect(konfioTras!.saldoActual, 162000, reason: 'Konfío recibe el cargo completo');

    final egresos = await db.select(db.egreso).get();
    expect(egresos.single.estatus, 'cancelado', reason: 'el Egreso viejo queda cancelado, nunca borrado (append-only)');
  });

  test('TDC -> CuentaFinanciera: la tarjeta revierte el cargo completo, la cuenta recibe un Egreso nuevo', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 0, nombre: 'Konfío');
    final tex = await registrarBase(monto: 162000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id);

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      motivo: 'En realidad se pagó desde BBVA',
    );
    final corregido = (resultado as CorregirTiempoExtraExitoso).tiempoExtra;
    expect(corregido.deudaId, isNull);
    expect(corregido.egresoId, isNotNull);

    final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
    expect(konfioTras!.saldoActual, 0, reason: 'Konfío revierte el cargo completo');

    final posicion = await obtenerPosicionCaja.ejecutar();
    expect(posicion.saldoDisponible, 5000000 - 162000);
  });

  test('Caso D: Uber \$350 Konfío -> \$350 Clara: Konfío revierte 350, Clara recibe cargo 350, gasto operativo sin cambio', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 3326608, nombre: 'Konfío');
    final clara = await crearTarjeta(limite: 2000000, saldoInicial: 500000, nombre: 'Clara');

    final tex = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      costosAdicionales: [
        CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
      ],
    ).then((r) => (r as RegistrarTiempoExtraExitoso).tiempoExtra);

    final costos = await tiempoExtraRepo.listarCostosAdicionales(tex.id);
    final uber = costos.single;
    final gastoAntes = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      cambiosCostos: [
        CorreccionCostoAdicionalEditar(costoAdicionalId: uber.id, concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: clara.id),
      ],
      motivo: 'Tarjeta equivocada',
    );
    expect(resultado, isA<CorregirTiempoExtraExitoso>());

    final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
    final claraTras = await deudaRepo.obtenerPorId(clara.id);
    expect(konfioTras!.saldoActual, 3326608, reason: 'Konfío revierte exactamente el cargo de Uber');
    expect(claraTras!.saldoActual, 500000 + 35000, reason: 'Clara recibe el cargo completo');

    final gastoDespues = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    expect(gastoDespues, gastoAntes, reason: 'el gasto operativo total no cambia — solo el origen de Uber');
  });

  test('Caso C: Uber \$350 Konfío -> \$420 Konfío (misma tarjeta): saldo +70, disponible -70, gasto +70', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 3326608, nombre: 'Konfío');

    final tex = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      costosAdicionales: [
        CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
      ],
    ).then((r) => (r as RegistrarTiempoExtraExitoso).tiempoExtra);

    final costos = await tiempoExtraRepo.listarCostosAdicionales(tex.id);
    final uber = costos.single;
    final creditoAntes = await obtenerCreditoDisponible.ejecutar();
    final gastoAntes = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    final movimientosAntes = await db.select(db.movimientoDeuda).get();

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      cambiosCostos: [
        CorreccionCostoAdicionalEditar(costoAdicionalId: uber.id, concepto: 'Uber', monto: 42000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
      ],
      motivo: 'Monto real era mayor',
    );
    expect(resultado, isA<CorregirTiempoExtraExitoso>());

    final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
    expect(konfioTras!.saldoActual, 3326608 + 42000, reason: 'saldo Konfío sube únicamente los 70 adicionales');

    final creditoDespues = await obtenerCreditoDisponible.ejecutar();
    expect(creditoDespues.totalDisponible, creditoAntes.totalDisponible - 7000, reason: 'crédito disponible baja únicamente 70');

    final gastoDespues = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    expect(gastoDespues, gastoAntes + 7000, reason: 'gasto operativo +70, nunca +420');

    final movimientosDespues = await db.select(db.movimientoDeuda).get();
    expect(movimientosDespues.length, movimientosAntes.length + 1, reason: 'exactamente 1 ajuste-delta nuevo, nunca reescribe el cargo original');
  });

  test('Caso E: eliminar un costo adicional (Uber \$350 Konfío): Konfío revierte 350, crédito se restaura, gasto -350', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final konfio = await crearTarjeta(limite: 4000000, saldoInicial: 3326608, nombre: 'Konfío');

    final tex = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      costosAdicionales: [
        CostoAdicionalInput(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
      ],
    ).then((r) => (r as RegistrarTiempoExtraExitoso).tiempoExtra);

    final costos = await tiempoExtraRepo.listarCostosAdicionales(tex.id);
    final uber = costos.single;
    final creditoAntes = await obtenerCreditoDisponible.ejecutar();
    final gastoAntes = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      cambiosCostos: [CorreccionCostoAdicionalQuitar(uber.id)],
      motivo: 'El Uber no ocurrió',
    );
    expect(resultado, isA<CorregirTiempoExtraExitoso>());

    final costosTras = await tiempoExtraRepo.listarCostosAdicionales(tex.id);
    expect(costosTras, isEmpty);

    final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
    expect(konfioTras!.saldoActual, 3326608, reason: 'Konfío revierte exactamente el cargo del Uber eliminado');

    final creditoDespues = await obtenerCreditoDisponible.ejecutar();
    expect(creditoDespues.totalDisponible, creditoAntes.totalDisponible + 35000, reason: 'crédito disponible se restaura');

    final gastoDespues = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    expect(gastoDespues, gastoAntes - 35000);
  });

  test('agregar un costo adicional nuevo durante la corrección aplica su propio origen, igual que en el alta', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final clara = await crearTarjeta(limite: 2000000, saldoInicial: 500000, nombre: 'Clara');
    final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);
    final gastoAntes = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 162000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      cambiosCostos: [
        CorreccionCostoAdicionalAgregar(concepto: 'Comida', monto: 20000, formaPago: 'tarjeta', deudaIdTarjeta: clara.id),
      ],
      motivo: 'Se me olvidó capturar la comida',
    );
    expect(resultado, isA<CorregirTiempoExtraExitoso>());

    final costos = await tiempoExtraRepo.listarCostosAdicionales(tex.id);
    expect(costos, hasLength(1));
    expect(costos.single.deudaId, clara.id);

    final claraTras = await deudaRepo.obtenerPorId(clara.id);
    expect(claraTras!.saldoActual, 500000 + 20000);

    final gastoDespues = (await obtenerResumenTiemposExtra.ejecutar()).gastoTotal;
    expect(gastoDespues, gastoAntes + 20000);
  });

  test(
    'rollback total: un costo agregado apuntando a una tarjeta inexistente revierte TODA la corrección — '
    'el monto/cuenta del pago base NUNCA queda a medias',
    () async {
      final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
      final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);

      await expectLater(
        tiempoExtraRepo.corregir(
          tiempoExtraId: tex.id,
          fecha: tex.fecha,
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: tex.motivoAusencia,
          empleadoCubreId: empleadoCubreId,
          turnoId: turnoId,
          montoTiempoExtra: 200000,
          formaPago: 'transferencia',
          cuentaFinancieraId: bbva.id,
          cambiosCostos: [
            CorreccionCostoAdicionalAgregar(concepto: 'Uber', monto: 35000, formaPago: 'tarjeta', deudaIdTarjeta: 'no-existe'),
          ],
          beneficiarioEgreso: 'Juan Apellido02',
          motivo: 'Corrección de prueba',
        ),
        throwsA(anything),
      );

      final actual = await tiempoExtraRepo.obtenerPorId(tex.id);
      expect(actual!.montoTiempoExtra, 162000, reason: 'el monto del pago base NUNCA cambió — rollback total');
      final egreso = await db.select(db.egreso).get();
      expect(egreso.single.monto, 162000, reason: 'el Egreso tampoco quedó corregido a medias');
      final costos = await tiempoExtraRepo.listarCostosAdicionales(tex.id);
      expect(costos, isEmpty, reason: 'el costo nuevo nunca sobrevivió — ni siquiera su fila');
    },
  );

  test('el historial (TiempoExtraEvento) conserva estadoAnterior/estadoNuevo con solo los campos que cambiaron', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);

    await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 180000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      motivo: 'Corrección de monto',
    );

    final eventos = await tiempoExtraRepo.listarEventos(tex.id);
    final corregido = eventos.singleWhere((e) => e.tipoEvento == 'corregido');
    expect(corregido.observacion, 'Corrección de monto');
    expect(corregido.estadoAnterior, contains('162000'));
    expect(corregido.estadoNuevo, contains('180000'));
  });

  test('rechaza corregir un TiempoExtra ya cancelado — la estrategia soportada sigue siendo cancelar + volver a registrar', () async {
    final bbva = await crearCuenta(saldoInicial: 5000000, nombre: 'BBVA', codigo: 'CTA-000001');
    final tex = await registrarBase(monto: 162000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);
    await tiempoExtraRepo.cancelar(tiempoExtraId: tex.id, motivo: 'Prueba');

    final resultado = await corregir.ejecutar(
      tiempoExtraId: tex.id,
      fecha: tex.fecha,
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: tex.motivoAusencia,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 180000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      motivo: 'Intento de corregir uno cancelado',
    );
    expect(resultado, isA<CorregirTiempoExtraYaCancelado>());
  });
}
