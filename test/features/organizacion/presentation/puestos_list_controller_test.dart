import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puestos_list_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    // Igual que en `sucursales_list_controller_test.dart`: se crean los
    // Puestos de prueba ANTES de construir el `container`, para no
    // competir con la carga inicial disparada por `Future.microtask`.
    final areaRepo = AreaRepositoryImpl(db);
    final crear = CrearPuestoUseCase(
      PuestoRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(areaRepo),
    );
    await crear.ejecutar(const PuestoBorrador(
      nombre: 'Guardia Norte',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 1,
    ));
    await crear.ejecutar(const PuestoBorrador(
      nombre: 'Analista de Reclutamiento',
      areaId: SeedIds.areaReclutamiento,
      tipo: TipoPuesto.administrativo,
      nivelJerarquico: 4,
      descripcion: 'Entrevistas y seguimiento de candidatos',
    ));

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(puestosListControllerProvider, (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(puestosListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial refleja los Puestos y Áreas creados antes de montar el controlador', () async {
    await esperarCarga();
    final state = container.read(puestosListControllerProvider);

    expect(state.errorCarga, isNull);
    expect(state.puestos, hasLength(2));
    expect(state.areas, isNotEmpty);
  });

  test('la búsqueda filtra por nombre', () async {
    await esperarCarga();
    final notifier = container.read(puestosListControllerProvider.notifier);

    notifier.actualizarBusqueda('norte');

    final filtrados = container.read(puestosListControllerProvider).puestosFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.nombre, 'Guardia Norte');
  });

  test('la búsqueda filtra por nombre de área', () async {
    await esperarCarga();
    final notifier = container.read(puestosListControllerProvider.notifier);

    notifier.actualizarBusqueda('reclutamiento');

    final filtrados = container.read(puestosListControllerProvider).puestosFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.nombre, 'Analista de Reclutamiento');
  });

  test('la búsqueda filtra por descripción — cobertura exigida por la corrección #4', () async {
    await esperarCarga();
    final notifier = container.read(puestosListControllerProvider.notifier);

    notifier.actualizarBusqueda('candidatos');

    final filtrados = container.read(puestosListControllerProvider).puestosFiltrados;
    expect(filtrados, hasLength(1));
    expect(filtrados.single.nombre, 'Analista de Reclutamiento');
  });

  test('recargar refleja un Puesto creado después de la carga inicial', () async {
    await esperarCarga();
    await container.read(crearPuestoUseCaseProvider).ejecutar(const PuestoBorrador(
      nombre: 'Supervisor',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 5,
    ));

    await container.read(puestosListControllerProvider.notifier).recargar();

    expect(container.read(puestosListControllerProvider).puestos, hasLength(3));
  });
}
