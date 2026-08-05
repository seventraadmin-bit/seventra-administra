import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_state.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String servicioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db);
    final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, validator);

    final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
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
}
