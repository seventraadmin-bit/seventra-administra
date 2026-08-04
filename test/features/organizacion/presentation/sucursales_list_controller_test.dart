import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursales_list_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    // Crea las sucursales de prueba ANTES de construir el `container` —
    // el controlador dispara su carga inicial vía `Future.microtask` en
    // cuanto se le agrega un listener, y esa carga podría ganarle la
    // carrera a un `crear.ejecutar` posterior si ambos comparten el
    // mismo container.
    final crear = CrearSucursalUseCase(
      SucursalRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );
    await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    await crear.ejecutar(nombre: 'Bodega Sur', tipoSucursalId: SeedIds.tipoSucursalBodega);

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(sucursalesListControllerProvider, (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(sucursalesListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial refleja las sucursales creadas antes de montar el controlador', () async {
    await esperarCarga();
    final state = container.read(sucursalesListControllerProvider);

    expect(state.errorCarga, isNull);
    expect(state.sucursales, hasLength(2));
    expect(state.tipos, isNotEmpty);
  });

  test('la búsqueda filtra por nombre', () async {
    await esperarCarga();
    final notifier = container.read(sucursalesListControllerProvider.notifier);

    notifier.actualizarBusqueda('norte');

    final filtradas = container.read(sucursalesListControllerProvider).sucursalesFiltradas;
    expect(filtradas, hasLength(1));
    expect(filtradas.single.nombre, 'Sucursal Norte');
  });

  test('la búsqueda filtra por nombre de tipo', () async {
    await esperarCarga();
    final notifier = container.read(sucursalesListControllerProvider.notifier);

    notifier.actualizarBusqueda('bodega');

    final filtradas = container.read(sucursalesListControllerProvider).sucursalesFiltradas;
    expect(filtradas, hasLength(1));
    expect(filtradas.single.nombre, 'Bodega Sur');
  });

  test('recargar refleja una sucursal creada después de la carga inicial', () async {
    await esperarCarga();
    await container
        .read(crearSucursalUseCaseProvider)
        .ejecutar(nombre: 'Oficina Centro', tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa);

    await container.read(sucursalesListControllerProvider.notifier).recargar();

    expect(container.read(sucursalesListControllerProvider).sucursales, hasLength(3));
  });
}
