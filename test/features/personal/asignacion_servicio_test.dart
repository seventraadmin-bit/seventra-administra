import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
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
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/asignacion_servicio_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_servicio_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_servicio_empleado_usecase.dart';
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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    const empleadoValidator = EmpleadoValidator();
    const asignacionValidator = AsignacionServicioValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarCodigo, empleadoValidator, servicioRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, empleadoValidator);
    asignarEmpleadoServicio = AsignarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, servicioRepo, asignacionValidator);
    cambiarServicioEmpleado = CambiarServicioEmpleadoUseCase(empleadoRepo, asignacionRepo, servicioRepo, asignacionValidator);
    retirarEmpleadoServicio = RetirarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, asignacionValidator);
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

  Future<ServicioData> crearServicioDePrueba({String nombre = 'Vigilancia Sportium Toluca', String? clienteId}) async {
    final cliente = clienteId ?? (await crearClienteDePrueba()).id;
    final resultado = await crearServicio.ejecutar(
      clienteId: cliente,
      borrador: ServicioBorrador(nombre: nombre, tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    return (resultado as GuardarServicioExitoso).servicio;
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
}
