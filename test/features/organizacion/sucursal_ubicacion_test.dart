import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/ubicacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_ubicacion_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/mover_ubicacion_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_arbol_ubicaciones_usecase.dart';

void main() {
  late AppDatabase db;
  late CrearSucursalUseCase crearSucursal;
  late CrearUbicacionUseCase crearUbicacion;
  late MoverUbicacionUseCase moverUbicacion;
  late ObtenerArbolUbicacionesUseCase obtenerArbol;
  late UbicacionRepositoryImpl ubicacionRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    crearSucursal = CrearSucursalUseCase(SucursalRepositoryImpl(db), generarCodigo);
    ubicacionRepo = UbicacionRepositoryImpl(db);
    crearUbicacion = CrearUbicacionUseCase(ubicacionRepo, generarCodigo);
    moverUbicacion = MoverUbicacionUseCase(ubicacionRepo);
    obtenerArbol = ObtenerArbolUbicacionesUseCase(ubicacionRepo);
  });

  tearDown(() => db.close());

  test('crear una Sucursal genera su raíz y su Almacén General automáticamente', () async {
    final result = await crearSucursal.ejecutar(
      nombre: 'Sucursal Norte',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );

    expect(result.isOk, isTrue);
    late String sucursalId;
    result.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));

    final raiz = await ubicacionRepo.obtenerRaizDeSucursal(sucursalId);
    expect(raiz, isNotNull);
    expect(raiz!.tipoUbicacion, TipoUbicacion.sucursal.name);
    expect(raiz.parentId, isNull);

    final hijos = await ubicacionRepo.obtenerHijos(raiz.id);
    expect(hijos, hasLength(1));
    expect(hijos.single.nombre, 'Almacén General');
    expect(hijos.single.tipoUbicacion, TipoUbicacion.almacen.name);
  });

  test('el árbol se ensambla correctamente con varios niveles', () async {
    final sucursalResult = await crearSucursal.ejecutar(
      nombre: 'Sucursal Centro',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );
    late String sucursalId;
    sucursalResult.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));
    final raiz = (await ubicacionRepo.obtenerRaizDeSucursal(sucursalId))!;

    final almacen = (await ubicacionRepo.obtenerHijos(raiz.id)).single;

    final tallerResult = await crearUbicacion.ejecutar(
      nombre: 'Taller de mantenimiento',
      tipo: TipoUbicacion.taller,
      parentId: almacen.id,
    );
    expect(tallerResult.isOk, isTrue);

    final arbolResult = await obtenerArbol.ejecutar(raiz.id);
    expect(arbolResult.isOk, isTrue);
    arbolResult.when(
      ok: (arbol) {
        expect(arbol.nodo.id, raiz.id);
        expect(arbol.hijos, hasLength(1));
        expect(arbol.hijos.single.nodo.nombre, 'Almacén General');
        expect(arbol.hijos.single.hijos, hasLength(1));
        expect(arbol.hijos.single.hijos.single.nodo.nombre, 'Taller de mantenimiento');
      },
      failure: (_) => fail('no debería fallar'),
    );
  });

  test('rechaza exceder la profundidad máxima de 4 niveles', () async {
    final sucursalResult = await crearSucursal.ejecutar(
      nombre: 'Sucursal Profunda',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );
    late String sucursalId;
    sucursalResult.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));
    final raiz = (await ubicacionRepo.obtenerRaizDeSucursal(sucursalId))!; // nivel 1
    final almacen = (await ubicacionRepo.obtenerHijos(raiz.id)).single; // nivel 2

    final nivel3 = await crearUbicacion.ejecutar(
      nombre: 'Nivel 3',
      tipo: TipoUbicacion.resguardo,
      parentId: almacen.id,
    );
    late String nivel3Id;
    nivel3.when(ok: (u) => nivel3Id = u.id, failure: (_) => fail('no debería fallar')); // nivel 3

    final nivel4 = await crearUbicacion.ejecutar(
      nombre: 'Nivel 4',
      tipo: TipoUbicacion.resguardo,
      parentId: nivel3Id,
    );
    expect(nivel4.isOk, isTrue); // nivel 4 — todavía permitido

    late String nivel4Id;
    nivel4.when(ok: (u) => nivel4Id = u.id, failure: (_) => fail('no debería fallar'));

    final nivel5 = await crearUbicacion.ejecutar(
      nombre: 'Nivel 5 — debe rechazarse',
      tipo: TipoUbicacion.resguardo,
      parentId: nivel4Id,
    );
    expect(nivel5.isFailure, isTrue);
  });

  test('MoverUbicacionUseCase rechaza mover un nodo raíz', () async {
    final sucursalResult = await crearSucursal.ejecutar(
      nombre: 'Sucursal Raíz',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );
    late String sucursalId;
    sucursalResult.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));
    final raiz = (await ubicacionRepo.obtenerRaizDeSucursal(sucursalId))!;
    final almacen = (await ubicacionRepo.obtenerHijos(raiz.id)).single;

    final result = await moverUbicacion.ejecutar(ubicacionId: raiz.id, nuevoParentId: almacen.id);
    expect(result.isFailure, isTrue);
  });

  test('MoverUbicacionUseCase rechaza crear un ciclo', () async {
    final sucursalResult = await crearSucursal.ejecutar(
      nombre: 'Sucursal Ciclo',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );
    late String sucursalId;
    sucursalResult.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));
    final raiz = (await ubicacionRepo.obtenerRaizDeSucursal(sucursalId))!;
    final almacen = (await ubicacionRepo.obtenerHijos(raiz.id)).single;

    final hijoResult = await crearUbicacion.ejecutar(
      nombre: 'Hijo de Almacén',
      tipo: TipoUbicacion.resguardo,
      parentId: almacen.id,
    );
    late String hijoId;
    hijoResult.when(ok: (u) => hijoId = u.id, failure: (_) => fail('no debería fallar'));

    // Intentar mover "almacen" para que quede debajo de su propio hijo.
    final result = await moverUbicacion.ejecutar(ubicacionId: almacen.id, nuevoParentId: hijoId);
    expect(result.isFailure, isTrue);
  });

  test('MoverUbicacionUseCase permite mover un nodo hijo válido entre hermanos', () async {
    final sucursalResult = await crearSucursal.ejecutar(
      nombre: 'Sucursal Movible',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );
    late String sucursalId;
    sucursalResult.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));
    final raiz = (await ubicacionRepo.obtenerRaizDeSucursal(sucursalId))!;
    final almacen = (await ubicacionRepo.obtenerHijos(raiz.id)).single;

    final otraAreaResult = await crearUbicacion.ejecutar(
      nombre: 'Otra área',
      tipo: TipoUbicacion.oficina,
      parentId: raiz.id,
    );
    late String otraAreaId;
    otraAreaResult.when(ok: (u) => otraAreaId = u.id, failure: (_) => fail('no debería fallar'));

    final hijoResult = await crearUbicacion.ejecutar(
      nombre: 'Recurso movible',
      tipo: TipoUbicacion.resguardo,
      parentId: almacen.id,
    );
    late String hijoId;
    hijoResult.when(ok: (u) => hijoId = u.id, failure: (_) => fail('no debería fallar'));

    final result = await moverUbicacion.ejecutar(ubicacionId: hijoId, nuevoParentId: otraAreaId);
    expect(result.isOk, isTrue);

    final movido = await ubicacionRepo.obtenerPorId(hijoId);
    expect(movido!.parentId, otraAreaId);
  });
}
