// Etapa 15 — reproducción real del bug reportado: un artículo con
// variante (`manejaVariante == true`, ej. CAMISOLA talla CH) mostraba
// Existencia = 0 en el expediente pese a tener movimientos de Entrada
// reales, tanto vía Compra como registro manual. Causa raíz:
// `calcularExistencia(articuloId: ..., varianteId: null)` filtraba
// `MovimientoInventario.varianteId IS NULL`, pero los movimientos de
// un artículo con variante siempre traen `varianteId` no nulo — la
// consulta nunca encontraba nada. Corregido en
// `InventarioRepositoryImpl.calcularExistencia`: `varianteId == null`
// ahora agrega TODOS los movimientos del artículo (con o sin
// variante), en vez de filtrar por `IS NULL`.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late RegistrarEntradaUseCase registrarEntrada;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloConVariante(String nombre) async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    final categoria = (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: nombre, manejaVariante: true, manejaSerie: false);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  test('artículo con variante: Existencia total (sin varianteId) refleja la entrada real de su única variante', () async {
    final articulo = await crearArticuloConVariante('CAMISOLA');
    final variante = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');

    final resultado = await registrarEntrada.ejecutar(
      articuloId: articulo.id,
      varianteId: variante.id,
      cantidad: 1,
      costoUnitario: 33000,
      fecha: DateTime(2026, 8, 12),
    );
    expect(resultado, isA<RegistrarEntradaExitoso>());

    // Exactamente el cálculo que hace el expediente/listado para
    // artículos con variante: sin `varianteId`, agregando el total.
    final existenciaTotal = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
    expect(existenciaTotal.total, 1, reason: 'antes del fix, esto devolvía 0 pese al movimiento real');
    expect(existenciaTotal.disponible, 1);

    // El cálculo POR variante específica sigue funcionando igual que
    // antes (no se rompió nada al quitar el filtro `IS NULL`).
    final existenciaVariante = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: variante.id);
    expect(existenciaVariante.total, 1);
  });

  test('artículo con dos variantes: Existencia total suma ambas, cada variante mantiene su propio conteo', () async {
    final articulo = await crearArticuloConVariante('CAMISOLA');
    final ch = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');
    final md = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'MD');

    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 2, fecha: DateTime(2026, 8, 12));
    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: md.id, cantidad: 5, fecha: DateTime(2026, 8, 12));

    final existenciaTotal = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
    expect(existenciaTotal.total, 7, reason: 'la existencia total del artículo agrega todas sus variantes');

    final existenciaCh = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existenciaCh.total, 2, reason: 'el filtro por variante específica sigue aislando correctamente');
  });

  test('artículo SIN variante: comportamiento sin cambios (varianteId siempre null en sus movimientos)', () async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    final categoria = (await crearCategoria.ejecutar(nombre: 'Guantes-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final articulo = ((await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Guantes')) as CrearArticuloExitoso).articulo;

    await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 4, fecha: DateTime(2026, 8, 12));

    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
    expect(existencia.total, 4);
  });
}
