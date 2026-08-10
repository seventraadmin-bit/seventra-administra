import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_sueldo_referencia_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/asignacion_servicio_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_servicio_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_sueldo_con_vigencia.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_servicio_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_vigencia_sueldo_asignacion_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/retirar_empleado_servicio_usecase.dart';

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
  late AsignarEmpleadoServicioUseCase asignarEmpleadoServicio;
  late CambiarServicioEmpleadoUseCase cambiarServicioEmpleado;
  late RetirarEmpleadoServicioUseCase retirarEmpleadoServicio;
  late GuardarSueldoReferenciaServicioUseCase guardarSueldoReferenciaServicio;
  late CambiarVigenciaSueldoAsignacionUseCase cambiarVigenciaSueldoAsignacion;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();
    const asignacionValidator = AsignacionServicioValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, empleadoValidator);
    asignarEmpleadoServicio = AsignarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, servicioRepo, asignacionValidator);
    cambiarServicioEmpleado = CambiarServicioEmpleadoUseCase(empleadoRepo, asignacionRepo, servicioRepo, asignacionValidator);
    retirarEmpleadoServicio = RetirarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, asignacionValidator);
    guardarSueldoReferenciaServicio = GuardarSueldoReferenciaServicioUseCase(servicioRepo, servicioValidator);
    cambiarVigenciaSueldoAsignacion = CambiarVigenciaSueldoAsignacionUseCase(asignacionRepo, asignacionValidator);
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleadoDePrueba({
    String nombres = 'Juan',
    String apellidoPaterno = 'Pérez',
    String curp = 'PEXJ900101HDFXXX01',
    String rfc = 'PEXJ900101AB1',
    String nss = '12345678901',
    DateTime? fechaIngreso,
  }) async {
    final resultado = await crearEmpleado.ejecutar(
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: curp,
      rfc: rfc,
      nss: nss,
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  var clienteContador = 0;
  Future<ClienteData> crearClienteDePrueba({String? codigo, String nombre = 'Sportium'}) {
    clienteContador++;
    return clienteRepo.crear(
      ClienteCompanion.insert(codigo: codigo ?? 'CLI-${clienteContador.toString().padLeft(6, '0')}', nombreComercial: nombre),
    );
  }

  /// Por defecto ya deja `sueldoMensualReferenciaPersonal`/
  /// `bonoMensualReferenciaPersonal` capturados (Etapa 6B) — para que
  /// las pruebas centradas en otro comportamiento no tengan que resolver
  /// la precarga de sueldo en cada caso. Pasar `sueldoMensualReferencia:
  /// null` explícitamente para probar el camino "sin referencia".
  Future<ServicioData> crearServicioDePrueba({
    String nombre = 'Vigilancia Sportium Toluca',
    String? clienteId,
    int? sueldoMensualReferencia = 1500000,
    int? bonoMensualReferencia = 0,
  }) async {
    final cliente = clienteId ?? (await crearClienteDePrueba()).id;
    final resultado = await crearServicio.ejecutar(
      clienteId: cliente,
      borrador: ServicioBorrador(nombre: nombre, tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    var servicio = (resultado as GuardarServicioExitoso).servicio;
    if (sueldoMensualReferencia != null || bonoMensualReferencia != null) {
      final guardado = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: sueldoMensualReferencia,
        bonoMensualReferenciaPersonal: bonoMensualReferencia,
      );
      servicio = (guardado as GuardarSueldoReferenciaServicioExitoso).servicio;
    }
    return servicio;
  }

  /// Activa un Servicio insertando su Dirección operativa directamente
  /// (mismo atajo que `servicio_test.dart` — el flujo real de captura de
  /// Dirección es de la Etapa 4F.2, fuera del alcance de esta prueba).
  Future<ServicioData> activarServicio(ServicioData servicio) async {
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
    final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
    return (resultado as CambiarEstatusServicioExitoso).servicio;
  }

  group('AsignarEmpleadoServicioUseCase', () {
    test('asigna un Empleado activo a un Servicio activo y registra el evento', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<AsignarEmpleadoServicioExitoso>());
      final asignacion = (resultado as AsignarEmpleadoServicioExitoso).asignacion;
      expect(asignacion.servicioId, servicio.id);
      expect(asignacion.fechaTermino, isNull);

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'asignacionServicio');
    });

    test('rechaza un Empleado que no está activo', () async {
      final empleado = await crearEmpleadoDePrueba();
      await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 1, 15), motivo: MotivoBajaEmpleado.renuncia);
      final servicio = await activarServicio(await crearServicioDePrueba());

      final resultado = await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 20));
      expect(resultado, isA<AsignarEmpleadoServicioEmpleadoNoActivo>());
    });

    test('rechaza un Servicio que no está activo (cotizado)', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final resultado = await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 2, 1));
      expect(resultado, isA<AsignarEmpleadoServicioServicioNoActivo>());
    });

    test('rechaza asignar cuando el Empleado ya tiene una asignación vigente', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicioA = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio A'));
      final servicioB = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio B'));

      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2026, 2, 1));
      final resultado = await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicioB.id, fechaInicio: DateTime(2026, 2, 5));

      expect(resultado, isA<AsignarEmpleadoServicioYaTieneAsignacionVigente>());
    });

    test('rechaza una fecha de inicio anterior al ingreso del Empleado', () async {
      final empleado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2026, 2, 1));
      final servicio = await activarServicio(await crearServicioDePrueba());

      final resultado = await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));
      expect(resultado, isA<AsignarEmpleadoServicioFechaInvalida>());
    });

    test('rechaza un índice único parcial: dos asignaciones vigentes para el mismo Empleado a nivel de BD', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicioA = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio A'));
      final servicioB = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio B'));

      await db.into(db.asignacionServicio).insert(
            AsignacionServicioCompanion.insert(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2026, 2, 1)),
          );

      expect(
        () => db.into(db.asignacionServicio).insert(
              AsignacionServicioCompanion.insert(empleadoId: empleado.id, servicioId: servicioB.id, fechaInicio: DateTime(2026, 2, 5)),
            ),
        throwsA(anything),
      );
    });
  });

  group('CambiarServicioEmpleadoUseCase', () {
    test('cierra la asignación anterior con motivo automático cambioServicio y crea la nueva', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicioA = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio A'));
      final servicioB = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio B'));
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await cambiarServicioEmpleado.ejecutar(empleadoId: empleado.id, nuevoServicioId: servicioB.id, fecha: DateTime(2026, 3, 15));

      expect(resultado, isA<CambiarServicioEmpleadoExitoso>());
      final nueva = (resultado as CambiarServicioEmpleadoExitoso).asignacion;
      expect(nueva.servicioId, servicioB.id);
      expect(nueva.fechaTermino, isNull);

      final historial = await asignacionRepo.listarPorEmpleado(empleado.id);
      expect(historial, hasLength(2));
      final cerrada = historial.firstWhere((a) => a.servicioId == servicioA.id);
      expect(cerrada.fechaTermino, DateTime(2026, 3, 15));
      expect(cerrada.motivoTermino, 'cambioServicio');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'cambioServicio');
    });

    test('rechaza cambiar de servicio cuando no hay asignación vigente', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());

      final resultado = await cambiarServicioEmpleado.ejecutar(empleadoId: empleado.id, nuevoServicioId: servicio.id, fecha: DateTime(2026, 2, 1));
      expect(resultado, isA<CambiarServicioEmpleadoNoTieneAsignacionVigente>());
    });

    test('rechaza cambiar al mismo Servicio', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await cambiarServicioEmpleado.ejecutar(empleadoId: empleado.id, nuevoServicioId: servicio.id, fecha: DateTime(2026, 2, 1));
      expect(resultado, isA<CambiarServicioEmpleadoMismoServicio>());
    });
  });

  group('RetirarEmpleadoServicioUseCase', () {
    test('retira al Empleado del Servicio vigente sin darlo de baja de la empresa', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await retirarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        fechaTermino: DateTime(2026, 3, 1),
        motivo: MotivoTerminoAsignacion.solicitudCliente,
      );

      expect(resultado, isA<RetirarEmpleadoServicioExitoso>());
      final actualizado = await empleadoRepo.obtenerPorId(empleado.id);
      expect(actualizado!.estatus, 'activo', reason: 'retirar de un Servicio nunca da de baja al Empleado');

      final activa = await asignacionRepo.obtenerActivaPorEmpleado(empleado.id);
      expect(activa, isNull);
    });

    test('exige observaciones cuando el motivo es "otro"', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await retirarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        fechaTermino: DateTime(2026, 3, 1),
        motivo: MotivoTerminoAsignacion.otro,
      );
      expect(resultado, isA<RetirarEmpleadoServicioObservacionesRequeridas>());
    });

    test('rechaza un motivo automático (no seleccionable manualmente)', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await retirarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        fechaTermino: DateTime(2026, 3, 1),
        motivo: MotivoTerminoAsignacion.cambioServicio,
      );
      expect(resultado, isA<RetirarEmpleadoServicioMotivoNoSeleccionable>());
    });

    test('rechaza retirar cuando no hay asignación vigente', () async {
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await retirarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        fechaTermino: DateTime(2026, 3, 1),
        motivo: MotivoTerminoAsignacion.solicitudCliente,
      );
      expect(resultado, isA<RetirarEmpleadoServicioNoTieneAsignacionVigente>());
    });
  });

  group('Baja laboral cierra la asignación vigente (Etapa 5C + 5D)', () {
    test('registrar la Baja laboral cierra automáticamente la asignación vigente con motivo bajaEmpleado', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 6, 15), motivo: MotivoBajaEmpleado.renuncia);

      final activa = await asignacionRepo.obtenerActivaPorEmpleado(empleado.id);
      expect(activa, isNull, reason: 'nunca debe quedar Empleado = Baja, Servicio = Todavía asignado');

      final historial = await asignacionRepo.listarPorEmpleado(empleado.id);
      expect(historial.single.motivoTermino, 'bajaEmpleado');
      expect(historial.single.fechaTermino, DateTime(2026, 6, 15), reason: 'misma fecha efectiva de la baja');
    });
  });

  group('Servicio terminado cierra todas las asignaciones vigentes (Etapa 5D)', () {
    test('terminar un Servicio cierra las asignaciones de todos los Empleados asignados', () async {
      final empleadoA = await crearEmpleadoDePrueba(curp: 'PEXJ900101HDFXXX01', rfc: 'PEXJ900101AB1', nss: '12345678901');
      final empleadoB = await crearEmpleadoDePrueba(nombres: 'Ana', curp: 'GAAA900101MDFXXX02', rfc: 'GAAA900101AB2', nss: '12345678902');
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleadoA.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleadoB.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 7, 1),
      );
      expect(resultado, isA<CambiarEstatusServicioExitoso>());

      for (final empleadoId in [empleadoA.id, empleadoB.id]) {
        final activa = await asignacionRepo.obtenerActivaPorEmpleado(empleadoId);
        expect(activa, isNull, reason: 'ningún Empleado debe seguir asignado a un Servicio terminado');
        final historial = await asignacionRepo.listarPorEmpleado(empleadoId);
        expect(historial.single.motivoTermino, 'servicioTerminado');
        expect(historial.single.fechaTermino, DateTime(2026, 7, 1));
      }
    });
  });

  group('Servicio suspendido conserva asignaciones vigentes pero bloquea nuevas (Etapa 5D)', () {
    test('suspender un Servicio no cierra la asignación existente, pero rechaza una nueva', () async {
      final empleadoA = await crearEmpleadoDePrueba(curp: 'PEXJ900101HDFXXX01', rfc: 'PEXJ900101AB1', nss: '12345678901');
      final empleadoB = await crearEmpleadoDePrueba(nombres: 'Ana', curp: 'GAAA900101MDFXXX02', rfc: 'GAAA900101AB2', nss: '12345678902');
      final servicio = await activarServicio(await crearServicioDePrueba());
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleadoA.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.suspendido);
      expect(resultado, isA<CambiarEstatusServicioExitoso>());

      final activa = await asignacionRepo.obtenerActivaPorEmpleado(empleadoA.id);
      expect(activa, isNotNull, reason: 'una suspensión puede ser temporal — la asignación existente se conserva');

      final nuevaAsignacion = await asignarEmpleadoServicio.ejecutar(empleadoId: empleadoB.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 4, 1));
      expect(nuevaAsignacion, isA<AsignarEmpleadoServicioServicioNoActivo>(), reason: 'solo se bloquean asignaciones nuevas');
    });
  });

  group('GuardarSueldoReferenciaServicioUseCase (Etapa 6B)', () {
    test('guarda, actualiza y limpia sueldo/bono de referencia', () async {
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: null, bonoMensualReferencia: null);

      final guardado = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: 1800000,
        bonoMensualReferenciaPersonal: 200000,
      );
      expect(guardado, isA<GuardarSueldoReferenciaServicioExitoso>());
      final actualizado = (guardado as GuardarSueldoReferenciaServicioExitoso).servicio;
      expect(actualizado.sueldoMensualReferenciaPersonal, 1800000);
      expect(actualizado.bonoMensualReferenciaPersonal, 200000);

      final limpiado = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: null,
        bonoMensualReferenciaPersonal: null,
      );
      final servicioLimpio = (limpiado as GuardarSueldoReferenciaServicioExitoso).servicio;
      expect(servicioLimpio.sueldoMensualReferenciaPersonal, isNull);
      expect(servicioLimpio.bonoMensualReferenciaPersonal, isNull);
    });

    test('rechaza sueldo <= 0 pero acepta bono = 0', () async {
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: null, bonoMensualReferencia: null);

      final conSueldoCero = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: 0,
        bonoMensualReferenciaPersonal: null,
      );
      expect(conSueldoCero, isA<GuardarSueldoReferenciaServicioSueldoInvalido>());

      final conBonoCero = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: 0,
      );
      expect(conBonoCero, isA<GuardarSueldoReferenciaServicioExitoso>());
    });

    test('rechaza bono negativo', () async {
      final servicio = await crearServicioDePrueba(sueldoMensualReferencia: null, bonoMensualReferencia: null);

      final resultado = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: -1,
      );
      expect(resultado, isA<GuardarSueldoReferenciaServicioBonoInvalido>());
    });

    test('rechaza un Servicio inexistente', () async {
      final resultado = await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: 'no-existe',
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: 0,
      );
      expect(resultado, isA<GuardarSueldoReferenciaServicioNoExiste>());
    });
  });

  group('Precarga de sueldo/bono al asignar (Etapa 6B)', () {
    test('AsignarEmpleadoServicioUseCase precarga sueldo/bono desde la referencia del Servicio', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: 1600000, bonoMensualReferencia: 300000),
      );

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
      );
      final asignacion = (resultado as AsignarEmpleadoServicioExitoso).asignacion;

      final vigencias = await asignacionRepo.listarHistorialSueldo(asignacion.id);
      expect(vigencias, hasLength(1));
      expect(vigencias.single.sueldoMensual, 1600000);
      expect(vigencias.single.bonoMensual, 300000);
      expect(vigencias.single.fechaInicioVigencia, DateTime(2026, 2, 1));
      expect(vigencias.single.fechaFinVigencia, isNull);
    });

    test('AsignarEmpleadoServicioUseCase acepta una excepción individual que sustituye la referencia', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: 1600000, bonoMensualReferencia: 300000),
      );

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        sueldoMensual: 2000000,
        bonoMensual: 0,
      );
      final asignacion = (resultado as AsignarEmpleadoServicioExitoso).asignacion;

      final vigencias = await asignacionRepo.listarHistorialSueldo(asignacion.id);
      expect(vigencias.single.sueldoMensual, 2000000, reason: 'la excepción individual sustituye la referencia del Servicio');
      expect(vigencias.single.bonoMensual, 0);
    });

    test('AsignarEmpleadoServicioUseCase rechaza cuando el Servicio no tiene referencia y no hay excepción', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: null, bonoMensualReferencia: null),
      );

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
      );
      expect(resultado, isA<AsignarEmpleadoServicioSueldoRequerido>());
    });

    test('AsignarEmpleadoServicioUseCase acepta bono = 0 cuando el Servicio no tiene bono de referencia', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: 1600000, bonoMensualReferencia: null),
      );

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
      );
      final asignacion = (resultado as AsignarEmpleadoServicioExitoso).asignacion;
      final vigencias = await asignacionRepo.listarHistorialSueldo(asignacion.id);
      expect(vigencias.single.bonoMensual, 0);
    });

    test('AsignarEmpleadoServicioUseCase rechaza una excepción de sueldo <= 0', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        sueldoMensual: 0,
      );
      expect(resultado, isA<AsignarEmpleadoServicioSueldoInvalido>());
    });

    test('AsignarEmpleadoServicioUseCase rechaza una excepción de bono negativo', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(await crearServicioDePrueba());

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        bonoMensual: -1,
      );
      expect(resultado, isA<AsignarEmpleadoServicioBonoInvalido>());
    });

    test('cambiar la referencia del Servicio después no modifica retroactivamente una asignación ya existente', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: 1600000, bonoMensualReferencia: 0),
      );

      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
      );
      final asignacion = (resultado as AsignarEmpleadoServicioExitoso).asignacion;

      await guardarSueldoReferenciaServicio.ejecutar(
        servicioId: servicio.id,
        sueldoMensualReferenciaPersonal: 5000000,
        bonoMensualReferenciaPersonal: 1000000,
      );

      final vigencias = await asignacionRepo.listarHistorialSueldo(asignacion.id);
      expect(vigencias.single.sueldoMensual, 1600000, reason: 'un cambio posterior en la referencia del Servicio nunca es retroactivo');
      expect(vigencias.single.bonoMensual, 0);
    });

    test('CambiarServicioEmpleadoUseCase precarga sueldo/bono desde la referencia del nuevo Servicio', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicioA = await activarServicio(
        await crearServicioDePrueba(nombre: 'Servicio A', sueldoMensualReferencia: 1500000, bonoMensualReferencia: 0),
      );
      final servicioB = await activarServicio(
        await crearServicioDePrueba(nombre: 'Servicio B', sueldoMensualReferencia: 2200000, bonoMensualReferencia: 400000),
      );
      final anterior = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicioA.id,
        fechaInicio: DateTime(2026, 1, 1),
      );
      final asignacionAnterior = (anterior as AsignarEmpleadoServicioExitoso).asignacion;

      final resultado = await cambiarServicioEmpleado.ejecutar(
        empleadoId: empleado.id,
        nuevoServicioId: servicioB.id,
        fecha: DateTime(2026, 3, 15),
      );
      final nueva = (resultado as CambiarServicioEmpleadoExitoso).asignacion;

      final vigenciasNueva = await asignacionRepo.listarHistorialSueldo(nueva.id);
      expect(vigenciasNueva.single.sueldoMensual, 2200000);
      expect(vigenciasNueva.single.bonoMensual, 400000);

      final vigenciasAnterior = await asignacionRepo.listarHistorialSueldo(asignacionAnterior.id);
      expect(vigenciasAnterior.single.sueldoMensual, 1500000, reason: 'la asignación anterior conserva su propio historial de sueldo');
    });

    test('CambiarServicioEmpleadoUseCase rechaza cuando el nuevo Servicio no tiene referencia y no hay excepción', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicioA = await activarServicio(await crearServicioDePrueba(nombre: 'Servicio A'));
      final servicioB = await activarServicio(
        await crearServicioDePrueba(nombre: 'Servicio B', sueldoMensualReferencia: null, bonoMensualReferencia: null),
      );
      await asignarEmpleadoServicio.ejecutar(empleadoId: empleado.id, servicioId: servicioA.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await cambiarServicioEmpleado.ejecutar(
        empleadoId: empleado.id,
        nuevoServicioId: servicioB.id,
        fecha: DateTime(2026, 3, 15),
      );
      expect(resultado, isA<CambiarServicioEmpleadoSueldoRequerido>());
    });

    test('CrearEmpleadoUseCase con adscripción a Servicio precarga sueldo/bono de la asignación inicial', () async {
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: 1700000, bonoMensualReferencia: 250000),
      );

      final resultado = await crearEmpleado.ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 2, 1),
        aniosExperienciaSeguridad: 3,
        servicioId: servicio.id,
      );
      final empleado = (resultado as CrearEmpleadoExitoso).empleado;

      final asignacion = await asignacionRepo.obtenerActivaPorEmpleado(empleado.id);
      final vigencias = await asignacionRepo.listarHistorialSueldo(asignacion!.id);
      expect(vigencias.single.sueldoMensual, 1700000);
      expect(vigencias.single.bonoMensual, 250000);
    });

    test('CrearEmpleadoUseCase rechaza cuando el Servicio de adscripción no tiene referencia y no hay excepción', () async {
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: null, bonoMensualReferencia: null),
      );

      final resultado = await crearEmpleado.ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 2, 1),
        aniosExperienciaSeguridad: 3,
        servicioId: servicio.id,
      );
      expect(resultado, isA<CrearEmpleadoSueldoAsignacionRequerido>());
    });
  });

  group('CambiarVigenciaSueldoAsignacionUseCase (Etapa 6B)', () {
    Future<AsignacionServicioData> crearAsignacionDePrueba({
      DateTime? fechaInicio,
      int sueldoMensual = 1500000,
      int bonoMensual = 0,
    }) async {
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await activarServicio(
        await crearServicioDePrueba(sueldoMensualReferencia: sueldoMensual, bonoMensualReferencia: bonoMensual),
      );
      final resultado = await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: fechaInicio ?? DateTime(2026, 2, 1),
      );
      return (resultado as AsignarEmpleadoServicioExitoso).asignacion;
    }

    test('registra una nueva vigencia efectiva hoy y cierra la anterior el día previo', () async {
      final asignacion = await crearAsignacionDePrueba();

      final resultado = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1800000,
        bonoMensual: 100000,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );
      expect(resultado, isA<CambiarVigenciaSueldoAsignacionExitoso>());

      final historial = await asignacionRepo.listarHistorialSueldo(asignacion.id);
      expect(historial, hasLength(2));
      final original = historial.firstWhere((v) => v.sueldoMensual == 1500000);
      final nueva = historial.firstWhere((v) => v.sueldoMensual == 1800000);
      expect(original.fechaFinVigencia, DateTime(2026, 5, 31));
      expect(nueva.fechaInicioVigencia, DateTime(2026, 6, 1));
      expect(nueva.fechaFinVigencia, isNull);
      expect(nueva.bonoMensual, 100000);
    });

    test('permite programar una vigencia futura sin sustituir la vigente de inmediato', () async {
      final asignacion = await crearAsignacionDePrueba();

      final resultado = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 2000000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2027, 1, 1),
      );
      expect(resultado, isA<CambiarVigenciaSueldoAsignacionExitoso>());

      // La predecesora sí se cierra un día antes del inicio de la
      // programada (evita solapamiento de rangos), pero eso no la
      // "sustituye" — sigue siendo la vigente HOY porque la fecha de
      // hoy cae dentro de su rango; la clasificación es por fecha, no
      // por si `fechaFinVigencia` es `null` (mismo criterio que
      // `clasificarVigencias` para línea comercial).
      final historial = await asignacionRepo.listarHistorialSueldo(asignacion.id);
      final original = historial.firstWhere((v) => v.sueldoMensual == 1500000);
      final programada = historial.firstWhere((v) => v.sueldoMensual == 2000000);
      expect(original.fechaFinVigencia, DateTime(2026, 12, 31));

      final activas = await asignacionRepo.listarVigenciasSueldoActivas(asignacion.id);
      final clasificacion = clasificarVigenciasSueldo(activas, DateTime(2026, 6, 1));
      expect(clasificacion.vigente?.id, original.id, reason: 'la vigente hoy sigue siendo la original, no la programada');
      expect(clasificacion.programadas.map((v) => v.id), contains(programada.id));
    });

    test('rechaza una fecha de inicio duplicada', () async {
      final asignacion = await crearAsignacionDePrueba();
      await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1800000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );

      final resultado = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1900000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );
      expect(resultado, isA<CambiarVigenciaSueldoAsignacionFechaDuplicada>());
    });

    test('rechaza una fecha anterior al inicio de la propia asignación', () async {
      final asignacion = await crearAsignacionDePrueba(fechaInicio: DateTime(2026, 2, 1));

      final resultado = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1800000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );
      expect(resultado, isA<CambiarVigenciaSueldoAsignacionFechaInvalida>());
    });

    test('rechaza sueldo <= 0 pero acepta bono = 0', () async {
      final asignacion = await crearAsignacionDePrueba();

      final conSueldoCero = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 0,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );
      expect(conSueldoCero, isA<CambiarVigenciaSueldoAsignacionSueldoInvalido>());

      final conBonoCero = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1800000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );
      expect(conBonoCero, isA<CambiarVigenciaSueldoAsignacionExitoso>());
    });

    test('rechaza bono negativo', () async {
      final asignacion = await crearAsignacionDePrueba();

      final resultado = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: asignacion.id,
        sueldoMensual: 1800000,
        bonoMensual: -1,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );
      expect(resultado, isA<CambiarVigenciaSueldoAsignacionBonoInvalido>());
    });

    test('rechaza una asignación inexistente', () async {
      final resultado = await cambiarVigenciaSueldoAsignacion.ejecutar(
        asignacionServicioId: 'no-existe',
        sueldoMensual: 1800000,
        bonoMensual: 0,
        fechaInicioVigencia: DateTime(2026, 6, 1),
      );
      expect(resultado, isA<CambiarVigenciaSueldoAsignacionNoExiste>());
    });
  });
}
