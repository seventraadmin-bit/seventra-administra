import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_state.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String servicioId;
  late String clienteId;
  late ClienteRepositoryImpl clienteRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db);
    final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, validator);

    final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (creado as GuardarServicioExitoso).servicio.id;

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(servicioExpedienteControllerProvider(servicioId), (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCargaInicial() async {
    while (container.read(servicioExpedienteControllerProvider(servicioId)).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial resuelve el Servicio creado, sin Dirección operativa', () async {
    await esperarCargaInicial();
    final state = container.read(servicioExpedienteControllerProvider(servicioId));

    expect(state.cargando, isFalse);
    expect(state.errorCarga, isNull);
    expect(state.datos?.servicio.nombre, 'Vigilancia Sportium Toluca');
    expect(state.datos?.servicio.estatus, 'cotizado');
    expect(state.datos?.tieneDireccionOperativaActiva, isFalse);
    expect(state.modo, ServicioExpedienteModo.consulta);
  });

  test('guardar con datos válidos persiste y regresa a consulta', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      ServicioBorrador(
        nombre: 'Vigilancia Sportium Renombrada',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 2, 1),
      ),
    );

    expect(exito, isTrue);
    final state = container.read(servicioExpedienteControllerProvider(servicioId));
    expect(state.modo, ServicioExpedienteModo.consulta);
    expect(state.datos?.servicio.nombre, 'Vigilancia Sportium Renombrada');
  });

  test('guardar con nombre vacío reporta el error estructurado sin persistir', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      ServicioBorrador(
        nombre: '   ',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 2, 1),
      ),
    );

    expect(exito, isFalse);
    final state = container.read(servicioExpedienteControllerProvider(servicioId));
    expect(state.modo, ServicioExpedienteModo.edicion);
    expect(state.erroresGuardado, isNotEmpty);
  });

  test('cambiarEstatus a suspendido no requiere Dirección operativa', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

    final resultado = await notifier.cambiarEstatus(EstatusServicio.suspendido);

    expect(resultado, isA<CambiarEstatusServicioExitoso>());
    expect(container.read(servicioExpedienteControllerProvider(servicioId)).datos?.servicio.estatus, 'suspendido');
  });

  test('cambiarEstatus a activo se bloquea por falta de Dirección operativa', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

    final resultado = await notifier.cambiarEstatus(EstatusServicio.activo);

    expect(resultado, isA<CambiarEstatusServicioFaltaDireccionOperativa>());
    expect(container.read(servicioExpedienteControllerProvider(servicioId)).datos?.servicio.estatus, 'cotizado');
  });

  test('cambiarEstatus a terminado sin fecha exige la fecha efectiva', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

    final resultado = await notifier.cambiarEstatus(EstatusServicio.terminado);

    expect(resultado, isA<CambiarEstatusServicioRequiereFechaTermino>());
  });

  test('cambiarEstatus a terminado con fecha efectiva la persiste', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

    final resultado = await notifier.cambiarEstatus(
      EstatusServicio.terminado,
      fechaTerminoEfectiva: DateTime(2026, 6, 1),
    );

    expect(resultado, isA<CambiarEstatusServicioExitoso>());
    expect(container.read(servicioExpedienteControllerProvider(servicioId)).datos?.servicio.fechaTermino, DateTime(2026, 6, 1));
  });

  test('reintentarCarga vuelve a intentar tras un error de carga', () async {
    await esperarCargaInicial();
    final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

    await notifier.reintentarCarga();

    final state = container.read(servicioExpedienteControllerProvider(servicioId));
    expect(state.cargando, isFalse);
    expect(state.datos, isNotNull);
  });

  group('asignarEntidadFiscal', () {
    test('asigna una Entidad fiscal activa del mismo Cliente y refresca el expediente', () async {
      await esperarCargaInicial();
      final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
      final entidadFiscalValidator = EntidadFiscalValidator(clienteRepo, entidadFiscalRepo);
      final crearEntidadFiscal = CrearEntidadFiscalUseCase(
        entidadFiscalRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        entidadFiscalValidator,
      );
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: clienteId,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AA1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;

      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
      final resultado = await notifier.asignarEntidadFiscal(entidad.id);

      expect(resultado, isA<AsignarEntidadFiscalAServicioExitoso>());
      final state = container.read(servicioExpedienteControllerProvider(servicioId));
      expect(state.datos?.entidadFiscal?.id, entidad.id);
      expect(state.operandoRelacion, isFalse);
    });

    test('rechaza una Entidad fiscal de otro Cliente', () async {
      await esperarCargaInicial();
      final otroCliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Miluyole'));
      final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
      final entidadFiscalValidator = EntidadFiscalValidator(clienteRepo, entidadFiscalRepo);
      final crearEntidadFiscal = CrearEntidadFiscalUseCase(
        entidadFiscalRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        entidadFiscalValidator,
      );
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: otroCliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Miluyole SA de CV', rfc: 'MIL010101AA1'),
      );
      final entidadAjena = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;

      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
      final resultado = await notifier.asignarEntidadFiscal(entidadAjena.id);

      expect(resultado, isA<AsignarEntidadFiscalAServicioNoPerteneceAlCliente>());
      expect(container.read(servicioExpedienteControllerProvider(servicioId)).datos?.entidadFiscal, isNull);
    });

    test('quitar la asignación (null) siempre funciona', () async {
      await esperarCargaInicial();
      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

      final resultado = await notifier.asignarEntidadFiscal(null);

      expect(resultado, isA<AsignarEntidadFiscalAServicioExitoso>());
    });
  });

  group('asignarResponsableCliente', () {
    test('asigna un Contacto activo del mismo Cliente', () async {
      await esperarCargaInicial();
      final contacto = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: clienteId, nombre: 'Juan Pérez', tipo: 'comercial'),
      );

      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
      final resultado = await notifier.asignarResponsableCliente(contacto.id);

      expect(resultado, isA<AsignarResponsableClienteExitoso>());
      final state = container.read(servicioExpedienteControllerProvider(servicioId));
      expect(state.datos?.responsableCliente?.id, contacto.id);
    });

    test('un Contacto ya asignado que se archiva después conserva la relación con advertencia', () async {
      await esperarCargaInicial();
      final contacto = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: clienteId, nombre: 'Juan Pérez', tipo: 'comercial'),
      );
      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
      await notifier.asignarResponsableCliente(contacto.id);

      await clienteRepo.archivarContacto(contacto.id);
      await notifier.reintentarCarga();

      final state = container.read(servicioExpedienteControllerProvider(servicioId));
      expect(state.datos?.responsableCliente?.id, contacto.id);
      expect(state.datos?.responsableClienteArchivado, isTrue);
    });
  });

  group('asignarSucursalAdministrativa', () {
    test('asigna una Sucursal activa', () async {
      await esperarCargaInicial();
      final sucursalRepo = SucursalRepositoryImpl(db);
      final crearSucursal = CrearSucursalUseCase(sucursalRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final creada = await crearSucursal.ejecutar(nombre: 'Sucursal Centro', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
      final sucursal = creada.when(ok: (s) => s, failure: (_) => throw StateError('no debería fallar'));

      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);
      final resultado = await notifier.asignarSucursalAdministrativa(sucursal.id);

      expect(resultado, isA<AsignarSucursalAdministrativaExitoso>());
      expect(container.read(servicioExpedienteControllerProvider(servicioId)).datos?.sucursalAdministrativa?.id, sucursal.id);
    });

    test('rechaza una Sucursal inexistente', () async {
      await esperarCargaInicial();
      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

      final resultado = await notifier.asignarSucursalAdministrativa('sucursal-inexistente');

      expect(resultado, isA<AsignarSucursalAdministrativaNoExiste>());
    });
  });

  group('guardarDireccionOperativa', () {
    test('captura una Dirección operativa completa y habilita la activación', () async {
      await esperarCargaInicial();
      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

      final resultado = await notifier.guardarDireccionOperativa(
        const DireccionBorrador(
          calle: 'Av. Toluca',
          numeroExterior: '50',
          colonia: 'Centro',
          municipioAlcaldia: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
        ),
      );

      expect(resultado, isA<GuardarDireccionOperativaServicioExitoso>());
      final state = container.read(servicioExpedienteControllerProvider(servicioId));
      expect(state.datos?.tieneDireccionOperativaActiva, isTrue);

      final cambio = await notifier.cambiarEstatus(EstatusServicio.activo);
      expect(cambio, isA<CambiarEstatusServicioExitoso>());
    });

    test('rechaza una Dirección parcialmente incompleta', () async {
      await esperarCargaInicial();
      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

      final resultado = await notifier.guardarDireccionOperativa(const DireccionBorrador(calle: 'Av. Toluca'));

      expect(resultado, isA<GuardarDireccionOperativaServicioErroresValidacion>());
      expect(container.read(servicioExpedienteControllerProvider(servicioId)).datos?.tieneDireccionOperativaActiva, isFalse);
    });
  });

  group('guardarResponsableInterno', () {
    test('guarda y limpia el texto libre', () async {
      await esperarCargaInicial();
      final notifier = container.read(servicioExpedienteControllerProvider(servicioId).notifier);

      final guardado = await notifier.guardarResponsableInterno('Juan Pérez');
      expect(guardado, isTrue);
      expect(
        container.read(servicioExpedienteControllerProvider(servicioId)).datos?.servicio.responsableInterno,
        'Juan Pérez',
      );

      final limpiado = await notifier.guardarResponsableInterno('   ');
      expect(limpiado, isTrue);
      expect(
        container.read(servicioExpedienteControllerProvider(servicioId)).datos?.servicio.responsableInterno,
        isNull,
      );
    });
  });
}
