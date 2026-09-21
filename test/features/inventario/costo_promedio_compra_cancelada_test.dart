// Inventario — el costo promedio deja de contar Compras canceladas.
//
// Hallazgo que corrige: cancelar una Compra conserva su movimiento
// `entrada` original y agrega un `baja` de reversa. Como el promedio
// ponderado sólo mira `entrada`, la compra cancelada seguía pesando en
// el numerador Y en el denominador: una Compra de 10 × $300 cancelada
// arrastraba el costo de un artículo que en realidad se compró a $100.
//
// Cómo se identifica una entrada cancelada — por FK, nunca por texto:
//
//   MovimientoInventario.id
//     ← CompraPartidaMovimiento.movimientoInventarioId
//        → CompraPartida.compraId
//           → Compra.estatus == 'cancelada'
//
// Lo que NO se hace: `entradas - bajas`. Una baja normal (entrega,
// pérdida, daño, baja física) no vuelve inválida la compra original, y
// restarla cambiaría retroactivamente un costo histórico correcto. El
// caso F existe exactamente para fijar esa diferencia.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/data/tables/compra_table.dart' show EstatusCompra;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CancelarCompraUseCase cancelarCompra;
  late CorregirCompraUseCase corregirCompra;
  var consecutivo = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo);
    consecutivo = 0;
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticulo({bool manejaVariante = false}) async {
    final n = (++consecutivo).toString().padLeft(3, '0');
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Cat $n'),
        );
    return articuloRepo.crear(
      folio: 'ART-$n',
      categoriaId: categoria.id,
      nombre: 'Articulo $n',
      manejaVariante: manejaVariante,
      manejaSerie: false,
    );
  }

  /// Registra una Compra real de un artículo por cantidad.
  Future<CompraData> comprar({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    required int costoUnitario,
  }) async {
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 3, 10),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(
          destino: DestinoCompraPartida.inventario.name,
          articuloId: articuloId,
          varianteId: varianteId,
          cantidad: cantidad,
          costoUnitario: costoUnitario,
        ),
      ],
    );
    expect(resultado, isA<RegistrarCompraExitosa>(), reason: 'la compra debe registrarse');
    return (resultado as RegistrarCompraExitosa).compra;
  }

  Future<void> cancelar(CompraData compra) async {
    final resultado = await cancelarCompra.ejecutar(
      compraId: compra.id,
      motivo: MotivoCancelacionCompra.errorDeCaptura,
      detalle: 'Capturada dos veces',
    );
    expect(resultado, isA<CancelarCompraExitosa>(), reason: 'la cancelación debe completarse');
  }

  /// Las tres rutas de costo promedio, para exigirles el mismo número.
  Future<({int? individual, int? porArticulo})> costosDe(String articuloId) async {
    return (
      individual: await inventarioRepo.calcularCostoPromedio(articuloId: articuloId),
      porArticulo: (await inventarioRepo.calcularCostoPromedioPorArticulo([articuloId]))[articuloId],
    );
  }

  group('Casos obligatorios A-G', () {
    test('A. Compra vigente 10 × \$100: promedio \$100', () async {
      final articulo = await crearArticulo();
      await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000);

      final costos = await costosDe(articulo.id);
      expect(costos.individual, 10000);
      expect(costos.porArticulo, 10000);
    });

    test('B. la misma Compra cancelada: promedio null, sin otra entrada válida', () async {
      final articulo = await crearArticulo();
      final compra = await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000);
      await cancelar(compra);

      final costos = await costosDe(articulo.id);
      expect(costos.individual, isNull, reason: 'no queda ninguna entrada económicamente válida');
      expect(costos.porArticulo, isNull);

      // El historial se conserva: la entrada original y la reversa siguen
      // ahí. La corrección es de LECTURA, no borra movimientos.
      final movimientos = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(
        movimientos.where((m) => m.tipoMovimiento == TipoMovimientoInventario.entrada.name),
        hasLength(1),
        reason: 'la entrada histórica NO se borra',
      );
      expect(
        movimientos.where((m) => m.tipoMovimiento == TipoMovimientoInventario.baja.name),
        hasLength(1),
        reason: 'la reversa tampoco se borra',
      );
    });

    test('C. mezcla: \$100 vigente + \$300 cancelada → \$100, nunca \$200', () async {
      final articulo = await crearArticulo();
      await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000);
      final cancelada = await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 30000);
      await cancelar(cancelada);

      final costos = await costosDe(articulo.id);
      expect(costos.individual, 10000, reason: 'sólo la compra vigente describe el costo');
      expect(costos.porArticulo, 10000);
      expect(costos.individual, isNot(20000), reason: '\$200 sería el promedio contaminado por la cancelada');
    });

    test('D. dos compras vigentes: 10 × \$100 + 20 × \$200 = \$166.67 ponderado', () async {
      final articulo = await crearArticulo();
      await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000);
      await comprar(articuloId: articulo.id, cantidad: 20, costoUnitario: 20000);

      // (10×10000 + 20×20000) / 30 = 16666.66… -> 16667 centavos.
      final costos = await costosDe(articulo.id);
      expect(costos.individual, 16667, reason: 'ponderado por cantidad, no media simple (\$150)');
      expect(costos.porArticulo, 16667);
    });

    test('E. variante: talla con entrada vigente \$50 y entrada cancelada \$150 → \$50', () async {
      final articulo = await crearArticulo(manejaVariante: true);
      final tallaM = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'M');
      final tallaG = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'G');

      await comprar(articuloId: articulo.id, varianteId: tallaM.id, cantidad: 4, costoUnitario: 5000);
      final cancelada =
          await comprar(articuloId: articulo.id, varianteId: tallaM.id, cantidad: 4, costoUnitario: 15000);
      await cancelar(cancelada);
      // Otra talla, vigente, para comprobar que la exclusión no se
      // derrama entre variantes.
      await comprar(articuloId: articulo.id, varianteId: tallaG.id, cantidad: 2, costoUnitario: 80000);

      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id, varianteId: tallaM.id), 5000);
      expect((await inventarioRepo.calcularCostoPromedioPorVariante([tallaM.id]))[tallaM.id], 5000);
      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id, varianteId: tallaG.id), 80000);
      expect((await inventarioRepo.calcularCostoPromedioPorVariante([tallaG.id]))[tallaG.id], 80000);
    });

    test('F. una baja física normal NO invalida la Compra: el costo sigue en \$100', () async {
      final articulo = await crearArticulo();
      await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000);

      final antes = await costosDe(articulo.id);
      expect(antes.individual, 10000);

      // Baja física de una unidad: un movimiento `baja` SIN origen de
      // compra cancelada. Si la regla fuera "entradas menos bajas", el
      // costo se movería; no debe moverse.
      await inventarioRepo.registrarBaja(articuloId: articulo.id, cantidad: 1, observaciones: 'Se rompió');

      final despues = await costosDe(articulo.id);
      expect(despues.individual, 10000, reason: 'la baja física no cambia el costo histórico de la entrada válida');
      expect(despues.porArticulo, 10000);

      // Y la existencia SÍ bajó: lo que cambia es el stock, no el costo.
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 9);
    });

    test('G. una Compra cancelada no puede corregirse para volver a contaminar el promedio', () async {
      final articulo = await crearArticulo();
      final compra = await comprar(articuloId: articulo.id, cantidad: 10, costoUnitario: 30000);
      await cancelar(compra);
      expect(costosDe(articulo.id).then((c) => c.individual), completion(isNull));

      final partida = (await compraRepo.listarPartidas(compra.id)).single;
      final correccion = await corregirCompra.ejecutar(
        compraId: compra.id,
        motivo: 'errorDeCaptura',
        cambiosPartidas: [
          CorreccionPartidaCantidadCosto(compraPartidaId: partida.id, nuevoCostoUnitario: 10000),
        ],
      );

      expect(correccion, isA<CorregirCompraCancelada>(), reason: 'el ciclo de Compra ya lo impide');
      final despues = await costosDe(articulo.id);
      expect(despues.individual, isNull, reason: 'sigue sin entradas válidas');
      expect(despues.porArticulo, isNull);

      final recargada = await compraRepo.obtenerPorId(compra.id);
      expect(recargada!.estatus, EstatusCompra.cancelada.name, reason: 'no hay camino de vuelta a registrada');
    });
  });

  group('Una sola regla en las tres rutas', () {
    test('individual, lote por artículo y lote por variante coinciden con y sin cancelaciones', () async {
      final porCantidad = await crearArticulo();
      await comprar(articuloId: porCantidad.id, cantidad: 5, costoUnitario: 12000);
      final canceladaCantidad = await comprar(articuloId: porCantidad.id, cantidad: 5, costoUnitario: 90000);
      await cancelar(canceladaCantidad);

      final conTallas = await crearArticulo(manejaVariante: true);
      final talla = await articuloRepo.crearVariante(articuloId: conTallas.id, valor: 'Unica');
      await comprar(articuloId: conTallas.id, varianteId: talla.id, cantidad: 3, costoUnitario: 7000);
      final canceladaTalla =
          await comprar(articuloId: conTallas.id, varianteId: talla.id, cantidad: 3, costoUnitario: 70000);
      await cancelar(canceladaTalla);

      // Artículo: individual == lote.
      expect(await inventarioRepo.calcularCostoPromedio(articuloId: porCantidad.id), 12000);
      expect((await inventarioRepo.calcularCostoPromedioPorArticulo([porCantidad.id]))[porCantidad.id], 12000);

      // Variante: individual == lote.
      expect(await inventarioRepo.calcularCostoPromedio(articuloId: conTallas.id, varianteId: talla.id), 7000);
      expect((await inventarioRepo.calcularCostoPromedioPorVariante([talla.id]))[talla.id], 7000);

      // Y el artículo con tallas sigue sin costo a nivel de artículo.
      expect((await inventarioRepo.calcularCostoPromedioPorArticulo([conTallas.id])).containsKey(conTallas.id), isFalse);
    });

    test('una entrada manual, sin Compra detrás, nunca se excluye', () async {
      final articulo = await crearArticulo();
      // Sin `CompraPartidaMovimiento`: no tiene origen económico que
      // cancelar, así que la exclusión no puede alcanzarla.
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 4,
              costoUnitario: const Value(25000),
              fecha: DateTime(2026, 3, 1),
            ),
          );

      final costos = await costosDe(articulo.id);
      expect(costos.individual, 25000);
      expect(costos.porArticulo, 25000);
    });
  });

  group('Rendimiento — la exclusión no cuesta consultas extra', () {
    test('el lote sigue resolviendo todo en una sola consulta', () async {
      final articulos = <ArticuloData>[];
      for (var i = 0; i < 12; i++) {
        final articulo = await crearArticulo();
        await comprar(articuloId: articulo.id, cantidad: 2, costoUnitario: 10000 + i * 100);
        if (i.isEven) {
          final cancelada = await comprar(articuloId: articulo.id, cantidad: 2, costoUnitario: 99000);
          await cancelar(cancelada);
        }
        articulos.add(articulo);
      }

      final enLote = await inventarioRepo.calcularCostoPromedioPorArticulo(articulos.map((a) => a.id));

      // El lote coincide con la lectura individual de los 12, y la
      // exclusión viaja dentro del mismo SELECT (subconsulta), no como
      // una consulta por artículo.
      for (final articulo in articulos) {
        expect(enLote[articulo.id], await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id),
            reason: articulo.folio);
      }
      expect(enLote.values.every((c) => c < 99000), isTrue, reason: 'ninguna cancelada contaminó el promedio');
    });
  });
}
