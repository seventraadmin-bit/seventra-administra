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
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicios_list_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db);
    final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, validator);

    final sportium = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    final sportiumId = sportium.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
    await crearServicio.ejecutar(
      clienteId: sportiumId,
      borrador: const ServicioBorrador(
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: null,
      ),
    );

    // Fecha de inicio real vía un segundo borrador (el primero se usó
    // solo para simplificar el ejemplo anterior; aquí se corrige con
    // una fecha real para que la creación no falle).
    final construcciones = await crearCliente.ejecutar(nombreComercial: 'Construcciones Habitacionales');
    final construccionesId =
        construcciones.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
    await crearServicio.ejecutar(
      clienteId: construccionesId,
      borrador: ServicioBorrador(
        nombre: 'Mirabilia',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(serviciosListControllerProvider, (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(serviciosListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial refleja los Servicios creados antes de montar el controlador', () async {
    await esperarCarga();
    final state = container.read(serviciosListControllerProvider);

    expect(state.errorCarga, isNull);
    expect(state.servicios, hasLength(1), reason: 'el primero falló por fechaInicio nula, solo Mirabilia se creó');
  });

  test('la búsqueda filtra por nombre', () async {
    await esperarCarga();
    final notifier = container.read(serviciosListControllerProvider.notifier);

    notifier.actualizarBusqueda('mirabilia');

    final filtrados = container.read(serviciosListControllerProvider).serviciosFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.servicio.nombre, 'Mirabilia');
  });

  test('la búsqueda filtra por nombre del Cliente', () async {
    await esperarCarga();
    final notifier = container.read(serviciosListControllerProvider.notifier);

    notifier.actualizarBusqueda('construcciones habitacionales');

    final filtrados = container.read(serviciosListControllerProvider).serviciosFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.clienteNombre, 'Construcciones Habitacionales');
  });

  test('la búsqueda normaliza mayúsculas/minúsculas y espacios', () async {
    await esperarCarga();
    final notifier = container.read(serviciosListControllerProvider.notifier);

    notifier.actualizarBusqueda('  MIRABILIA  ');

    final filtrados = container.read(serviciosListControllerProvider).serviciosFiltrados;
    expect(filtrados, hasLength(1));
  });

  test('recargar refleja un Servicio creado después de la carga inicial', () async {
    await esperarCarga();
    final clienteRepo = ClienteRepositoryImpl(db);
    final sportium = await clienteRepo.listarActivos();
    final sportiumId = sportium.first.id;

    await container.read(crearServicioUseCaseProvider).ejecutar(
          clienteId: sportiumId,
          borrador: ServicioBorrador(
            nombre: 'Vigilancia Sportium Interlomas',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );

    await container.read(serviciosListControllerProvider.notifier).recargar();

    expect(container.read(serviciosListControllerProvider).servicios, hasLength(2));
  });
}
