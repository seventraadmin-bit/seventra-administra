import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_distribucion_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_movimientos_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/calcular_periodo_nomina.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
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
import 'package:riseg_one/features/personal/domain/usecases/cambiar_servicio_empleado_usecase.dart';
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
  late CrearEmpleadoUseCase crearEmpleado;
  late CrearServicioUseCase crearServicio;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late RegistrarBajaLaboralUseCase registrarBajaLaboral;
  late RegistrarReingresoUseCase registrarReingreso;
  late AsignarEmpleadoServicioUseCase asignarEmpleadoServicio;
  late CambiarServicioEmpleadoUseCase cambiarServicioEmpleado;
  late ServicioComercialRepositoryImpl comercialRepo;
  late PuestoRepositoryImpl puestoRepo;

  late GenerarNominaUseCase generarNomina;
  late ActualizarNominaDesdePersonalUseCase actualizarDesdePersonal;
  late ActualizarMovimientosNominaUseCase actualizarMovimientos;
  late ActualizarDistribucionNominaUseCase actualizarDistribucion;
  late CerrarNominaUseCase cerrarNomina;
  late NominaRepositoryImpl nominaRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();
    const asignacionValidator = AsignacionServicioValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo, comercialRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, empleadoValidator);
    registrarReingreso = RegistrarReingresoUseCase(empleadoRepo, empleadoValidator);
    asignarEmpleadoServicio =
        AsignarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, servicioRepo, comercialRepo, asignacionValidator);
    cambiarServicioEmpleado =
        CambiarServicioEmpleadoUseCase(empleadoRepo, asignacionRepo, servicioRepo, comercialRepo, asignacionValidator);

    nominaRepo = NominaRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    actualizarDesdePersonal = ActualizarNominaDesdePersonalUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo);
    actualizarMovimientos = ActualizarMovimientosNominaUseCase(nominaRepo);
    actualizarDistribucion = ActualizarDistribucionNominaUseCase(nominaRepo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);
  });

  tearDown(() => db.close());

  var empleadoContador = 0;

  Future<EmpleadoData> crearEmpleadoDePrueba({
    String? nombres,
    DateTime? fechaIngreso,
    int? sueldoMensualAdministrativo,
    int? bonoMensualAdministrativo,
  }) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: nombres ?? 'Empleado$n',
      apellidoPaterno: 'Apellido$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900101HDFXXX$n',
      rfc: 'PEXJ900101$n',
      nss: '100000000$n',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: sueldoMensualAdministrativo,
      bonoMensualAdministrativo: bonoMensualAdministrativo,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  var clienteContador = 0;
  Future<ClienteData> crearClienteDePrueba() {
    clienteContador++;
    return clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${clienteContador.toString().padLeft(6, '0')}', nombreComercial: 'Cliente $clienteContador'),
    );
  }

  // A qué línea comercial pertenece cada Servicio de prueba (Etapa 15,
  // rediseño de "Condiciones de Personal") — el sueldo/bono de
  // referencia ya no vive en `Servicio`, así que `asignar`/`cambiar`
  // (abajo) la consultan aquí para seguir precargando automáticamente,
  // sin tener que tocar cada llamada de este archivo una por una.
  final lineaComercialPorServicio = <String, String>{};
  var puestoContador = 0;

  Future<ServicioData> crearServicioDePrueba({String nombre = 'Servicio', int sueldoMensualReferencia = 1500000}) async {
    final cliente = await crearClienteDePrueba();
    final resultado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: nombre, tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2024, 1, 1)),
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
    // Cantidad generosa — a estas pruebas de Nómina no les importa la
    // capacidad del perfil, solo su sueldo/bono de referencia.
    final linea = await comercialRepo.crearLinea(
      servicioId: servicio.id,
      datos: LineaComercialValidada(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 50,
        precioUnitario: 100000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2024, 1, 1),
        sueldoMensualReferenciaPersonal: sueldoMensualReferencia,
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
    final activado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
    return (activado as CambiarEstatusServicioExitoso).servicio;
  }

  // Envuelven `AsignarEmpleadoServicioUseCase`/`CambiarServicioEmpleadoUseCase`
  // inyectando automáticamente `lineaComercialId` (Etapa 15) desde
  // `lineaComercialPorServicio` — todas las pruebas de este archivo ya
  // pasan por `crearServicioDePrueba`, así que ninguna necesita elegir
  // la línea a mano; conservan el resto de los parámetros sin cambio.
  Future<AsignarEmpleadoServicioResultado> asignar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    int? sueldoMensual,
    int? bonoMensual,
  }) {
    return asignarEmpleadoServicio.ejecutar(
      empleadoId: empleadoId,
      servicioId: servicioId,
      fechaInicio: fechaInicio,
      lineaComercialId: lineaComercialPorServicio[servicioId],
      sueldoMensual: sueldoMensual,
      bonoMensual: bonoMensual,
    );
  }

  Future<CambiarServicioEmpleadoResultado> cambiar({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
  }) {
    return cambiarServicioEmpleado.ejecutar(
      empleadoId: empleadoId,
      nuevoServicioId: nuevoServicioId,
      fecha: fecha,
      lineaComercialId: lineaComercialPorServicio[nuevoServicioId],
    );
  }

  group('GenerarNominaUseCase', () {
    test('cobertura laboral completa en un Servicio: 15 días pagables, bono en \$0 en la primera quincena', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: 1500000);
      await asignar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2025, 6, 1));

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      expect(resultado, isA<GenerarNominaExitoso>());
      final exitoso = resultado as GenerarNominaExitoso;
      expect(exitoso.empleadosIncluidos, 1);
      expect(exitoso.empleadosExcluidos, isEmpty);

      final renglones = await nominaRepo.listarEmpleados(exitoso.nomina.id);
      expect(renglones, hasLength(1));
      final renglon = renglones.single;
      expect(renglon.diasPagables, 15);
      expect(renglon.importeBase, 750000, reason: 'sueldo/2 con un único tramo');
      expect(renglon.bono, 0, reason: 'la primera quincena nunca propone bono automáticamente');
      expect(renglon.montoFiscal, renglon.totalAPagar, reason: 'Fiscal/No fiscal por defecto: todo a Fiscal');
      expect(renglon.montoNoFiscal, 0);
      expect(renglon.montoFiscal + renglon.montoNoFiscal, renglon.totalAPagar);

      final tramos = await nominaRepo.listarTramos(renglon.id);
      expect(tramos, hasLength(1));
    });

    test('la segunda quincena sí propone bono automáticamente desde el bono de referencia del Servicio', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: 1500000);
      await asignar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2025, 6, 1),
        bonoMensual: 50000,
      );

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.segunda);

      final exitoso = resultado as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(exitoso.nomina.id)).single;
      expect(renglon.bono, 50000);
      expect(renglon.bonoModificadoManualmente, isFalse);
    });

    test(
      'cambio de Servicio a mitad de una segunda quincena de 31 días nunca excede el equivalente de 15 días '
      '(regresión del bug real detectado por Marlon, verificado a nivel de base de datos)',
      () async {
        final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
        final servicioA = await crearServicioDePrueba(nombre: 'Servicio A', sueldoMensualReferencia: 2000000);
        final servicioB = await crearServicioDePrueba(nombre: 'Servicio B', sueldoMensualReferencia: 3000000);
        await asignar(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2025, 6, 1));
        await cambiar(empleadoId: empleado.id, nuevoServicioId: servicioB.id, fecha: DateTime(2026, 1, 24));

        // Enero 2026 tiene 31 días — la segunda quincena (16 al 31) tiene
        // 16 días reales, pero debe pagarse como si fueran 15.
        final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.segunda);

        final exitoso = resultado as GenerarNominaExitoso;
        final renglon = (await nominaRepo.listarEmpleados(exitoso.nomina.id)).single;
        expect(renglon.diasPagables, 15);
        expect(renglon.importeBase, lessThan(1500000), reason: 'nunca debe superar sueldoB/2 (el mayor de los dos)');

        final tramos = await nominaRepo.listarTramos(renglon.id);
        expect(tramos, hasLength(2));
      },
    );

    test('un Empleado dado de baja a mitad de la quincena sigue incluido, con días parciales (nunca desaparece dinero pendiente)', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: 1500000);
      await asignar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2025, 6, 1));
      await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 1, 10), motivo: MotivoBajaEmpleado.renuncia);

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      final exitoso = resultado as GenerarNominaExitoso;
      expect(exitoso.empleadosIncluidos, 1, reason: 'una baja nunca excluye a un Empleado con días pagables reales');
      final renglon = (await nominaRepo.listarEmpleados(exitoso.nomina.id)).single;
      expect(renglon.diasPagables, 10, reason: 'del 1 al 10 de enero, cobertura parcial');
      expect(renglon.importeBase, (1500000 * 10 / 30).round());
    });

    test('un reingreso dentro de la misma quincena produce dos tramos (dos segmentos laborales)', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2026, 1, 1));
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: 1500000);
      await asignar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));
      final bajaResultado =
          await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 1, 5), motivo: MotivoBajaEmpleado.renuncia);
      expect(bajaResultado, isA<RegistrarBajaLaboralExitoso>(), reason: bajaResultado.runtimeType.toString());
      final reingresoResultado = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 1, 10));
      expect(reingresoResultado, isA<RegistrarReingresoExitoso>(), reason: reingresoResultado.runtimeType.toString());
      // Una baja retira automáticamente al Empleado del Servicio (cierra la
      // AsignacionServicio) — el reingreso no reasigna por sí solo, hace
      // falta una nueva asignación para cubrir el segundo segmento laboral.
      await asignar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 10));

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      final exitoso = resultado as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(exitoso.nomina.id)).single;
      // Días 1-5 (5) + días 10-15 (6) = 11 días pagables, cobertura parcial.
      expect(renglon.diasPagables, 11);
      final tramos = await nominaRepo.listarTramos(renglon.id);
      expect(tramos, hasLength(2));
    });

    test('un Empleado administrativo sin AsignacionServicio usa el sueldo/bono administrativo de Empleado', () async {
      final empleado = await crearEmpleadoDePrueba(
        fechaIngreso: DateTime(2025, 1, 1),
        sueldoMensualAdministrativo: 1800000,
        bonoMensualAdministrativo: 20000,
      );

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.segunda);

      final exitoso = resultado as GenerarNominaExitoso;
      expect(exitoso.empleadosIncluidos, 1);
      final renglon = (await nominaRepo.listarEmpleados(exitoso.nomina.id)).single;
      expect(renglon.fuenteSueldoUtilizada, 'administrativo');
      expect(renglon.diasPagables, 15);
      expect(renglon.importeBase, 900000);
      expect(renglon.bono, 20000, reason: 'segunda quincena sí propone bono, también para administrativos');
      expect(empleado.id, renglon.empleadoId);
    });

    test('un Empleado sin ninguna fuente de sueldo configurada se excluye con motivo, nunca con importe en \$0', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));

      final resultado = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      expect(resultado, isA<GenerarNominaSinEmpleados>(), reason: 'el único candidato quedó excluido, no hay ninguno con importe válido');
    });

    test('una segunda generación para el mismo periodo se rechaza: una sola Nómina por periodo', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      final segunda = await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);
      expect(segunda, isA<GenerarNominaYaExiste>());
    });
  });

  group('ActualizarMovimientosNominaUseCase', () {
    test('faltas descuentan del total sin afectar diasPagables (independientes, nunca lo reducen)', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      final totalOriginal = renglon.totalAPagar;
      final diasOriginales = renglon.diasPagables;

      final resultado = await actualizarMovimientos.ejecutar(nominaEmpleadoId: renglon.id, faltas: 2);

      expect(resultado, isA<ActualizarMovimientosNominaExitoso>());
      final actualizado = (resultado as ActualizarMovimientosNominaExitoso).renglon;
      expect(actualizado.diasPagables, diasOriginales, reason: 'una falta nunca reduce los días pagables');
      expect(actualizado.descuentoPorFaltas, 2 * actualizado.pagoPorDia);
      expect(actualizado.totalAPagar, totalOriginal - actualizado.descuentoPorFaltas);
    });

    test('editar el bono a mano marca bonoModificadoManualmente', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      final resultado = await actualizarMovimientos.ejecutar(nominaEmpleadoId: renglon.id, bono: 30000);

      final actualizado = (resultado as ActualizarMovimientosNominaExitoso).renglon;
      expect(actualizado.bono, 30000);
      expect(actualizado.bonoModificadoManualmente, isTrue);
    });
  });

  group('ActualizarDistribucionNominaUseCase', () {
    test('acepta una distribución Fiscal/No fiscal que sí balancea y limpia distribucionPendienteRevision', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      final mitad = renglon.totalAPagar ~/ 2;
      final resultado = await actualizarDistribucion.ejecutar(
        nominaEmpleadoId: renglon.id,
        montoFiscal: mitad,
        montoNoFiscal: renglon.totalAPagar - mitad,
      );

      expect(resultado, isA<ActualizarDistribucionNominaExitoso>());
      final actualizado = (resultado as ActualizarDistribucionNominaExitoso).renglon;
      expect(actualizado.distribucionModificadaManualmente, isTrue);
      expect(actualizado.distribucionPendienteRevision, isFalse);
    });

    test('rechaza una distribución que no suma el total a pagar', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglon = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;

      final resultado = await actualizarDistribucion.ejecutar(nominaEmpleadoId: renglon.id, montoFiscal: 1, montoNoFiscal: 1);
      expect(resultado, isA<ActualizarDistribucionNominaNoBalancea>());
    });
  });

  group('ActualizarNominaDesdePersonalUseCase', () {
    test('un cambio de Servicio recalcula el importe pero conserva préstamo/faltas/observaciones capturados a mano', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
      final servicioA = await crearServicioDePrueba(nombre: 'Servicio A', sueldoMensualReferencia: 1500000);
      final servicioB = await crearServicioDePrueba(nombre: 'Servicio B', sueldoMensualReferencia: 2000000);
      await asignar(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2025, 6, 1));

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonOriginal = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      await actualizarMovimientos.ejecutar(nominaEmpleadoId: renglonOriginal.id, prestamo: 50000, faltas: 1, observaciones: 'nota de prueba');

      // Un día antes del periodo, para que todo el periodo quede limpiamente
      // del lado de Servicio B (cambiar justo el día 1 dejaría ese día
      // todavía traslapado con el cierre de la asignación anterior).
      await cambiar(empleadoId: empleado.id, nuevoServicioId: servicioB.id, fecha: DateTime(2025, 12, 31));

      final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
      expect(resultado, isA<ActualizarNominaDesdePersonalExitoso>());
      final exitoso = resultado as ActualizarNominaDesdePersonalExitoso;
      expect(exitoso.renglonesActualizados, 1);
      expect(exitoso.renglonesNuevos, 0);

      final renglonActualizado = await nominaRepo.obtenerEmpleado(renglonOriginal.id) ??
          (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      expect(renglonActualizado.importeBase, 1000000, reason: 'ahora usa el sueldo de Servicio B (2,000,000/2)');
      expect(renglonActualizado.prestamo, 50000, reason: 'un movimiento manual nunca se pierde al actualizar desde Personal');
      expect(renglonActualizado.faltas, 1);
      expect(renglonActualizado.observaciones, 'nota de prueba');
    });

    test('una nueva alta con fuente de sueldo válida aparece como renglón nuevo al actualizar', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      expect(await nominaRepo.listarEmpleados(generado.nomina.id), hasLength(1));

      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2026, 1, 1), sueldoMensualAdministrativo: 1600000);

      final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
      final exitoso = resultado as ActualizarNominaDesdePersonalExitoso;
      expect(exitoso.renglonesNuevos, 1);
      expect(await nominaRepo.listarEmpleados(generado.nomina.id), hasLength(2));
    });

    test('un renglón que pierde todos sus días pagables se elimina si nunca tuvo movimientos manuales', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      expect(await nominaRepo.listarEmpleados(generado.nomina.id), hasLength(1));

      await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 1, 20), motivo: MotivoBajaEmpleado.renuncia);

      final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
      final exitoso = resultado as ActualizarNominaDesdePersonalExitoso;
      expect(exitoso.renglonesEliminados, 1);
      expect(await nominaRepo.listarEmpleados(generado.nomina.id), isEmpty);
    });

    test(
      'un renglón que pierde todos sus días pagables pero tiene movimientos manuales capturados se conserva tal '
      'cual (nunca desaparece un dato ya capturado en silencio)',
      () async {
        final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
        final generado = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
        final renglonOriginal = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
        await actualizarMovimientos.ejecutar(nominaEmpleadoId: renglonOriginal.id, prestamo: 20000);

        await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 1, 20), motivo: MotivoBajaEmpleado.renuncia);

        final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
        final exitoso = resultado as ActualizarNominaDesdePersonalExitoso;
        expect(exitoso.renglonesConservadosSinDias, 1);
        expect(exitoso.renglonesEliminados, 0);

        final renglones = await nominaRepo.listarEmpleados(generado.nomina.id);
        expect(renglones, hasLength(1));
        expect(renglones.single.prestamo, 20000);
      },
    );

    test('una Nómina Cerrada rechaza la actualización desde Personal (snapshot histórico congelado)', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      final resultado = await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);
      expect(resultado, isA<ActualizarNominaDesdePersonalNominaCerrada>());
    });
  });

  group('CerrarNominaUseCase', () {
    test('cierra una Nómina en Borrador y congela el estatus', () async {
      await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;

      final resultado = await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      expect(resultado, isA<CerrarNominaExitoso>());
      final cerrada = (resultado as CerrarNominaExitoso).nomina;
      expect(cerrada.estatus, 'cerrada');
      expect(cerrada.fechaCierre, isNotNull);
    });

    test('bloquea el cierre cuando algún renglón tiene distribución Fiscal/No fiscal pendiente de revisar', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1));
      final servicioA = await crearServicioDePrueba(nombre: 'Servicio A', sueldoMensualReferencia: 1500000);
      final servicioB = await crearServicioDePrueba(nombre: 'Servicio B', sueldoMensualReferencia: 2000000);
      await asignar(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2025, 6, 1));

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonOriginal = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
      // Distribución capturada a mano contra el total original.
      await actualizarDistribucion.ejecutar(
        nominaEmpleadoId: renglonOriginal.id,
        montoFiscal: renglonOriginal.totalAPagar,
        montoNoFiscal: 0,
      );

      // El total cambia (nuevo Servicio con sueldo distinto) sin que el
      // usuario haya vuelto a resolver la distribución.
      await cambiar(empleadoId: empleado.id, nuevoServicioId: servicioB.id, fecha: DateTime(2026, 1, 1));
      await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);

      final resultado = await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
      expect(resultado, isA<CerrarNominaDistribucionPendiente>());
      expect((resultado as CerrarNominaDistribucionPendiente).renglonesPendientes, hasLength(1));

      final nominaTrasIntento = await nominaRepo.obtenerPorId(generado.nomina.id);
      expect(nominaTrasIntento!.estatus, 'borrador', reason: 'nunca se cierra en silencio con una distribución pendiente');
    });

    test('rechaza cerrar una Nómina sin renglones', () async {
      final periodo = calcularPeriodoNomina(anio: 2099, mes: 1, tipo: TipoPeriodoNomina.primera);
      final nomina = await nominaRepo.generar(folio: 'NOM-000099', periodo: periodo, filas: const []);

      final resultado = await cerrarNomina.ejecutar(nominaId: nomina.id);
      expect(resultado, isA<CerrarNominaSinEmpleados>());
    });

    test(
      'bloquea el cierre cuando un renglón se quedó sin días pagables pero conserva movimientos manuales '
      '(Resolución explícita de Marlon: nunca queda solo implícito en diasPagables == 0)',
      () async {
        final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2025, 1, 1), sueldoMensualAdministrativo: 1500000);
        final generado = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
        final renglonOriginal = (await nominaRepo.listarEmpleados(generado.nomina.id)).single;
        await actualizarMovimientos.ejecutar(nominaEmpleadoId: renglonOriginal.id, prestamo: 20000);

        await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 1, 20), motivo: MotivoBajaEmpleado.renuncia);
        await actualizarDesdePersonal.ejecutar(nominaId: generado.nomina.id);

        final resultado = await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
        expect(resultado, isA<CerrarNominaRequiereRevision>());
        expect((resultado as CerrarNominaRequiereRevision).renglonesPendientes, hasLength(1));

        final nominaTrasIntento = await nominaRepo.obtenerPorId(generado.nomina.id);
        expect(nominaTrasIntento!.estatus, 'borrador', reason: 'nunca se cierra en silencio con un renglón que requiere revisión');
      },
    );
  });
}
