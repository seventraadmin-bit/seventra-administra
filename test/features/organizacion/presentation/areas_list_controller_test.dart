import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/areas/areas_list_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(areasListControllerProvider, (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(areasListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial refleja las 6 Áreas sembradas', () async {
    await esperarCarga();
    final state = container.read(areasListControllerProvider);

    expect(state.errorCarga, isNull);
    expect(state.areas, hasLength(6));
  });

  test('recargar refleja un Área creada después de la carga inicial', () async {
    await esperarCarga();
    await container.read(crearAreaUseCaseProvider).ejecutar(nombre: 'Tecnología');

    await container.read(areasListControllerProvider.notifier).recargar();

    final state = container.read(areasListControllerProvider);
    expect(state.areas, hasLength(7));
    expect(state.areas.map((a) => a.nombre), contains('Tecnología'));
  });

  test('recargar refleja el resultado de desactivar un Área', () async {
    await esperarCarga();
    final area = container.read(areasListControllerProvider).areas.first;

    await AreaRepositoryImpl(db).desactivar(area.id);
    await container.read(areasListControllerProvider.notifier).recargar();

    final actualizada = container.read(areasListControllerProvider).areas.firstWhere((a) => a.id == area.id);
    expect(actualizada.activo, isFalse);
  });
}
