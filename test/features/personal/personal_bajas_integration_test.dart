// Etapa 15 — rediseño de Personal/Bajas. Cubre de punta a punta (BD
// real): el snapshot de baja (puesto/servicio/turno) se captura en el
// momento exacto de `RegistrarBajaLaboralUseCase`, sobrevive intacto
// aunque el Empleado reingrese y cambie de Servicio, la baja cierra la
// asignación vigente (comportamiento ya existente, confirmado sin
// regresión), y `construirEventosBaja` nunca atribuye un evento
// archivado al Servicio ACTUAL del Empleado — solo al snapshot de ESE
// periodo.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_servicio_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_reingreso_usecase.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late ServicioRepositoryImpl servicioRepo;
  late AsignacionServicioRepositoryImpl asignacionRepo;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late PuestoRepositoryImpl puestoRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late CrearServicioUseCase crearServicio;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late RegistrarBajaLaboralUseCase registrarBajaLaboral;
  late RegistrarReingresoUseCase registrarReingreso;
  late AsignarEmpleadoServicioUseCase asignarEmpleadoServicio;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    clienteRepo = ClienteRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();
    const asignacionValidator = AsignacionServicioValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo, comercialRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, empleadoValidator, AsignacionRepositoryImpl(db), AsignacionVehiculoRepositoryImpl(db));
    registrarReingreso = RegistrarReingresoUseCase(empleadoRepo, empleadoValidator);
    asignarEmpleadoServicio =
        AsignarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, servicioRepo, comercialRepo, asignacionValidator);
  });

  tearDown(() => db.close());

  var empleadoContador = 0;
  Future<EmpleadoData> crearEmpleadoDePrueba({DateTime? fechaIngreso}) async {
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
      fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  var clienteContador = 0;
  var puestoContador = 0;
  final lineaComercialPorServicio = <String, String>{};

  Future<ServicioData> crearServicioDePrueba(String nombre) async {
    clienteContador++;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${clienteContador.toString().padLeft(6, '0')}', nombreComercial: nombre),
    );
    final resultado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: nombre, tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    final servicio = (resultado as GuardarServicioExitoso).servicio;

    puestoContador++;
    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-${puestoContador.toString().padLeft(6, '0')}',
        nombre: 'Elemento Operativo $puestoContador',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final linea = await comercialRepo.crearLinea(
      servicioId: servicio.id,
      datos: LineaComercialValidada(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 10,
        precioUnitario: 100000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: 0,
      ),
    );
    lineaComercialPorServicio[servicio.id] = linea.linea.id;

    await db.into(db.direccion).insert(
          DireccionCompanion.insert(
            servicioId: Value(servicio.id),
            tipoDireccion: TipoDireccion.operativa.name,
            calle: 'Av. Toluca',
            numeroExterior: '50',
            colonia: 'Centro',
            municipioAlcaldia: 'Toluca',
            estado: 'Estado de México',
            codigoPostal: '50000',
          ),
        );
    final activado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo, motivo: 'Motivo de prueba');
    return (activado as CambiarEstatusServicioExitoso).servicio;
  }

  test('la baja captura el snapshot exacto de servicio/turno vigentes al momento de darse de baja', () async {
    final empleado = await crearEmpleadoDePrueba();
    final servicio = await crearServicioDePrueba('Morgan Atlacomulco');
    final asignacionResultado = await asignarEmpleadoServicio.ejecutar(
      empleadoId: empleado.id,
      servicioId: servicio.id,
      fechaInicio: DateTime(2026, 1, 1),
      turnoId: SeedIds.modalidadTurno24x24,
      lineaComercialId: lineaComercialPorServicio[servicio.id],
    );
    expect(asignacionResultado, isA<AsignarEmpleadoServicioExitoso>(), reason: asignacionResultado.runtimeType.toString());

    final resultado = await registrarBajaLaboral.ejecutar(
      empleadoId: empleado.id,
      fechaBaja: DateTime(2026, 6, 1),
      motivo: MotivoBajaEmpleado.renuncia,
    );
    final actualizado = (resultado as RegistrarBajaLaboralExitoso).empleado;

    expect(actualizado.servicioNombreBaja, 'Morgan Atlacomulco');
    expect(actualizado.turnoNombreBaja, isNotNull);
    expect(actualizado.estatus, 'baja');

    // La asignación de Servicio se cierra en la misma operación
    // (comportamiento ya existente, confirmado sin regresión).
    final asignacionVigente = await asignacionRepo.obtenerActivaPorEmpleado(empleado.id);
    expect(asignacionVigente, isNull);
  });

  test('un Empleado administrativo (sin AsignacionServicio) al darse de baja queda con servicio/turno NULL — nunca inventados', () async {
    final empleado = await crearEmpleadoDePrueba();
    final resultado = await registrarBajaLaboral.ejecutar(
      empleadoId: empleado.id,
      fechaBaja: DateTime(2026, 6, 1),
      motivo: MotivoBajaEmpleado.finContrato,
    );
    final actualizado = (resultado as RegistrarBajaLaboralExitoso).empleado;

    expect(actualizado.servicioNombreBaja, isNull);
    expect(actualizado.turnoNombreBaja, isNull);
  });

  test('reingreso conserva la baja anterior íntegra (con su snapshot) y NUNCA acumula antigüedad entre periodos', () async {
    final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
    final servicioA = await crearServicioDePrueba('Morgan Atlacomulco');
    await asignarEmpleadoServicio.ejecutar(
      empleadoId: empleado.id,
      servicioId: servicioA.id,
      fechaInicio: DateTime(2025, 1, 1),
      lineaComercialId: lineaComercialPorServicio[servicioA.id],
    );
    await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2025, 6, 1), motivo: MotivoBajaEmpleado.renuncia);

    final reingreso = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 1, 1));
    expect(reingreso, isA<RegistrarReingresoExitoso>());

    final periodos = await empleadoRepo.listarPeriodosLaboralesArchivados(empleado.id);
    expect(periodos, hasLength(1));
    expect(periodos.single.motivoBaja, 'renuncia');
    expect(periodos.single.servicioNombre, 'Morgan Atlacomulco', reason: 'el snapshot de la baja se copia intacto al archivar');

    final activo = await empleadoRepo.obtenerPorId(empleado.id);
    expect(activo!.estatus, 'activo');
    expect(activo.fechaIngreso, DateTime(2026, 1, 1), reason: 'nueva fecha de ingreso — nunca se conserva la anterior');
    expect(activo.servicioNombreBaja, isNull, reason: 'el bloque de snapshot de baja se limpia al reingresar');
  });

  test('segunda baja tras reingreso a un Servicio DISTINTO genera un evento independiente con SU PROPIO snapshot — '
      'nunca atribuido al Servicio actual/anterior del Empleado', () async {
    final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
    final servicioA = await crearServicioDePrueba('Morgan Atlacomulco');
    await asignarEmpleadoServicio.ejecutar(
      empleadoId: empleado.id,
      servicioId: servicioA.id,
      fechaInicio: DateTime(2025, 1, 1),
      lineaComercialId: lineaComercialPorServicio[servicioA.id],
    );
    await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2025, 6, 1), motivo: MotivoBajaEmpleado.renuncia);
    await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 1, 1));

    final servicioB = await crearServicioDePrueba('Sportium Satélite');
    await asignarEmpleadoServicio.ejecutar(
      empleadoId: empleado.id,
      servicioId: servicioB.id,
      fechaInicio: DateTime(2026, 1, 1),
      lineaComercialId: lineaComercialPorServicio[servicioB.id],
    );
    await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 8, 1), motivo: MotivoBajaEmpleado.inasistencias);

    final todosLosEmpleados = await empleadoRepo.listar();
    final periodosPorEmpleado = await empleadoRepo.listarPeriodosLaboralesArchivadosPorEmpleados([empleado.id]);
    final eventos = construirEventosBaja(todosLosEmpleados.where((e) => e.id == empleado.id).toList(), periodosPorEmpleado);

    expect(eventos, hasLength(2), reason: 'dos periodos laborales terminados = dos eventos, nunca uno');
    final eventoArchivado = eventos.firstWhere((e) => !e.esBajaVigente);
    final eventoVigente = eventos.firstWhere((e) => e.esBajaVigente);
    expect(eventoArchivado.servicioNombre, 'Morgan Atlacomulco');
    expect(eventoVigente.servicioNombre, 'Sportium Satélite');
    expect(eventoArchivado.motivoBaja, 'renuncia');
    expect(eventoVigente.motivoBaja, 'inasistencias');
  });

  test('un Empleado activo SIN AsignacionServicio no aparece en listarTodasActivas — señal real de "Sin asignar"', () async {
    final conServicio = await crearEmpleadoDePrueba();
    final sinServicio = await crearEmpleadoDePrueba();
    final servicio = await crearServicioDePrueba('Morgan Atlacomulco');
    await asignarEmpleadoServicio.ejecutar(
      empleadoId: conServicio.id,
      servicioId: servicio.id,
      fechaInicio: DateTime(2026, 1, 1),
      lineaComercialId: lineaComercialPorServicio[servicio.id],
    );

    final activas = await asignacionRepo.listarTodasActivas();
    final empleadosConAsignacion = activas.map((a) => a.empleadoId).toSet();

    expect(empleadosConAsignacion.contains(conServicio.id), isTrue);
    expect(empleadosConAsignacion.contains(sinServicio.id), isFalse);
  });

  test('MUY IMPORTANTE: renombrar el Servicio DESPUÉS de la baja no altera el snapshot histórico ya capturado', () async {
    final empleado = await crearEmpleadoDePrueba();
    final servicio = await crearServicioDePrueba('Morgan Atlacomulco');
    await asignarEmpleadoServicio.ejecutar(
      empleadoId: empleado.id,
      servicioId: servicio.id,
      fechaInicio: DateTime(2026, 1, 1),
      lineaComercialId: lineaComercialPorServicio[servicio.id],
    );
    await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 6, 1), motivo: MotivoBajaEmpleado.renuncia);

    await servicioRepo.actualizar(id: servicio.id, cambios: const ServicioCompanion(nombre: Value('Nombre Renombrado Después')));

    final actualizado = await empleadoRepo.obtenerPorId(empleado.id);
    expect(actualizado!.servicioNombreBaja, 'Morgan Atlacomulco', reason: 'el snapshot es inmutable frente a cambios posteriores del Servicio real');
  });

  test('un Empleado dado de baja desaparece de listar(estatus: activo) de inmediato', () async {
    final empleado = await crearEmpleadoDePrueba();
    expect((await empleadoRepo.listar(estatus: 'activo')).map((e) => e.id), contains(empleado.id));

    await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 6, 1), motivo: MotivoBajaEmpleado.renuncia);

    expect((await empleadoRepo.listar(estatus: 'activo')).map((e) => e.id), isNot(contains(empleado.id)));
  });
}
