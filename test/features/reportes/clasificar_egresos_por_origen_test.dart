// Etapa "Cierre del ciclo financiero de Descuentos Programados —
// pendientes de cierre": `ClasificarEgresosPorOrigenUseCase` (Reportes)
// no reconocía el Egreso de un préstamo (DescuentoProgramadoEmpleado.
// egresoId) — se clasificaba como `manual`. Cubre, contra BD real
// (Drift `NativeDatabase.memory()`, sin mocks), los 6 orígenes
// automáticos + manual, y confirma que Botas (recuperación de
// concepto, sin `egresoId`) nunca genera ni clasifica un Egreso
// inexistente.

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
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
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresoRepo;
  late DeudaRepositoryImpl deudaRepo;
  late ClasificarEgresosPorOrigenUseCase clasificar;
  late RegistrarEgresoUseCase registrarEgreso;
  late RegistrarCompraUseCase registrarCompra;
  late RegistrarTiempoExtraUseCase registrarTiempoExtra;
  late RegistrarDescuentoProgramadoUseCase registrarDescuento;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late NominaRepositoryImpl nominaRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);

    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    final descuentoRepo = DescuentoProgramadoRepositoryImpl(db, egresoRepo, codigoSecuencia);
    final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo);

    registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo);
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    registrarTiempoExtra = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
    registrarDescuento = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, generarCodigo);

    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), descuentoRepo, tiempoExtraRepo, pagoNominaRepo);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));

    clasificar = ClasificarEgresosPorOrigenUseCase(
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

  Future<EmpleadoData> crearEmpleado({int numero = 1, int sueldoMensualAdministrativo = 3000000}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Empleado$numero',
            apellidoPaterno: 'Apellido$numero',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ90010${numero}HDFXXX0$numero',
            rfc: 'PEXJ90010${numero}AB$numero',
            nss: '1000000000$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  Future<DeudaData> crearTarjeta(String nombre, int saldoActual) {
    return db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(folio: 'DEU-$nombre', nombre: nombre, tipo: 'tarjetaCredito', saldoActual: saldoActual),
        );
  }

  test('Egreso manual se clasifica como manual', () async {
    final bbva = await crearCuenta('BBVA', 1000000);
    final resultado = await registrarEgreso.ejecutar(
      monto: 50000,
      fecha: DateTime(2026, 1, 5),
      origen: OrigenFinancieroCuenta(bbva.id),
      formaPago: 'transferencia',
      concepto: 'Gasto administrativo manual',
    );
    final egresoId = (resultado as RegistrarEgresoExitoso).egreso.id;

    final clasificado = await clasificar.ejecutar();
    final origen = clasificado.detalle.firstWhere((e) => e.egreso.id == egresoId).origen;
    expect(origen, OrigenEgreso.manual);
    expect(clasificado.totalManual, 50000);
  });

  test('Egreso de una Compra se clasifica como compra', () async {
    final bbva = await crearCuenta('BBVA', 1000000);
    final compra = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 1, 5),
      proveedor: 'Proveedor de prueba',
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Insumo', cantidad: 1, costoUnitario: 30000)],
    );
    final egresoId = (compra as RegistrarCompraExitosa).compra.egresoId!;

    final clasificado = await clasificar.ejecutar();
    final origen = clasificado.detalle.firstWhere((e) => e.egreso.id == egresoId).origen;
    expect(origen, OrigenEgreso.compra);
    expect(clasificado.totalCompra, 30000);
  });

  test('Egreso de un pago de Nómina se clasifica como nomina', () async {
    final bbva = await crearCuenta('BBVA', 1000000);
    final empleado = await crearEmpleado(sueldoMensualAdministrativo: 2000000);
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
    final pago = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    final egresoId = (pago as RegistrarPagoNominaExitoso).pagoNomina.egresoId!;
    expect(empleado, isNotNull);

    final clasificado = await clasificar.ejecutar();
    final origen = clasificado.detalle.firstWhere((e) => e.egreso.id == egresoId).origen;
    expect(origen, OrigenEgreso.nomina);
    expect(clasificado.totalNomina, renglon.totalAPagar);
  });

  test('Egreso de un pago base de Tiempo Extra se clasifica como tiempoExtra', () async {
    final bbva = await crearCuenta('BBVA', 1000000);
    final ausente = await crearEmpleado(numero: 1);
    final cubre = await crearEmpleado(numero: 2);

    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Cliente de prueba'));
    final servicioCreado = await CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(codigoSecuencia), ServicioValidator(clienteRepo, catalogoRepo))
        .ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Servicio de prueba', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final registrado = await registrarTiempoExtra.ejecutar(
      fecha: DateTime(2026, 1, 5),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: ausente.id,
      motivoAusencia: 'incapacidad',
      empleadoCubreId: cubre.id,
      turnoId: SeedIds.modalidadTurno24x24,
      montoTiempoExtra: 20000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
    );
    final tiempoExtra = (registrado as RegistrarTiempoExtraExitoso).tiempoExtra;
    final egresoId = tiempoExtra.egresoId!;

    final clasificado = await clasificar.ejecutar();
    final origen = clasificado.detalle.firstWhere((e) => e.egreso.id == egresoId).origen;
    expect(origen, OrigenEgreso.tiempoExtra);
    expect(clasificado.totalTiempoExtra, 20000);
  });

  test('Egreso de un pago de Deuda (TDC) se clasifica como deuda', () async {
    final bbva = await crearCuenta('BBVA', 1000000);
    final tarjeta = await crearTarjeta('Konfío', 40000);
    final folioEgreso = await CodigoSecuenciaService(db).siguienteCodigo('egreso');
    await deudaRepo.registrarPago(
      deudaId: tarjeta.id,
      folioEgreso: folioEgreso,
      fecha: DateTime(2026, 1, 5),
      importe: 40000,
      formaPago: 'transferencia',
      cuentaFinancieraId: bbva.id,
    );
    final movimientoPago = (await deudaRepo.listarMovimientos(tarjeta.id)).firstWhere((m) => m.tipo == 'pago');
    final egresoId = movimientoPago.egresoId!;

    final clasificado = await clasificar.ejecutar();
    final origen = clasificado.detalle.firstWhere((e) => e.egreso.id == egresoId).origen;
    expect(origen, OrigenEgreso.deuda);
    expect(clasificado.totalDeuda, 40000);
  });

  test('Egreso del desembolso de un préstamo se clasifica como descuentoProgramado, nunca manual', () async {
    final bbva = await crearCuenta('BBVA', 2000000);
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 5),
      importeOriginal: 500000,
      numeroCuotas: 5,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: true,
      cuentaFinancieraId: bbva.id,
      formaPagoEgreso: 'transferencia',
    );
    final egresoId = (registrado as RegistrarDescuentoProgramadoExitoso).descuento.egresoId!;

    final clasificado = await clasificar.ejecutar();
    final origen = clasificado.detalle.firstWhere((e) => e.egreso.id == egresoId).origen;
    expect(origen, OrigenEgreso.descuentoProgramado, reason: 'nunca debe caer en el bucket manual');
    expect(clasificado.totalDescuentoProgramado, 500000);
    expect(clasificado.totalManual, 0);
  });

  test('Botas (recuperación de concepto, sin egresoId) no genera ni clasifica ningún Egreso', () async {
    final empleado = await crearEmpleado();
    final registrado = await registrarDescuento.ejecutar(
      empleadoId: empleado.id,
      tipo: 'botas',
      fechaRegistro: DateTime(2026, 1, 5),
      importeOriginal: 70000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 1, 20),
      esEntregaDinero: false,
    );
    final descuento = (registrado as RegistrarDescuentoProgramadoExitoso).descuento;
    expect(descuento.egresoId, isNull);

    final clasificado = await clasificar.ejecutar();
    expect(clasificado.detalle, isEmpty, reason: 'no existe ningún Egreso real que clasificar');
    expect(clasificado.totalCompra + clasificado.totalNomina + clasificado.totalTiempoExtra + clasificado.totalDeuda + clasificado.totalDescuentoProgramado + clasificado.totalManual, 0);
  });

  // Hueco encontrado por la no-vacuidad: romper la clasificación de
  // Telefonía no hacía fallar nada porque ninguna prueba la cubría.
  test('Egreso de una recarga de Telefonía se clasifica como telefonia, nunca manual', () async {
    final codigoSecuencia = CodigoSecuenciaService(db);
    final recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia);
    final lineaRepo = LineaTelefonicaRepositoryImpl(
      db,
      AsignacionLineaTelefonicaRepositoryImpl(db),
      LineaTelefonicaEquipoRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), AsignacionRepositoryImpl(db)),
    );
    final cuenta = await CuentaFinancieraRepositoryImpl(db).crear(
      codigo: 'CTA-TEL',
      nombre: 'BBVA Empresarial',
      tipo: TipoCuentaFinanciera.banco.name,
      saldoInicial: 10000000,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
    final linea = (await CrearLineaTelefonicaUseCase(lineaRepo, GenerarCodigoUseCase(codigoSecuencia)).ejecutar(
      numero: '7225562629',
      operador: OperadorTelefonico.telcel.name,
      modalidadSim: ModalidadSim.fisica.name,
    ) as CrearLineaTelefonicaExitoso)
        .linea;

    await RegistrarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo, deudaRepo).ejecutar(
      lineaTelefonicaId: linea.id,
      fecha: DateTime(2026, 3, 1),
      importe: 20000,
      formaPago: FormaPago.transferencia.name,
      cuentaFinancieraId: cuenta.id,
    );

    final clasificado = await clasificar.ejecutar();
    final deTelefonia = clasificado.detalle.where((e) => e.origen == OrigenEgreso.telefonia).toList();

    expect(deTelefonia, hasLength(1), reason: 'Finanzas tiene que reconocer de dónde salió');
    expect(deTelefonia.single.egreso.monto, 20000);
    expect(clasificado.totalTelefonia, 20000);
    expect(clasificado.totalManual, 0, reason: 'un Egreso automático nunca es "manual"');
  });
}
