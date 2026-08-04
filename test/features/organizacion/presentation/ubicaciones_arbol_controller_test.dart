import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/ubicacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/ubicaciones_arbol_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String sucursalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final crear = CrearSucursalUseCase(
      SucursalRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );
    final creada = await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    sucursalId = creada.when(ok: (s) => s.id, failure: (f) => throw StateError(f.message));

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(ubicacionesArbolControllerProvider(sucursalId), (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    while (container.read(ubicacionesArbolControllerProvider(sucursalId)).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial resuelve la raíz con el Almacén General ya creado', () async {
    await esperarCarga();
    final state = container.read(ubicacionesArbolControllerProvider(sucursalId));

    expect(state.errorCarga, isNull);
    expect(state.arbol!.nodo.tipoUbicacion, TipoUbicacion.sucursal.name);
    expect(state.arbol!.hijos, hasLength(1));
    expect(state.arbol!.hijos.single.nodo.nombre, 'Almacén General');
    // Todo expandido por defecto al cargar.
    expect(state.expandidos, containsAll([state.arbol!.nodo.id, state.arbol!.hijos.single.nodo.id]));
  });

  test('colapsarTodo vacía los expandidos y expandirTodo los repone', () async {
    await esperarCarga();
    final notifier = container.read(ubicacionesArbolControllerProvider(sucursalId).notifier);

    notifier.colapsarTodo();
    expect(container.read(ubicacionesArbolControllerProvider(sucursalId)).expandidos, isEmpty);

    notifier.expandirTodo();
    final state = container.read(ubicacionesArbolControllerProvider(sucursalId));
    expect(state.expandidos, containsAll([state.arbol!.nodo.id, state.arbol!.hijos.single.nodo.id]));
  });

  test('alternarExpandido cambia solo el nodo indicado', () async {
    await esperarCarga();
    final notifier = container.read(ubicacionesArbolControllerProvider(sucursalId).notifier);
    final raizId = container.read(ubicacionesArbolControllerProvider(sucursalId)).arbol!.nodo.id;

    notifier.alternarExpandido(raizId);
    expect(container.read(ubicacionesArbolControllerProvider(sucursalId)).expandidos.contains(raizId), isFalse);

    notifier.alternarExpandido(raizId);
    expect(container.read(ubicacionesArbolControllerProvider(sucursalId)).expandidos.contains(raizId), isTrue);
  });

  test('agregarUbicacion agrega un nodo hijo y recarga el árbol', () async {
    await esperarCarga();
    final notifier = container.read(ubicacionesArbolControllerProvider(sucursalId).notifier);
    final raizId = container.read(ubicacionesArbolControllerProvider(sucursalId)).arbol!.nodo.id;

    final exito = await notifier.agregarUbicacion(parentId: raizId, nombre: 'Oficina 1', tipo: TipoUbicacion.oficina);

    expect(exito, isTrue);
    final state = container.read(ubicacionesArbolControllerProvider(sucursalId));
    expect(state.arbol!.hijos.map((h) => h.nodo.nombre), containsAll(['Almacén General', 'Oficina 1']));
  });

  test('moverUbicacion reubica un nodo bajo otro padre válido', () async {
    await esperarCarga();
    final notifier = container.read(ubicacionesArbolControllerProvider(sucursalId).notifier);
    final raizId = container.read(ubicacionesArbolControllerProvider(sucursalId)).arbol!.nodo.id;
    await notifier.agregarUbicacion(parentId: raizId, nombre: 'Oficina 1', tipo: TipoUbicacion.oficina);

    final arbolAntes = container.read(ubicacionesArbolControllerProvider(sucursalId)).arbol!;
    final almacenId = arbolAntes.hijos.firstWhere((h) => h.nodo.nombre == 'Almacén General').nodo.id;
    final oficinaId = arbolAntes.hijos.firstWhere((h) => h.nodo.nombre == 'Oficina 1').nodo.id;

    final exito = await notifier.moverUbicacion(ubicacionId: oficinaId, nuevoParentId: almacenId);

    expect(exito, isTrue);
    final ubicacionRepo = UbicacionRepositoryImpl(db);
    final oficina = await ubicacionRepo.obtenerPorId(oficinaId);
    expect(oficina!.parentId, almacenId);
  });

  test('agregarUbicacion con un padre inexistente falla sin romper el estado', () async {
    await esperarCarga();
    final notifier = container.read(ubicacionesArbolControllerProvider(sucursalId).notifier);

    final exito = await notifier.agregarUbicacion(
      parentId: 'no-existe',
      nombre: 'Oficina fantasma',
      tipo: TipoUbicacion.oficina,
    );

    expect(exito, isFalse);
    expect(container.read(ubicacionesArbolControllerProvider(sucursalId)).procesando, isFalse);
  });
}
