import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    // Igual que en `puestos_list_controller_test.dart`: se crean los
    // Clientes de prueba ANTES de construir el `container`, para no
    // competir con la carga inicial disparada por `Future.microtask`.
    final crear = CrearClienteUseCase(ClienteRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    await crear.ejecutar(nombreComercial: 'Sportium');
    await crear.ejecutar(nombreComercial: 'Miluyole', observaciones: 'Cliente referido por un tercero');

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(clientesListControllerProvider, (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(clientesListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial refleja los Clientes creados antes de montar el controlador', () async {
    await esperarCarga();
    final state = container.read(clientesListControllerProvider);

    expect(state.errorCarga, isNull);
    expect(state.clientes, hasLength(2));
  });

  test('la búsqueda filtra por nombre comercial', () async {
    await esperarCarga();
    final notifier = container.read(clientesListControllerProvider.notifier);

    notifier.actualizarBusqueda('sportium');

    final filtrados = container.read(clientesListControllerProvider).clientesFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.nombreComercial, 'Sportium');
  });

  test('la búsqueda filtra por observaciones', () async {
    await esperarCarga();
    final notifier = container.read(clientesListControllerProvider.notifier);

    notifier.actualizarBusqueda('referido');

    final filtrados = container.read(clientesListControllerProvider).clientesFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.nombreComercial, 'Miluyole');
  });

  test('recargar refleja un Cliente creado después de la carga inicial', () async {
    await esperarCarga();
    await container.read(crearClienteUseCaseProvider).ejecutar(nombreComercial: 'Toluca 32');

    await container.read(clientesListControllerProvider.notifier).recargar();

    expect(container.read(clientesListControllerProvider).clientes, hasLength(3));
  });
}
