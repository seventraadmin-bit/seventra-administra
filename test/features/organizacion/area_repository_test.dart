import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';

void main() {
  late AppDatabase db;
  late AreaRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AreaRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('listarTodas devuelve las 6 Áreas sembradas con el formato definitivo', () async {
    final areas = await repo.listarTodas();
    expect(areas, hasLength(6));
    expect(areas.map((a) => a.codigo).toSet(), {
      'ARE-0001', 'ARE-0002', 'ARE-0003', 'ARE-0004', 'ARE-0005', 'ARE-0006',
    });
  });

  test('crear agrega una Área nueva con el código recibido y un id propio', () async {
    final creada = await repo.crear(codigo: 'ARE-0007', nombre: 'Calidad', descripcion: 'Aseguramiento de calidad');

    expect(creada.codigo, 'ARE-0007');
    expect(creada.nombre, 'Calidad');
    expect(creada.id, isNotEmpty);
    expect(creada.activo, isTrue);

    final todas = await repo.listarTodas();
    expect(todas, hasLength(7));
  });

  test('actualizar cambia nombre/descripción sin tocar código ni estado', () async {
    final creada = await repo.crear(codigo: 'ARE-0007', nombre: 'Calidad', descripcion: null);

    final actualizada = await repo.actualizar(id: creada.id, nombre: 'Calidad y Procesos', descripcion: 'Nueva descripción');

    expect(actualizada.nombre, 'Calidad y Procesos');
    expect(actualizada.descripcion, 'Nueva descripción');
    expect(actualizada.codigo, 'ARE-0007');
    expect(actualizada.activo, isTrue);
  });

  test('desactivar y activar cambian solo el booleano activo', () async {
    final areas = await repo.listarTodas();
    final areaId = areas.first.id;

    final desactivada = await repo.desactivar(areaId);
    expect(desactivada.activo, isFalse);

    final activasTrasDesactivar = await repo.listarActivas();
    expect(activasTrasDesactivar.map((a) => a.id), isNot(contains(areaId)));

    final reactivada = await repo.activar(areaId);
    expect(reactivada.activo, isTrue);

    final activasTrasReactivar = await repo.listarActivas();
    expect(activasTrasReactivar.map((a) => a.id), contains(areaId));
  });

  test('listarActivas excluye únicamente las inactivas', () async {
    final areas = await repo.listarTodas();
    await repo.desactivar(areas.first.id);

    final activas = await repo.listarActivas();
    expect(activas, hasLength(5));
  });
}
