// Etapa "Ingresos y Egresos: corrección, cancelación, origen automático
// y trazabilidad integral". Cubre, contra BD real (nunca fakes):
//
// - Corrección de monto de Ingreso/Egreso MANUAL (antes imposible —
//   `corregirMonto` existía en el repositorio pero ningún caso de
//   uso/UI lo exponía).
// - Escenario BBVA/Klar (Sección 9 del pedido): registrar, corregir,
//   mover de cuenta, cancelar — saldos calculados a mano.
// - El hallazgo central de esta etapa: antes de estas correcciones,
//   NINGÚN código verificaba el origen antes de permitir corregir o
//   cancelar un Egreso directamente — Compra/Nómina/Tiempo Extra/pago
//   de Deuda podían editarse/cancelarse aquí sin que nada lo impidiera.
//   Se prueba el bloqueo real para los 5 orígenes automáticos.
// - Compra TDC / costo de Tiempo Extra TDC nunca generan Egreso (solo
//   MovimientoDeuda) — confirmando que el bloqueo no aplica donde no
//   hay Egreso que bloquear.
// - Eliminación física de un Egreso automático (Tiempo Extra/Deuda) —
//   antes fallaba con una excepción SQL cruda; ahora da el mensaje
//   amigable con el folio real, igual que ya pasaba con Compra/Nómina.
// - `ClasificarEgresosPorOrigenUseCase` clasifica Tiempo Extra
//   correctamente (antes se colaba como "manual").
// - Atomicidad de `corregir()` con monto.
// - Regresión Pago→Ingreso: corregir el Pago SÍ debe reflejarse en el
//   mismo Ingreso automático, Caja cambia exactamente la diferencia.
//
// Los asserts monetarios usan literales calculados a mano, nunca la
// misma fórmula de producción.

import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/ingreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_egreso_fisicamente_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  late IngresoRepository ingresoRepo;
  late EgresoRepository egresoRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late RegistrarIngresoManualUseCase registrarIngresoManual;
  late RegistrarEgresoUseCase registrarEgresoManual;
  late CorregirIngresoUseCase corregirIngreso;
  late CancelarIngresoUseCase cancelarIngreso;
  late CorregirEgresoUseCase corregirEgreso;
  late CancelarEgresoUseCase cancelarEgreso;
  late EliminarEgresoFisicamenteUseCase eliminarEgresoFisicamente;
  late ObtenerOrigenAutomaticoEgresoUseCase obtenerOrigenAutomatico;
  late ClasificarEgresosPorOrigenUseCase clasificarEgresos;

  late CompraRepository compraRepo;
  late RegistrarCompraUseCase registrarCompra;
  late DeudaRepositoryImpl deudaRepo;
  late RegistrarDeudaUseCase registrarDeuda;
  late RegistrarPagoDeudaUseCase registrarPagoDeuda;

  late EmpleadoRepository empleadoRepo;
  late ServicioRepository servicioRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late PagoNominaRepository pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;

  late TiempoExtraRepository tiempoExtraRepo;
  late RegistrarTiempoExtraUseCase registrarTiempoExtra;

  late PagoRepositoryImpl pagoRepo;
  late RegistrarPagoUseCase registrarPago;
  late CorregirPagoUseCase corregirPago;

  late String servicioId;
  late String empleadoAusenteId;
  late String turnoId;
  var empleadoContador = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_ingreso_egreso_correccion_test_');

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    ingresoRepo = IngresoRepositoryImpl(db);
    egresoRepo = EgresoRepositoryImpl(db);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    registrarIngresoManual = RegistrarIngresoManualUseCase(ingresoRepo, generarCodigo);
    corregirIngreso = CorregirIngresoUseCase(ingresoRepo);
    cancelarIngreso = CancelarIngresoUseCase(ingresoRepo);
    eliminarEgresoFisicamente = EliminarEgresoFisicamenteUseCase(egresoRepo);

    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    registrarEgresoManual = RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    registrarPagoDeuda = RegistrarPagoDeudaUseCase(deudaRepo, generarCodigo);

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final generarNumero = GenerarNumeroUseCase(CodigoSecuenciaService(db));
    const empleadoValidator = EmpleadoValidator();
    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo, ServicioComercialRepositoryImpl(db));

    tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), empleadoRepo, servicioRepo);
    registrarTiempoExtra = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));

    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      tiempoExtraRepo,
      PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))),
    );
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRevision);
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));

    obtenerOrigenAutomatico = ObtenerOrigenAutomaticoEgresoUseCase(
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      deudaRepo,
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      VehiculoMantenimientoRepositoryImpl(db),
      VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db)),
      RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
      LineaTelefonicaRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), LineaTelefonicaEquipoRepositoryImpl(db, AsignacionLineaTelefonicaRepositoryImpl(db), AsignacionRepositoryImpl(db))),
      ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
    );
    corregirEgreso = CorregirEgresoUseCase(egresoRepo, obtenerOrigenAutomatico, deudaRepo);
    cancelarEgreso = CancelarEgresoUseCase(egresoRepo, obtenerOrigenAutomatico);
    clasificarEgresos = ClasificarEgresosPorOrigenUseCase(
      egresoRepo,
      compraRepo,
      pagoNominaRepo,
      tiempoExtraRepo,
      RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db)),
      deudaRepo,
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      VehiculoMantenimientoRepositoryImpl(db),
      ServicioEventualRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), CuentaPorCobrarRepositoryImpl(db), PagoRepositoryImpl(db)),
    );

    pagoRepo = PagoRepositoryImpl(db);
    final clienteRepo = ClienteRepositoryImpl(db);
    registrarPago = RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigo);
    corregirPago = CorregirPagoUseCase(pagoRepo, CuentaPorCobrarRepositoryImpl(db), ComplementoPagoRepositoryImpl(db));

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Cliente de prueba'));
    final servicioCreado = await CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia de prueba', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 9001,
            nombres: 'Empleado de prueba',
            apellidoPaterno: 'Apellido',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX1',
            rfc: 'PEXJ90010111',
            nss: '1000000001',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    empleadoAusenteId = empleado.id;
    turnoId = SeedIds.modalidadTurno24x24;
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<CuentaFinancieraData> crearCuenta({required int saldoInicial, required String nombre, required String codigo}) {
    return cuentaFinancieraRepo.crear(
      codigo: codigo,
      nombre: nombre,
      tipo: TipoCuentaFinanciera.banco.name,
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
  }

  Future<EmpleadoData> crearEmpleadoDePrueba() async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Nomina$n',
      apellidoPaterno: 'Apellido$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900202HDFXXX$n',
      rfc: 'PEXJ900202$n',
      nss: '200000000$n',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: 1500000,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  Future<PagoNominaData> pagoNominaDePrueba({DateTime? fechaPago}) async {
    await crearEmpleadoDePrueba();
    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

    final resultado = await registrarPagoNomina.ejecutar(
      nominaId: generado.nomina.id,
      fechaPago: fechaPago ?? DateTime(2026, 1, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );
    return (resultado as RegistrarPagoNominaExitoso).pagoNomina;
  }

  Future<CompraData> compraDePrueba({DateTime? fecha, int costoUnitario = 50000, String? deudaId}) async {
    final resultado = await registrarCompra.ejecutar(
      fecha: fecha ?? DateTime(2026, 1, 10),
      proveedor: 'Proveedor de prueba',
      formaPago: deudaId != null ? 'tarjeta' : 'transferencia',
      deudaId: deudaId,
      partidas: [
        PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasto directo de prueba', cantidad: 1, costoUnitario: costoUnitario),
      ],
    );
    return (resultado as RegistrarCompraExitosa).compra;
  }

  Future<DeudaData> crearTarjeta({required int limite, int saldoInicial = 0, String nombre = 'TDC de prueba'}) async {
    final resultado = await registrarDeuda.ejecutar(
      nombre: nombre,
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: saldoInicial,
      fechaSaldoInicial: saldoInicial > 0 ? DateTime(2026, 1, 1) : null,
      tarjetaLimiteCredito: limite,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  Future<TiempoExtraData> tiempoExtraDePrueba({
    required int monto,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    List<CostoAdicionalInput> costosAdicionales = const [],
  }) async {
    final resultado = await registrarTiempoExtra.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      nombreExternoCubre: 'Cobertura externa de prueba',
      turnoId: turnoId,
      montoTiempoExtra: monto,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
      costosAdicionales: costosAdicionales,
    );
    return (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
  }

  group('Ingreso manual — corrección de monto (antes imposible)', () {
    test('corrige el monto y audita el diff completo en un solo evento', () async {
      final registrado = await registrarIngresoManual.ejecutar(monto: 500000, fecha: DateTime(2026, 2, 1), formaPago: 'efectivo', concepto: 'Venta de activo');
      final ingreso = (registrado as RegistrarIngresoManualExitoso).ingreso;

      final corregido = await corregirIngreso.ejecutar(ingresoId: ingreso.id, monto: 650000, concepto: 'Venta de activo (corregida)', motivo: 'Monto mal capturado');
      expect(corregido, isA<CorregirIngresoExitoso>());
      final actualizado = (corregido as CorregirIngresoExitoso).ingreso;
      expect(actualizado.monto, 650000);
      expect(actualizado.concepto, 'Venta de activo (corregida)');

      final eventos = await ingresoRepo.listarEventos(ingreso.id);
      final evento = eventos.firstWhere((e) => e.tipoEvento == 'corregido');
      expect(evento.estadoAnterior, contains('500000'));
      expect(evento.estadoAnterior, contains('Venta de activo'));
      expect(evento.estadoNuevo, contains('650000'));
      expect(evento.observacion, 'Monto mal capturado');
    });

    test('rechaza monto <= 0 y motivo vacío', () async {
      final registrado = await registrarIngresoManual.ejecutar(monto: 500000, fecha: DateTime(2026, 2, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final ingreso = (registrado as RegistrarIngresoManualExitoso).ingreso;

      final montoInvalido = await corregirIngreso.ejecutar(ingresoId: ingreso.id, monto: 0, motivo: 'Motivo válido');
      expect(montoInvalido, isA<CorregirIngresoMontoInvalido>());

      final motivoVacio = await corregirIngreso.ejecutar(ingresoId: ingreso.id, monto: 600000, motivo: '   ');
      expect(motivoVacio, isA<CorregirIngresoMotivoRequerido>());

      final sinTocar = await ingresoRepo.obtenerPorId(ingreso.id);
      expect(sinTocar!.monto, 500000, reason: 'ningún intento rechazado debe alterar el monto');
    });
  });

  group('Egreso manual — corrección de monto (antes imposible)', () {
    test('corrige el monto y audita el diff completo en un solo evento', () async {
      final registrado = await registrarEgresoManual.ejecutar(monto: 300000, fecha: DateTime(2026, 2, 1), formaPago: 'efectivo', concepto: 'Papelería');
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;

      final corregido = await corregirEgreso.ejecutar(egresoId: egreso.id, monto: 350000, concepto: 'Papelería (corregida)', motivo: 'Faltaba una factura');
      expect(corregido, isA<CorregirEgresoExitoso>());
      final actualizado = (corregido as CorregirEgresoExitoso).egreso;
      expect(actualizado.monto, 350000);

      final eventos = await egresoRepo.listarEventos(egreso.id);
      final evento = eventos.firstWhere((e) => e.tipoEvento == 'corregido');
      expect(evento.estadoAnterior, contains('300000'));
      expect(evento.estadoNuevo, contains('350000'));
    });

    test('rechaza monto <= 0 y motivo vacío', () async {
      final registrado = await registrarEgresoManual.ejecutar(monto: 300000, fecha: DateTime(2026, 2, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;

      final montoInvalido = await corregirEgreso.ejecutar(egresoId: egreso.id, monto: -100, motivo: 'Motivo válido');
      expect(montoInvalido, isA<CorregirEgresoMontoInvalido>());

      final motivoVacio = await corregirEgreso.ejecutar(egresoId: egreso.id, monto: 350000, motivo: '');
      expect(motivoVacio, isA<CorregirEgresoMotivoRequerido>());
    });
  });

  test(
    'Escenario BBVA/Klar (Sección 9): registrar, corregir, mover de cuenta, cancelar — saldos calculados a mano',
    () async {
      final bbva = await crearCuenta(saldoInicial: 2000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final klar = await crearCuenta(saldoInicial: 1000000, nombre: 'Klar', codigo: 'CTA-KLAR');

      // Ingreso manual BBVA +$5,000 -> BBVA $25,000
      final ingresoReg = (await registrarIngresoManual.ejecutar(
        monto: 500000,
        fecha: DateTime(2026, 3, 1),
        cuentaFinancieraId: bbva.id,
        formaPago: 'transferencia',
        concepto: 'Ingreso de prueba',
      )) as RegistrarIngresoManualExitoso;
      var saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[bbva.id], 2500000);
      expect(saldos[klar.id], 1000000);

      // Corregir a $6,000 -> BBVA $26,000
      await corregirIngreso.ejecutar(ingresoId: ingresoReg.ingreso.id, monto: 600000, motivo: 'Se capturó de menos');
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[bbva.id], 2600000);

      // Moverlo BBVA->Klar -> BBVA $20,000, Klar $16,000
      await corregirIngreso.ejecutar(ingresoId: ingresoReg.ingreso.id, cuentaFinancieraId: klar.id, motivo: 'Se depositó en la cuenta equivocada');
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[bbva.id], 2000000, reason: 'BBVA regresa exactamente a su saldo original — el Ingreso ya no le pertenece');
      expect(saldos[klar.id], 1600000);

      // Egreso manual Klar $2,000 -> Klar $14,000
      final egresoReg = (await registrarEgresoManual.ejecutar(
        monto: 200000,
        fecha: DateTime(2026, 3, 2),
        origen: OrigenFinancieroCuenta(klar.id),
        formaPago: 'transferencia',
        concepto: 'Egreso de prueba',
      )) as RegistrarEgresoExitoso;
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[klar.id], 1400000);

      // Corregirlo a $2,500 -> Klar $13,500
      await corregirEgreso.ejecutar(egresoId: egresoReg.egreso.id, monto: 250000, motivo: 'Faltaba un cargo');
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[klar.id], 1350000);

      // Moverlo Klar->BBVA -> Klar $16,000, BBVA $17,500
      await corregirEgreso.ejecutar(egresoId: egresoReg.egreso.id, origen: OrigenFinancieroCuenta(bbva.id), motivo: 'Se pagó desde la cuenta equivocada');
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[klar.id], 1600000, reason: 'Klar regresa exactamente a su saldo original — el Egreso ya no le pertenece');
      expect(saldos[bbva.id], 1750000);

      // Cancela ambos manuales -> BBVA regresa a $20,000, Klar a $10,000
      await cancelarIngreso.ejecutar(ingresoId: ingresoReg.ingreso.id, motivo: 'Se canceló la prueba');
      await cancelarEgreso.ejecutar(egresoId: egresoReg.egreso.id, motivo: 'Se canceló la prueba');
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id, klar.id]);
      expect(saldos[bbva.id], 2000000, reason: 'saldo inicial exacto, ningún movimiento cancelado cuenta');
      expect(saldos[klar.id], 1000000, reason: 'saldo inicial exacto, ningún movimiento cancelado cuenta');
    },
  );

  group('Bloqueo real: un Egreso automático nunca se corrige/cancela directamente desde Finanzas', () {
    test('Compra (Cuenta financiera): corregir/cancelar directamente se rechaza con el origen real', () async {
      final compra = await compraDePrueba();
      final egresoId = compra.egresoId!;

      final corregir = await corregirEgreso.ejecutar(egresoId: egresoId, monto: 999999, motivo: 'Intento directo');
      expect(corregir, isA<CorregirEgresoOrigenAutomatico>());
      expect((corregir as CorregirEgresoOrigenAutomatico).origen, isA<OrigenAutomaticoEgresoCompra>());
      expect((corregir.origen as OrigenAutomaticoEgresoCompra).compraId, compra.id);

      final cancelar = await cancelarEgreso.ejecutar(egresoId: egresoId, motivo: 'Intento directo');
      expect(cancelar, isA<CancelarEgresoOrigenAutomatico>());

      final egresoTrasIntentos = await egresoRepo.obtenerPorId(egresoId);
      expect(egresoTrasIntentos!.monto, 50000, reason: 'cero mutación tras el intento rechazado');
      expect(egresoTrasIntentos.estatus, 'registrado');
    });

    test('Pago de Nómina: corregir/cancelar directamente se rechaza con el origen real', () async {
      final pagoNomina = await pagoNominaDePrueba();
      final egresoId = pagoNomina.egresoId!;

      final corregir = await corregirEgreso.ejecutar(egresoId: egresoId, monto: 1, motivo: 'Intento directo');
      expect(corregir, isA<CorregirEgresoOrigenAutomatico>());
      expect((corregir as CorregirEgresoOrigenAutomatico).origen, isA<OrigenAutomaticoEgresoNomina>());
      expect((corregir.origen as OrigenAutomaticoEgresoNomina).pagoNominaId, pagoNomina.id);

      final cancelar = await cancelarEgreso.ejecutar(egresoId: egresoId, motivo: 'Intento directo');
      expect(cancelar, isA<CancelarEgresoOrigenAutomatico>());
    });

    test('Tiempo Extra (pago base, Cuenta financiera): corregir/cancelar directamente se rechaza con el origen real', () async {
      final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final tex = await tiempoExtraDePrueba(monto: 100000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);
      final egresoId = tex.egresoId!;

      final corregir = await corregirEgreso.ejecutar(egresoId: egresoId, monto: 1, motivo: 'Intento directo');
      expect(corregir, isA<CorregirEgresoOrigenAutomatico>());
      expect((corregir as CorregirEgresoOrigenAutomatico).origen, isA<OrigenAutomaticoEgresoTiempoExtra>());
      expect((corregir.origen as OrigenAutomaticoEgresoTiempoExtra).tiempoExtraId, tex.id);

      final cancelar = await cancelarEgreso.ejecutar(egresoId: egresoId, motivo: 'Intento directo');
      expect(cancelar, isA<CancelarEgresoOrigenAutomatico>());
    });

    test('Tiempo Extra (costo adicional, Cuenta financiera): corregir/cancelar directamente se rechaza con el origen real', () async {
      final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final tex = await tiempoExtraDePrueba(
        monto: 100000,
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
        costosAdicionales: [CostoAdicionalInput(concepto: 'Transporte', monto: 20000, formaPago: 'efectivo', cuentaFinancieraId: bbva.id)],
      );
      final costo = (await tiempoExtraRepo.listarCostosAdicionales(tex.id)).single;
      final egresoId = costo.egresoId!;

      final corregir = await corregirEgreso.ejecutar(egresoId: egresoId, monto: 1, motivo: 'Intento directo');
      expect(corregir, isA<CorregirEgresoOrigenAutomatico>());
      expect((corregir as CorregirEgresoOrigenAutomatico).origen, isA<OrigenAutomaticoEgresoTiempoExtra>());
      expect((corregir.origen as OrigenAutomaticoEgresoTiempoExtra).tiempoExtraId, tex.id, reason: 'el origen resuelto es el TiempoExtra dueño del costo');

      final cancelar = await cancelarEgreso.ejecutar(egresoId: egresoId, motivo: 'Intento directo');
      expect(cancelar, isA<CancelarEgresoOrigenAutomatico>());
    });

    test('Pago de Deuda/TDC: corregir/cancelar directamente se rechaza con el origen real (el bug más severo — antes cancelaba sin bloqueo)', () async {
      final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 500000, nombre: 'TDC de prueba');
      final resultado = await registrarPagoDeuda.ejecutar(deudaId: tarjeta.id, fecha: DateTime(2026, 4, 1), importe: 300000, formaPago: 'transferencia');
      expect(resultado, isA<RegistrarPagoDeudaExitoso>());
      final movimientos = await deudaRepo.listarMovimientos(tarjeta.id);
      final movimiento = movimientos.singleWhere((m) => m.tipo == 'pago');
      final egresoId = movimiento.egresoId!;

      final corregir = await corregirEgreso.ejecutar(egresoId: egresoId, monto: 1, motivo: 'Intento directo');
      expect(corregir, isA<CorregirEgresoOrigenAutomatico>());
      expect((corregir as CorregirEgresoOrigenAutomatico).origen, isA<OrigenAutomaticoEgresoDeuda>());
      expect((corregir.origen as OrigenAutomaticoEgresoDeuda).deudaId, tarjeta.id);

      final cancelar = await cancelarEgreso.ejecutar(egresoId: egresoId, motivo: 'Intento directo');
      expect(cancelar, isA<CancelarEgresoOrigenAutomatico>());

      final tarjetaTrasIntento = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(tarjetaTrasIntento!.saldoActual, 200000, reason: 'saldoInicial 500000 - pago 300000 = 200000; nunca se desincroniza por el intento rechazado');
    });
  });

  test('Compra pagada con TDC nunca genera Egreso — no hay nada que bloquear', () async {
    final tarjeta = await crearTarjeta(limite: 5000000);
    final compra = await compraDePrueba(deudaId: tarjeta.id);
    expect(compra.egresoId, isNull);
    expect(compra.deudaId, tarjeta.id);

    final movimientos = await deudaRepo.listarMovimientos(tarjeta.id);
    final cargo = movimientos.singleWhere((m) => m.tipo == 'cargoCompra');
    expect(cargo.egresoId, isNull, reason: 'un cargo a TDC nunca genera Egreso — se reconoce solo como MovimientoDeuda');
  });

  test('Costo adicional de Tiempo Extra pagado con TDC nunca genera Egreso — no hay nada que bloquear', () async {
    final tarjeta = await crearTarjeta(limite: 5000000);
    final tex = await tiempoExtraDePrueba(
      monto: 100000,
      formaPago: 'tarjeta',
      deudaIdTarjeta: tarjeta.id,
      costosAdicionales: [CostoAdicionalInput(concepto: 'Casetas', monto: 15000, formaPago: 'tarjeta', deudaIdTarjeta: tarjeta.id)],
    );
    expect(tex.egresoId, isNull);
    expect(tex.deudaId, tarjeta.id);
    final costo = (await tiempoExtraRepo.listarCostosAdicionales(tex.id)).single;
    expect(costo.egresoId, isNull);
    expect(costo.deudaId, tarjeta.id);
  });

  group('Eliminación física de un Egreso automático (Sección 8) — antes fallaba con una excepción SQL cruda', () {
    test('Tiempo Extra: bloqueada con el folio real, nunca una excepción cruda', () async {
      final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final tex = await tiempoExtraDePrueba(monto: 100000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);

      final resumen = await egresoRepo.obtenerResumenEliminacionFisica(tex.egresoId!);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains(tex.folio));

      final resultado = await eliminarEgresoFisicamente.ejecutar(egresoId: tex.egresoId!, motivo: 'Intento de limpieza');
      expect(resultado, isA<EliminarEgresoFisicamenteTieneDependencias>());
      expect((resultado as EliminarEgresoFisicamenteTieneDependencias).detalle, contains(tex.folio));
    });

    test('Pago de Deuda: bloqueada con el folio real, nunca una excepción cruda', () async {
      final tarjeta = await crearTarjeta(limite: 5000000, saldoInicial: 500000);
      final resultado = await registrarPagoDeuda.ejecutar(deudaId: tarjeta.id, fecha: DateTime(2026, 4, 1), importe: 300000, formaPago: 'transferencia');
      expect(resultado, isA<RegistrarPagoDeudaExitoso>());
      final movimientos = await deudaRepo.listarMovimientos(tarjeta.id);
      final movimiento = movimientos.singleWhere((m) => m.tipo == 'pago');

      final resumen = await egresoRepo.obtenerResumenEliminacionFisica(movimiento.egresoId!);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains(tarjeta.folio));

      final eliminar = await eliminarEgresoFisicamente.ejecutar(egresoId: movimiento.egresoId!, motivo: 'Intento de limpieza');
      expect(eliminar, isA<EliminarEgresoFisicamenteTieneDependencias>());
    });
  });

  test('ClasificarEgresosPorOrigenUseCase clasifica Tiempo Extra correctamente (antes se colaba como manual — bug real)', () async {
    final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
    final tex = await tiempoExtraDePrueba(monto: 100000, formaPago: 'transferencia', cuentaFinancieraId: bbva.id);
    await registrarEgresoManual.ejecutar(monto: 50000, fecha: DateTime(2026, 9, 3), formaPago: 'efectivo', concepto: 'Gasto manual real');

    final resumen = await clasificarEgresos.ejecutar(rangoInicio: DateTime(2026, 9, 1), rangoFin: DateTime(2026, 9, 30));
    expect(resumen.totalTiempoExtra, 100000);
    expect(resumen.totalManual, 50000, reason: 'el gasto manual real sigue siendo el único que cuenta como manual');
    final clasificado = resumen.detalle.singleWhere((d) => d.egreso.id == tex.egresoId);
    expect(clasificado.origen, OrigenEgreso.tiempoExtra);
  });

  group('Atomicidad', () {
    test('un fallo real durante la corrección de un Ingreso revierte TODO (monto, cuenta, auditoría)', () async {
      final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final registrado = await registrarIngresoManual.ejecutar(monto: 200000, fecha: DateTime(2026, 2, 1), cuentaFinancieraId: bbva.id, formaPago: 'efectivo', concepto: 'Concepto');
      final ingreso = (registrado as RegistrarIngresoManualExitoso).ingreso;
      final eventosAntes = await ingresoRepo.listarEventos(ingreso.id);

      await expectLater(
        () => db.transaction(() async {
          await (db.update(db.ingreso)..where((t) => t.id.equals(ingreso.id))).write(const IngresoCompanion(monto: Value(999999999)));
          throw StateError('Fallo real provocado a mitad de la transacción');
        }),
        throwsA(anything),
      );

      final despues = await ingresoRepo.obtenerPorId(ingreso.id);
      expect(despues!.monto, 200000, reason: 'rollback completo — el monto nunca quedó a medias');
      final eventosDespues = await ingresoRepo.listarEventos(ingreso.id);
      expect(eventosDespues.length, eventosAntes.length);
    });

    test('un fallo real durante la corrección de un Egreso revierte TODO (monto, cuenta, auditoría)', () async {
      final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final registrado = await registrarEgresoManual.ejecutar(monto: 200000, fecha: DateTime(2026, 2, 1), origen: OrigenFinancieroCuenta(bbva.id), formaPago: 'efectivo', concepto: 'Concepto');
      final egreso = (registrado as RegistrarEgresoExitoso).egreso;
      final eventosAntes = await egresoRepo.listarEventos(egreso.id);

      await expectLater(
        () => db.transaction(() async {
          await (db.update(db.egreso)..where((t) => t.id.equals(egreso.id))).write(const EgresoCompanion(monto: Value(999999999)));
          throw StateError('Fallo real provocado a mitad de la transacción');
        }),
        throwsA(anything),
      );

      final despues = await egresoRepo.obtenerPorId(egreso.id);
      expect(despues!.monto, 200000, reason: 'rollback completo — el monto nunca quedó a medias');
      final eventosDespues = await egresoRepo.listarEventos(egreso.id);
      expect(eventosDespues.length, eventosAntes.length);
    });
  });

  test(
    'Regresión Pago->Ingreso (Sección 11): corregir el Pago SÍ se refleja en el mismo Ingreso automático, Caja cambia exactamente la diferencia',
    () async {
      final bbva = await crearCuenta(saldoInicial: 1000000, nombre: 'BBVA', codigo: 'CTA-BBVA');
      final clienteRepo = ClienteRepositoryImpl(db);
      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Cliente Pago'));

      final registrado = await registrarPago.ejecutar(
        clienteId: cliente.id,
        montoTotal: 1000000,
        fechaPago: DateTime(2026, 5, 1),
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;
      final ingreso = (await ingresoRepo.obtenerPorPagoId(pago.id))!;
      expect(ingreso.monto, 1000000);

      var saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id]);
      expect(saldos[bbva.id], 2000000);

      // Intentar corregir el Ingreso directamente -> rechazado, Caja intacta.
      final intento = await corregirIngreso.ejecutar(ingresoId: ingreso.id, monto: 800000, motivo: 'Intento directo');
      expect(intento, isA<CorregirIngresoPagoAutomatico>());
      final ingresoTrasIntento = await ingresoRepo.obtenerPorId(ingreso.id);
      expect(ingresoTrasIntento!.monto, 1000000);
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id]);
      expect(saldos[bbva.id], 2000000);

      // Corregir el Pago a $12,000 -> mismo Ingreso automático $12,000, Caja aumenta exactamente $2,000.
      final corregido = await corregirPago.ejecutar(pagoId: pago.id, montoTotal: 1200000, motivo: 'Se recibió más de lo registrado');
      expect(corregido, isA<CorregirPagoExitoso>());
      final ingresoTrasCorregir = await ingresoRepo.obtenerPorId(ingreso.id);
      expect(ingresoTrasCorregir!.monto, 1200000, reason: 'el mismo Ingreso automático se sincroniza, nunca un segundo Ingreso');
      saldos = await cuentaFinancieraRepo.calcularSaldos([bbva.id]);
      expect(saldos[bbva.id], 2200000, reason: r'Caja aumenta exactamente la diferencia de $2,000, nunca $1,000+$1,200');
    },
  );
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
