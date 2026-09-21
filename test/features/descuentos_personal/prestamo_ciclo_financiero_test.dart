// Etapa "Cierre del ciclo financiero de Descuentos Programados —
// Préstamo/Botas": el desembolso real de un préstamo debe generar un
// Egreso vinculado por FK (nunca por texto), afectar la CuentaFinanciera
// correspondiente, y su recuperación vía Nómina NUNCA debe generar un
// Ingreso ni afectar Caja de nuevo (se representa por un menor Egreso de
// Nómina + reducción del saldo pendiente del préstamo). Una recuperación
// de concepto ya pagado en otro módulo (botas) NUNCA genera un segundo
// Egreso. Cubre los dos casos numéricos íntegros obligatorios (Secciones
// 15/16 del pedido) contra BD real (Drift `NativeDatabase.memory()`, sin
// mocks), más las reglas de corrección/cancelación/eliminación física.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/corregir_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/eliminar_descuento_programado_fisicamente_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DescuentoProgramadoRepository descuentoRepo;
  late EgresoRepositoryImpl egresoRepo;
  late CuentaFinancieraRepositoryImpl cuentaRepo;
  late CompraRepositoryImpl compraRepo;
  late RegistrarCompraUseCase registrarCompra;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;
  late CorregirDescuentoProgramadoUseCase corregirDescuento;
  late CancelarSaldoDescuentoProgramadoUseCase cancelarSaldo;
  late EliminarDescuentoProgramadoFisicamenteUseCase eliminarFisicamente;
  late ObtenerOrigenAutomaticoEgresoUseCase obtenerOrigenAutomatico;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late NominaRepositoryImpl nominaRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    egresoRepo = EgresoRepositoryImpl(db);
    cuentaRepo = CuentaFinancieraRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final asignacionRepo = AsignacionRepositoryImpl(db);
    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);

    descuentoRepo = DescuentoProgramadoRepositoryImpl(db, egresoRepo, codigoSecuencia);
    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, generarCodigo);
    corregirDescuento = CorregirDescuentoProgramadoUseCase(descuentoRepo);
    cancelarSaldo = CancelarSaldoDescuentoProgramadoUseCase(descuentoRepo);
    eliminarFisicamente = EliminarDescuentoProgramadoFisicamenteUseCase(descuentoRepo);

    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);

    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);
    obtenerOrigenAutomatico = ObtenerOrigenAutomaticoEgresoUseCase(
      compraRepo,
      pagoNominaRepo,
      TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo),
      deudaRepo,
      descuentoRepo,
      VehiculoMantenimientoRepositoryImpl(db),
      VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db)),
      RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
      LineaTelefonicaRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), LineaTelefonicaEquipoRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), AsignacionRepositoryImpl(db))),
      ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
    );

    nominaRepo = NominaRepositoryImpl(
      db,
      asignacionRepo,
      descuentoRepo,
      TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo),
      pagoNominaRepo,
    );
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-maestro'), nombre: 'Maestro', nombreUsuario: 'maestro', passwordHash: 'x'),
        );
  });

  tearDown(() => db.close());

  Future<CuentaFinancieraData> crearCuenta(String nombre, int saldoInicial) {
    return db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-$nombre',
            nombre: nombre,
            tipo: 'cuenta',
            saldoInicial: saldoInicial,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<EmpleadoData> crearEmpleado({int sueldoMensualAdministrativo = 3000000}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '10000000001',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  test('registrar un préstamo con cuenta de origen crea exactamente un Egreso y reduce esa CuentaFinanciera de inmediato', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();

    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuento = (registrado as RegistrarDescuentoProgramadoExitoso).descuento;

    expect(descuento.cuentaFinancieraId, bbva.id);
    expect(descuento.egresoId, isNotNull);
    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1), reason: 'exactamente un Egreso, nunca más');
    expect(egresos.single.monto, 500000);
    expect(egresos.single.cuentaFinancieraId, bbva.id);

    final saldos = await cuentaRepo.calcularSaldos([bbva.id]);
    expect(saldos[bbva.id], 1500000, reason: r'BBVA $20,000 - $5,000 = $15,000');

    final origen = await obtenerOrigenAutomatico.ejecutar(egresos.single.id);
    expect(origen, isA<OrigenAutomaticoEgresoDescuentoProgramado>());
    expect((origen as OrigenAutomaticoEgresoDescuentoProgramado).descuentoProgramadoId, descuento.id);
  });

  test(
    'invariante 1 DescuentoProgramado ↔ 1 Egreso: dos préstamos distintos siempre reciben Egresos distintos '
    '(garantizado por construcción — único sitio que escribe `egresoId` es `registrar()`, siempre justo después de '
    'crear un Egreso nuevo; ver `DescuentoProgramadoRepositoryImpl.registrar`, línea ~219)',
    () async {
      final bbva = await crearCuenta('BBVA', 5000000);
      final empleado = await crearEmpleado();

      final primero = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: 100000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 1, 20),
        esEntregaDinero: true,
        cuentaFinancieraId: bbva.id,
        formaPagoEgreso: 'transferencia',
      );
      final segundo = await registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 2),
        importeOriginal: 200000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 1, 21),
        esEntregaDinero: true,
        cuentaFinancieraId: bbva.id,
        formaPagoEgreso: 'transferencia',
      );
      final descuentoA = (primero as RegistrarDescuentoProgramadoExitoso).descuento;
      final descuentoB = (segundo as RegistrarDescuentoProgramadoExitoso).descuento;

      expect(descuentoA.egresoId, isNotNull);
      expect(descuentoB.egresoId, isNotNull);
      expect(descuentoA.egresoId, isNot(equals(descuentoB.egresoId)), reason: 'nunca deben compartir el mismo Egreso');

      final todosLosEgresos = await db.select(db.egreso).get();
      expect(todosLosEgresos.map((e) => e.id).toSet(), hasLength(2), reason: '2 descuentos → 2 Egresos distintos, cero colisión');

      // Cada Egreso resuelve de vuelta a SU propio descuento — nunca al otro.
      expect((await descuentoRepo.obtenerPorEgresoId(descuentoA.egresoId!))!.id, descuentoA.id);
      expect((await descuentoRepo.obtenerPorEgresoId(descuentoB.egresoId!))!.id, descuentoB.id);

      // Corregir A (cambio de cuenta/monto) nunca puede reasignarle el
      // Egreso de B — `corregir()` no acepta ningún parámetro de
      // `egresoId`, solo muta el que YA tenía el propio descuento.
      await corregirDescuento.ejecutar(
        descuentoProgramadoId: descuentoA.id,
        importeOriginal: 150000,
        numeroCuotas: 1,
        fechaPrimeraCuota: DateTime(2026, 2, 20),
        motivo: 'Corrección de prueba de la invariante',
      );
      final actualA = (await descuentoRepo.obtenerPorId(descuentoA.id))!;
      final actualB = (await descuentoRepo.obtenerPorId(descuentoB.id))!;
      expect(actualA.egresoId, descuentoA.egresoId, reason: 'sigue siendo el mismo Egreso propio, corregir nunca reasigna');
      expect(actualB.egresoId, descuentoB.egresoId, reason: 'el Egreso de B nunca se vio afectado');
    },
  );

  test('registrar botas (recuperación de concepto, sin cuenta) NO crea ningún Egreso ni toca ninguna CuentaFinanciera', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();

    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'botas',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 70000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: false,
    );
    final descuento = (registrado as RegistrarDescuentoProgramadoExitoso).descuento;

    expect(descuento.cuentaFinancieraId, isNull);
    expect(descuento.egresoId, isNull);
    expect(await db.select(db.egreso).get(), isEmpty);
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 2000000, reason: 'ningún desembolso — BBVA sin cambio');
  });

  test('registrar declarando entrega de dinero sin cuenta es rechazado', () async {
    final empleado = await crearEmpleado();
    final resultado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
    );
    expect(resultado, isA<RegistrarDescuentoProgramadoCuentaFinancieraRequerida>());
  });

  test('corregir: BBVA → Klar mueve el MISMO Egreso, nunca duplica', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final klar = await crearCuenta('Klar', 1000000);
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;
    final egresoIdOriginal = (await descuentoRepo.obtenerPorId(descuentoId))!.egresoId;

    final corregido = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      cuentaFinancieraId: klar.id,
      motivo: 'Se entregó realmente desde Klar, no BBVA',
    );
    expect(corregido, isA<CorregirDescuentoProgramadoExitoso>());

    expect(await db.select(db.egreso).get(), hasLength(1), reason: 'nunca se crea un segundo Egreso');
    final actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.egresoId, egresoIdOriginal, reason: 'sigue siendo el MISMO Egreso');
    expect(actual.cuentaFinancieraId, klar.id);
    expect((await cuentaRepo.calcularSaldos([bbva.id, klar.id])), {bbva.id: 2000000, klar.id: 500000});
  });

  test('corregir el importeOriginal sincroniza el monto del mismo Egreso (arreglo de error de captura)', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    final corregido = await corregirDescuento.ejecutar(
      descuentoProgramadoId: descuentoId,
      importeOriginal: 450000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      motivo: 'El monto real prestado fue menor',
    );
    expect(corregido, isA<CorregirDescuentoProgramadoExitoso>());

    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1));
    expect(egresos.single.monto, 450000);
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 2000000 - 450000);
  });

  test('cancelarSaldo revierte el Egreso cuando NADA se ha recuperado todavía', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    final cancelado = await cancelarSaldo.ejecutar(descuentoProgramadoId: descuentoId, motivo: 'Registrado por error, nunca se entregó');
    expect(cancelado, isA<CancelarSaldoDescuentoProgramadoExitoso>());

    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 2000000, reason: 'el Egreso se revirtió — BBVA vuelve exacto a su saldo original');
    final egreso = (await db.select(db.egreso).get()).single;
    expect(egreso.estatus, 'cancelado');
    final movimientos = await descuentoRepo.listarMovimientos(descuentoId);
    final cancelacion = movimientos.firstWhere((m) => m.tipoMovimiento == 'cancelacion');
    expect(cancelacion.datosRelevantes, contains('"egresoRevertido":true'));
  });

  test('cancelarSaldo NUNCA toca el Egreso cuando ya se recuperó algo — condonación pura', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final klar = await crearCuenta('Klar', 1000000);
    final empleado = await crearEmpleado(sueldoMensualAdministrativo: 1000000);
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    // Paga una quincena completa desde Klar — recupera $1,000 de cuota.
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: klar.id,
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    expect((await descuentoRepo.obtenerPorId(descuentoId))!.saldoPendiente, 400000);

    final cancelado = await cancelarSaldo.ejecutar(descuentoProgramadoId: descuentoId, motivo: 'Empleado liquidó el resto por fuera');
    expect(cancelado, isA<CancelarSaldoDescuentoProgramadoExitoso>());

    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 2000000 - 500000, reason: 'BBVA NUNCA recupera el desembolso histórico');
    final egreso = (await db.select(db.egreso).get()).firstWhere((e) => e.cuentaFinancieraId == bbva.id);
    expect(egreso.estatus, 'registrado', reason: 'el Egreso del desembolso original permanece intacto');
    final movimientos = await descuentoRepo.listarMovimientos(descuentoId);
    final cancelacion = movimientos.firstWhere((m) => m.tipoMovimiento == 'cancelacion');
    expect(cancelacion.datosRelevantes, contains('"egresoRevertido":false'));
  });

  test('eliminación física bloquea si hay una cuota reservada en una Nómina viva, incluso ya cancelado', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    // Genera (sin pagar) una Nómina que reserva la primera cuota.
    await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);
    final resumen = await descuentoRepo.obtenerResumenEliminacionFisica(descuentoId);
    expect(resumen.bloqueado, isTrue, reason: 'hay una cuota reservada en una Nómina viva');

    // El usecase bloquea primero por estatus (`activo`, nunca `cancelado`)
    // — nunca llega a evaluar la cuota reservada del repo.
    final resultado = await eliminarFisicamente.ejecutar(descuentoProgramadoId: descuentoId, motivo: 'Intento antes de cancelar');
    expect(resultado, isA<EliminarDescuentoProgramadoFisicamenteNoPermitido>());
  });

  test('eliminación física, tras cancelar sin nada recuperado, borra también el Egreso ya cancelado', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;
    final egresoId = (await descuentoRepo.obtenerPorId(descuentoId))!.egresoId!;

    await cancelarSaldo.ejecutar(descuentoProgramadoId: descuentoId, motivo: 'Registrado por error');
    final resultado = await eliminarFisicamente.ejecutar(descuentoProgramadoId: descuentoId, motivo: 'Prueba de registro erróneo');
    expect(resultado, isA<EliminarDescuentoProgramadoFisicamenteExitoso>());

    expect(await descuentoRepo.obtenerPorId(descuentoId), isNull);
    expect(await (db.select(db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull(), isNull, reason: 'el Egreso vinculado también se borra');
    final eventos = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(descuentoId))).get();
    expect(eventos.single.snapshotJson, contains('"egreso"'), reason: 'el snapshot incluye el Egreso borrado');
  });

  // ---------------------------------------------------------------------
  // Caso numérico íntegro obligatorio — PRÉSTAMO (Sección 15 del pedido).
  // ---------------------------------------------------------------------
  test('caso íntegro préstamo: registrar → pagar Nómina → cancelar pago → liquidar, BBVA nunca se mueve por Nómina', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    // Fondeada para las 5 quincenas del ciclo: desde la v91 una salida
    // sin saldo se rechaza, y esta prueba no va de eso.
    final klar = await crearCuenta('Klar', 100000000);
    // $20,000/mes ÷ 2 quincenas = $10,000 de percepciones por período,
    // exactamente el "Percepciones antes de descuento" del caso numérico.
    final empleado = await crearEmpleado(sueldoMensualAdministrativo: 2000000);

    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    // Tras registrar: BBVA=$15,000, saldoPendiente=$5,000, recuperado=$0,
    // cero Ingreso, exactamente un Egreso.
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 1500000);
    var actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.saldoPendiente, 500000);
    expect(actual.importeOriginal - actual.saldoPendiente, 0, reason: r'recuperado=$0');
    expect(await db.select(db.ingreso).get(), isEmpty);
    expect(await db.select(db.egreso).get(), hasLength(1));

    // Generar Nómina: Percepciones $10,000, cuota préstamo $1,000 →
    // Deducción $1,000, Neto $9,000.
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    var renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    expect(renglon.descuentosProgramados, 100000, reason: r'deducción = $1,000');
    expect(renglon.totalAPagar, 900000, reason: r'neto = $9,000');
    final cuotaAntesDePagar = (await descuentoRepo.listarCuotas(descuentoId)).first;
    expect(cuotaAntesDePagar.estatus, 'reservada');

    // Pagar la Nómina desde Klar.
    final pago = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: klar.id,
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    final pagoNominaId = (pago as RegistrarPagoNominaExitoso).pagoNomina.id;

    // Klar baja exactamente el pago de $9,000. Préstamo recuperado=$1,000,
    // saldoPendiente=$4,000. BBVA SIGUE en $15,000 — nunca sube.
    expect((await cuentaRepo.calcularSaldos([klar.id]))[klar.id], 100000000 - 900000);
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 1500000, reason: 'BBVA jamás se mueve por la recuperación de Nómina');
    actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.importeOriginal - actual.saldoPendiente, 100000, reason: r'recuperado = $1,000');
    expect(actual.saldoPendiente, 400000);
    expect(await db.select(db.ingreso).get(), isEmpty, reason: 'la recuperación NUNCA crea un Ingreso');

    // Cancelar/revertir el pago de Nómina: Klar regresa exacto a
    // $10,000, préstamo regresa a recuperado=$0/saldoPendiente=$5,000,
    // BBVA permanece exactamente en $15,000.
    await pagoNominaRepo.cancelar(pagoNominaId: pagoNominaId, motivo: 'Reversión de prueba del caso íntegro');
    expect((await cuentaRepo.calcularSaldos([klar.id]))[klar.id], 100000000, reason: 'Klar recupera el pago completo');
    actual = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(actual.importeOriginal - actual.saldoPendiente, 0);
    expect(actual.saldoPendiente, 500000);
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 1500000);

    // Vuelve a pagar y continúa hasta liquidar las 5 cuotas.
    var mes = 1;
    var quincena = TipoPeriodoNomina.primera;
    for (var i = 0; i < 5; i++) {
      GenerarNominaExitoso gen;
      if (i == 0) {
        gen = generado; // reusa la Nómina de enero-primera ya generada/cerrada
      } else {
        if (quincena == TipoPeriodoNomina.primera) {
          quincena = TipoPeriodoNomina.segunda;
        } else {
          quincena = TipoPeriodoNomina.primera;
          mes++;
        }
        gen = (await generarNomina.ejecutar(anio: 2026, mes: mes, tipo: quincena)) as GenerarNominaExitoso;
        await cerrarNomina.ejecutar(nominaId: gen.nomina.id);
      }
      final r = (await nominaRepo.listarEmpleados(gen.nomina.id)).single;
      await registrarPagoNomina.ejecutar(
        nominaId: gen.nomina.id,
        fechaPago: DateTime(2026, mes, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: klar.id,
        aplicaciones: [(nominaEmpleadoId: r.id, monto: r.totalAPagar)],
      );
    }

    final finalDescuento = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(finalDescuento.saldoPendiente, 0);
    expect(finalDescuento.estatus, 'liquidado');
    expect(await db.select(db.ingreso).get(), isEmpty, reason: 'nunca se generó ningún Ingreso artificial por las recuperaciones');
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 1500000, reason: 'BBVA solo se movió UNA vez, en el desembolso original');
  });

  // ---------------------------------------------------------------------
  // Segundo caso numérico íntegro obligatorio — BOTAS (Sección 16).
  // ---------------------------------------------------------------------
  test('caso íntegro botas: Compra real ya movió BBVA, el descuento de recuperación NO mueve BBVA de nuevo', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado(sueldoMensualAdministrativo: 1000000);

    final compra = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 1, 1),
      proveedor: 'Botas Industriales S.A.',
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      partidas: [PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Botas de trabajo', cantidad: 1, costoUnitario: 70000)],
    );
    final compraExitosa = compra as RegistrarCompraExitosa;
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 1930000, reason: r'BBVA $20,000 - $700 = $19,300 (Compra real)');

    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'botas',
      fechaRegistro: DateTime(2026, 1, 5),
      importeOriginal: 70000,
      numeroCuotas: 1,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: false,
    );
    final descuentoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.id;

    // Tras registrar el descuento: BBVA DEBE SEGUIR = $19,300.
    expect((await cuentaRepo.calcularSaldos([bbva.id]))[bbva.id], 1930000, reason: 'ningún segundo Egreso por el mismo costo');
    expect(await db.select(db.egreso).get(), hasLength(1), reason: 'sigue existiendo solo el Egreso de la Compra');

    // Recuperar vía Nómina hasta liquidar.
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    expect(renglon.descuentosProgramados, 70000);
    await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );

    final finalDescuento = (await descuentoRepo.obtenerPorId(descuentoId))!;
    expect(finalDescuento.saldoPendiente, 0);
    expect(finalDescuento.estatus, 'liquidado');
    expect(await db.select(db.ingreso).get(), isEmpty, reason: r'sin Ingreso ficticio de $700');
    expect(await db.select(db.egreso).get(), hasLength(2), reason: 'la Compra + el pago neto de Nómina, nunca un tercero por las botas');

    final origenCompra = await obtenerOrigenAutomatico.ejecutar(compraExitosa.compra.egresoId!);
    expect(origenCompra, isA<OrigenAutomaticoEgresoCompra>(), reason: 'el Egreso de la Compra nunca se confunde con el descuento de botas');
  });

  group('Política de saldo (v91) — préstamo con entrega de dinero', () {
    Future<RegistrarDescuentoProgramadoResultado> prestar(String cuentaId, int importe) async {
      final empleado = await crearEmpleado(sueldoMensualAdministrativo: 2000000);
      return registrarDescuento.ejecutar(
        empleadoId: empleado.id,
        tipo: 'prestamo',
        fechaRegistro: DateTime(2026, 1, 1),
        importeOriginal: importe,
        numeroCuotas: 5,
        fechaPrimeraCuota: DateTime(2026, 1, 20),
        esEntregaDinero: true,
        cuentaFinancieraId: cuentaId,
        formaPagoEgreso: 'transferencia',
      );
    }

    test('A) con saldo suficiente: el préstamo se entrega', () async {
      final cuenta = await crearCuenta('Acotada', 500000);
      expect(await prestar(cuenta.id, 500000), isA<RegistrarDescuentoProgramadoExitoso>());
      expect((await cuentaRepo.calcularSaldos([cuenta.id]))[cuenta.id], 0);
    });

    test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
      final cuenta = await crearCuenta('Acotada', 499999);
      await expectLater(prestar(cuenta.id, 500000), throwsA(isA<SaldoInsuficienteException>()));

      expect(await db.select(db.descuentoProgramadoEmpleado).get(), isEmpty, reason: 'ni el descuento');
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'ni el Egreso');
      expect(await db.select(db.egresoFuente).get(), isEmpty, reason: 'ni su fuente');
      expect((await cuentaRepo.calcularSaldos([cuenta.id]))[cuenta.id], 499999);
    });
  });
}
