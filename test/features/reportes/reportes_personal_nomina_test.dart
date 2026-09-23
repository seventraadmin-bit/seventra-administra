// Etapa 12B (Reportes generales — Personal · Nómina) — pruebas de
// repositorio/caso de uso: administrativo vs. operativo derivado sin
// bandera nueva, altas/reingresos/bajas respetando EmpleadoPeriodoLaboral
// (nunca solo el estado actual), histórico de Nómina congelado aunque
// Personal cambie después, generado/pagado/pendiente sin confundir ejes
// de fecha, y las proyecciones seguras (`EmpleadoReporteRow`/
// `NominaEmpleadoReporteRow`) nunca exponiendo campos sensibles.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
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
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/obtener_plantilla_personal_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_reingreso_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  late EmpleadoRepository empleadoRepo;
  late AsignacionServicioRepository asignacionRepo;
  late ServicioRepository servicioRepo;
  late ClienteRepositoryImpl clienteRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late RegistrarBajaLaboralUseCase registrarBaja;
  late RegistrarReingresoUseCase registrarReingreso;
  late CrearServicioUseCase crearServicio;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;

  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late PagoNominaRepository pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;

  late ObtenerResumenPersonalUseCase obtenerResumenPersonal;
  late ObtenerResumenNominaUseCase obtenerResumenNomina;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_reportes_personal_nomina_test_');

    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      generarNumero,
      empleadoValidator,
      servicioRepo,
      ServicioComercialRepositoryImpl(db),
    );
    registrarBaja = RegistrarBajaLaboralUseCase(empleadoRepo, empleadoValidator, AsignacionRepositoryImpl(db), AsignacionVehiculoRepositoryImpl(db), usuarioRepository: UsuarioRepositoryImpl(db));
    registrarReingreso = RegistrarReingresoUseCase(empleadoRepo, empleadoValidator);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);

    final egresoRepo = EgresoRepositoryImpl(db);
    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRevision);
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));

    obtenerResumenPersonal = ObtenerResumenPersonalUseCase(
      empleadoRepo,
      asignacionRepo,
      ObtenerPlantillaPersonalUseCase(empleadoRepo, asignacionRepo, puestoRepo),
    );
    obtenerResumenNomina = ObtenerResumenNominaUseCase(nominaRepo, pagoNominaRepo);
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  var empleadoContador = 0;
  var clienteContador = 0;

  Future<EmpleadoData> crearEmpleadoDePrueba({
    DateTime? fechaIngreso,
    int sueldoMensualAdministrativo = 1500000,
    String? servicioId,
    String? sucursalId,
  }) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Empleado$n',
      apellidoPaterno: 'Apellido$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900101HDFXXX$n',
      rfc: 'PEXJ900101$n',
      nss: '100000000$n',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: servicioId == null ? sueldoMensualAdministrativo : null,
      servicioId: servicioId,
      sucursalId: sucursalId,
      sueldoMensualAsignacion: servicioId == null ? null : 1500000,
      bonoMensualAsignacion: servicioId == null ? null : 0,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  Future<ClienteData> crearClienteDePrueba() {
    clienteContador++;
    return clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${clienteContador.toString().padLeft(6, '0')}', nombreComercial: 'Cliente de prueba'),
    );
  }

  /// Servicio activo, con sueldo de referencia capturado — listo para
  /// asignar un Empleado operativo.
  Future<ServicioData> crearServicioActivoDePrueba() async {
    final cliente = await crearClienteDePrueba();
    final creado = (await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Servicio de prueba',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2025, 1, 1),
      ),
    )) as GuardarServicioExitoso;

    await db.into(db.direccion).insert(
          DireccionCompanion.insert(
            servicioId: Value(creado.servicio.id),
            tipoDireccion: TipoDireccion.operativa.name,
            calle: 'Av. de prueba',
            numeroExterior: '1',
            colonia: 'Centro',
            municipioAlcaldia: 'Toluca',
            estado: 'Estado de México',
            codigoPostal: '50000',
          ),
        );
    final activado = (await cambiarEstatusServicio.ejecutar(servicioId: creado.servicio.id, nuevo: EstatusServicio.activo, motivo: 'Motivo de prueba'))
        as CambiarEstatusServicioExitoso;
    return activado.servicio;
  }

  group('EmpleadoRepository.listarParaReporte — proyección segura', () {
    test('no expone datos bancarios ni CURP/RFC/NSS (no existen como campos en el DTO)', () async {
      await crearEmpleadoDePrueba();
      final filas = await empleadoRepo.listarParaReporte(estatus: 'activo');

      expect(filas, hasLength(1));
      // La proyección segura (EmpleadoReporteRow) estructuralmente no
      // tiene getters bancoId/numeroCuentaTarjeta/clabe/curp/rfc/nss —
      // si este archivo compila, ya está probado que no existen; aquí
      // confirmamos los campos que SÍ trae son los correctos.
      expect(filas.single.numeroEmpleado, greaterThan(0));
      expect(filas.single.nombreCompleto, contains('Empleado'));
    });
  });

  group('Administrativo vs. operativo — sin bandera nueva', () {
    // Etapa "Plantilla operativa vs. administrativa": la regla se
    // corrigió. Antes bastaba NO tener Servicio para contar como
    // administrativo, sin mirar nunca `sucursalId` — un empleado sin
    // ningún destino se volvía administrativo en silencio, y el
    // Dashboard al mismo empleado lo llamaba "sin asignar". Ahora
    // administrativo = adscrito a una SUCURSAL, y ambas pantallas
    // consumen la misma fuente de verdad.
    test('Servicio = operativo y Sucursal = administrativo, derivados de la estructura y nunca de una columna en Empleado',
        () async {
      final servicio = await crearServicioActivoDePrueba();
      final sucursal = await db.into(db.sucursal).insertReturning(
        SucursalCompanion.insert(
          codigo: 'SUC-000001',
          nombre: 'Toluca',
          tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
        ),
      );

      await crearEmpleadoDePrueba(servicioId: servicio.id);
      await crearEmpleadoDePrueba(sucursalId: sucursal.id);

      final resumen = await obtenerResumenPersonal.ejecutar();

      expect(resumen.totalActivos, 2);
      expect(resumen.totalOperativos, 1);
      expect(resumen.totalAdministrativos, 1);
      expect(resumen.personalPorServicio[servicio.id], 1);
    });

    test('un empleado sin Servicio y sin Sucursal ya NO se cuenta como administrativo', () async {
      await crearEmpleadoDePrueba();

      final resumen = await obtenerResumenPersonal.ejecutar();

      expect(resumen.totalActivos, 1);
      expect(resumen.totalAdministrativos, 0, reason: 'sin destino no es administrativo');
      expect(resumen.totalOperativos, 0);
    });
  });

  group('Altas / reingresos / bajas en el periodo — respeta EmpleadoPeriodoLaboral', () {
    test('un alta original se clasifica como alta, no como reingreso', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2026, 1, 10));

      final resumen = await obtenerResumenPersonal.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.altasEnPeriodo, hasLength(1));
      expect(resumen.reingresosEnPeriodo, isEmpty);
    });

    test('baja y reingreso posterior: la baja aparece en el periodo correcto y el reingreso se distingue del alta', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));

      await registrarBaja.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2025, 6, 15), motivo: MotivoBajaEmpleado.renuncia);
      await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 2, 1));

      final resumenBaja = await obtenerResumenPersonal.ejecutar(rangoInicio: DateTime(2025, 6, 1), rangoFin: DateTime(2025, 6, 30));
      expect(resumenBaja.bajasEnPeriodo, hasLength(1));
      expect(resumenBaja.bajasEnPeriodo.single.motivoBaja, MotivoBajaEmpleado.renuncia);

      final resumenReingreso = await obtenerResumenPersonal.ejecutar(rangoInicio: DateTime(2026, 2, 1), rangoFin: DateTime(2026, 2, 28));
      expect(resumenReingreso.reingresosEnPeriodo, hasLength(1));
      expect(resumenReingreso.altasEnPeriodo, isEmpty, reason: 'un reingreso nunca debe contarse como alta');
    });

    test('periodo vacío: listas vacías, sin excepciones', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2020, 1, 1));

      final resumen = await obtenerResumenPersonal.ejecutar(rangoInicio: DateTime(2030, 1, 1), rangoFin: DateTime(2030, 1, 31));

      expect(resumen.altasEnPeriodo, isEmpty);
      expect(resumen.reingresosEnPeriodo, isEmpty);
      expect(resumen.bajasEnPeriodo, isEmpty);
      expect(resumen.motivosBajaConteo, isEmpty);
    });
  });

  group('NominaRepository.listarRenglonesEnRango — proyección segura', () {
    test('no expone bancoNombre/numeroCuentaTarjeta/clabe (no existen como campos en el DTO)', () async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final renglones = await nominaRepo.listarRenglonesEnRango(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(renglones, hasLength(1));
      expect(renglones.single.numeroEmpleado, greaterThan(0));
      // Igual que arriba: NominaEmpleadoReporteRow no tiene getters
      // bancarios — si compila, la exclusión estructural ya está
      // probada; aquí confirmamos que sí trae lo esperado.
      expect(renglones.single.totalAPagar, greaterThan(0));
    });
  });

  group('ObtenerResumenNominaUseCase — generado/pagado/pendiente sin confundir ejes de fecha', () {
    test('un pago aplicado en un mes distinto al periodo de la Nómina se refleja correctamente', () async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      // La Nómina es de enero, pero el pago real ocurre en febrero.
      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 2, 5),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );

      final resumen = await obtenerResumenNomina.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.nominas, hasLength(1));
      expect(resumen.nominas.single.totalGenerado, renglon.totalAPagar);
      expect(
        resumen.nominas.single.totalPagado,
        renglon.totalAPagar,
        reason: 'el pago se refleja aunque haya ocurrido en un mes de calendario distinto al periodo de la Nómina',
      );
      expect(resumen.nominas.single.saldoPendiente, 0);
    });

    test('pago parcial: saldo pendiente correcto y la bandera esPagoParcial se activa', () async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      final mitad = renglon.totalAPagar ~/ 2;

      await registrarPagoNomina.ejecutar(
        nominaId: generado.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: mitad)],
      );

      final resumen = await obtenerResumenNomina.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.nominas.single.totalPagado, mitad);
      expect(resumen.nominas.single.saldoPendiente, renglon.totalAPagar - mitad);
      expect(resumen.nominas.single.esPagoParcial, isTrue);
    });

    test('Nómina en borrador aparece pero nunca se confunde con una cerrada/pagada', () async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      expect(generado.nomina.estatus, 'borrador');

      final resumen = await obtenerResumenNomina.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.nominas, hasLength(1));
      expect(resumen.nominas.single.nomina.estatus, 'borrador');
      expect(resumen.nominas.single.totalPagado, 0);
    });

    test('histórico congelado: cerrar la Nómina, luego cambiar el sueldo administrativo del empleado, el reporte no cambia', () async {
      final empleado = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: 1000000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final resumenAntes = await obtenerResumenNomina.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      final generadoAntes = resumenAntes.nominas.single.totalGenerado;

      await empleadoRepo.corregir(
        empleadoId: empleado.id,
        cambios: const EmpleadoCompanion(sueldoMensualAdministrativo: Value(5000000)),
        motivo: 'Prueba de que no afecta el histórico',
      );

      final resumenDespues = await obtenerResumenNomina.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumenDespues.nominas.single.totalGenerado, generadoAntes, reason: 'el snapshot de NominaEmpleado nunca se recalcula');
    });

    test('periodo sin Nóminas: lista vacía, totales en cero, sin excepciones', () async {
      final resumen = await obtenerResumenNomina.ejecutar(rangoInicio: DateTime(2030, 1, 1), rangoFin: DateTime(2030, 1, 31));

      expect(resumen.nominas, isEmpty);
      expect(resumen.totalGeneradoGlobal, 0);
      expect(resumen.totalPagadoGlobal, 0);
      expect(resumen.totalPendienteGlobal, 0);
    });
  });
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
