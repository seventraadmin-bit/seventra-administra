// Inventario — eliminación del N+1 del resumen.
//
// Esta etapa no cambia ninguna regla ni ninguna cifra: cambia CUÁNTAS
// consultas se hacen para obtener las mismas cifras. Por eso las
// pruebas son de dos clases y las dos hacen falta:
//
//  1. **Paridad.** Para cada artículo, la lectura en lote tiene que
//     devolver exactamente lo mismo que la lectura individual —
//     existencia por estado, total, disponible, costo promedio y valor.
//     La versión individual se conserva y se usa aquí como oráculo.
//
//  2. **Complejidad.** Que el número de consultas deje de crecer con el
//     número de artículos. Medir tiempo no serviría: es ruidoso y
//     depende de la máquina. Se cuentan las sentencias que llegan a
//     SQLite con `ContadorDeConsultas`.
//
// El dataset es deliberadamente heterogéneo: serializados con unidades
// en los ocho estatus, artículos por cantidad con los ocho tipos de
// movimiento, artículos sin nada, con variante, con entradas sin costo
// capturado y con varias entradas a precios distintos (promedio
// ponderado con redondeo).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';

import '../../support/contador_de_consultas.dart';

/// El resumen TAL COMO ERA: dos consultas por artículo.
///
/// Se conserva aquí, en las pruebas y no en producción, para poder
/// exigir igualdad exacta contra la versión en lote. Si alguien
/// cambiara una fórmula, este oráculo dejaría de coincidir.
Future<ResumenInventarioReportes> resumenLegacyPorArticulo({
  required ArticuloRepositoryImpl articuloRepo,
  required InventarioRepository inventarioRepo,
  required AsignacionRepositoryImpl asignacionRepo,
}) async {
  final articulos = await articuloRepo.listar(soloActivos: false);

  var existenciaTotal = 0;
  var valorAproximado = 0;
  var articulosConValorExcluido = 0;

  for (final articulo in articulos) {
    final existencia = articulo.manejaSerie
        ? await inventarioRepo.calcularExistenciaUnidades(articulo.id)
        : await inventarioRepo.calcularExistencia(articuloId: articulo.id);
    existenciaTotal += existencia.total;

    if (articulo.manejaVariante) {
      articulosConValorExcluido++;
      continue;
    }
    final costoPromedio = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);
    if (costoPromedio == null) {
      articulosConValorExcluido++;
      continue;
    }
    valorAproximado += costoPromedio * existencia.total;
  }

  return ResumenInventarioReportes(
    existenciaTotal: existenciaTotal,
    asignacionesVigentes: (await asignacionRepo.listarTodasActivas()).length,
    danadosPerdidos: (await asignacionRepo.listarDanadasPerdidas()).length,
    descuentosPendientes: (await asignacionRepo.listarTodosDescuentosPendientes()).length,
    movimientosEnPeriodo: await inventarioRepo.totalMovimientosEnRango(),
    valorAproximado: valorAproximado,
    articulosConValorExcluido: articulosConValorExcluido,
    unidadesPorEstatus: await inventarioRepo.contarUnidadesPorEstatus(),
  );
}

void main() {
  late AppDatabase db;
  late ContadorDeConsultas contador;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  var consecutivo = 0;

  setUp(() async {
    contador = ContadorDeConsultas(NativeDatabase.memory());
    db = AppDatabase(contador);
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    consecutivo = 0;
    // Fuerza la apertura y el sembrado antes de medir nada.
    await db.select(db.articulo).get();
  });

  tearDown(() => db.close());

  Future<String> crearCategoria() async {
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Cat ${++consecutivo}'),
        );
    return categoria.id;
  }

  Future<ArticuloData> crearArticulo({
    required bool manejaSerie,
    bool manejaVariante = false,
    String? categoriaId,
  }) async {
    final n = (++consecutivo).toString().padLeft(4, '0');
    return articuloRepo.crear(
      folio: 'ART-$n',
      categoriaId: categoriaId ?? await crearCategoria(),
      nombre: 'Articulo $n',
      manejaVariante: manejaVariante,
      manejaSerie: manejaSerie,
    );
  }

  Future<void> unidad(String articuloId, EstatusArticuloUnidad estatus) async {
    final n = (++consecutivo).toString().padLeft(5, '0');
    await db.into(db.articuloUnidad).insert(
          ArticuloUnidadCompanion.insert(
            articuloId: articuloId,
            codigo: 'UNI-$n',
            numeroSerie: 'S-$n',
            estatus: Value(estatus.name),
          ),
        );
  }

  Future<void> movimiento(
    String articuloId,
    TipoMovimientoInventario tipo,
    int cantidad, {
    int? costoUnitario,
    String? varianteId,
  }) async {
    await db.into(db.movimientoInventario).insert(
          MovimientoInventarioCompanion.insert(
            articuloId: articuloId,
            varianteId: Value(varianteId),
            tipoMovimiento: tipo.name,
            cantidad: cantidad,
            costoUnitario: Value(costoUnitario),
            fecha: DateTime(2026, 3, 10),
          ),
        );
  }

  /// Dataset heterogéneo de [cantidadDeArticulos] artículos.
  ///
  /// El patrón se repite en ciclos de cinco para que cualquier tamaño
  /// contenga las mismas clases de artículo.
  Future<List<ArticuloData>> sembrar(int cantidadDeArticulos) async {
    final categoriaId = await crearCategoria();
    final creados = <ArticuloData>[];

    for (var i = 0; i < cantidadDeArticulos; i++) {
      switch (i % 5) {
        // 0 — serializado con unidades en LOS OCHO estatus.
        case 0:
          final articulo = await crearArticulo(manejaSerie: true, categoriaId: categoriaId);
          for (final estatus in EstatusArticuloUnidad.values) {
            await unidad(articulo.id, estatus);
          }
          await movimiento(articulo.id, TipoMovimientoInventario.entrada, 8, costoUnitario: 12500);
          creados.add(articulo);

        // 1 — por cantidad, con los ocho tipos de movimiento.
        case 1:
          final articulo = await crearArticulo(manejaSerie: false, categoriaId: categoriaId);
          await movimiento(articulo.id, TipoMovimientoInventario.entrada, 40, costoUnitario: 10000);
          await movimiento(articulo.id, TipoMovimientoInventario.entrada, 20, costoUnitario: 17500);
          await movimiento(articulo.id, TipoMovimientoInventario.ajusteEntrada, 3);
          await movimiento(articulo.id, TipoMovimientoInventario.ajusteSalida, 1);
          await movimiento(articulo.id, TipoMovimientoInventario.salidaAsignacion, 9);
          await movimiento(articulo.id, TipoMovimientoInventario.entradaDevolucion, 2);
          await movimiento(articulo.id, TipoMovimientoInventario.salidaDano, 3);
          await movimiento(articulo.id, TipoMovimientoInventario.salidaPerdida, 1);
          await movimiento(articulo.id, TipoMovimientoInventario.baja, 4);
          creados.add(articulo);

        // 2 — sin ningún movimiento ni unidad.
        case 2:
          creados.add(await crearArticulo(manejaSerie: false, categoriaId: categoriaId));

        // 3 — con variante: nunca se valúa a nivel de artículo.
        case 3:
          final articulo = await crearArticulo(manejaSerie: false, manejaVariante: true, categoriaId: categoriaId);
          final variante = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'Talla $i');
          await movimiento(articulo.id, TipoMovimientoInventario.entrada, 12,
              costoUnitario: 9900, varianteId: variante.id);
          await movimiento(articulo.id, TipoMovimientoInventario.salidaAsignacion, 5, varianteId: variante.id);
          creados.add(articulo);

        // 4 — entradas SIN costo capturado: el valor no se puede conocer.
        case 4:
          final articulo = await crearArticulo(manejaSerie: true, categoriaId: categoriaId);
          await unidad(articulo.id, EstatusArticuloUnidad.disponible);
          await unidad(articulo.id, EstatusArticuloUnidad.enLavanderia);
          await movimiento(articulo.id, TipoMovimientoInventario.entrada, 2);
          creados.add(articulo);
      }
    }

    return creados;
  }

  ObtenerResumenInventarioUseCase construirCasoDeUso() =>
      ObtenerResumenInventarioUseCase(articuloRepo, inventarioRepo, asignacionRepo);

  group('Paridad — el lote devuelve exactamente lo mismo que la lectura individual', () {
    test('existencia por estado, total y disponible coinciden artículo por artículo', () async {
      final articulos = await sembrar(25);

      final enLote = await inventarioRepo.calcularExistenciaPorArticulos(articulos);

      expect(enLote.keys.toSet(), articulos.map((a) => a.id).toSet(),
          reason: 'todo artículo pedido aparece, aunque no tenga movimientos');

      for (final articulo in articulos) {
        final individual = articulo.manejaSerie
            ? await inventarioRepo.calcularExistenciaUnidades(articulo.id)
            : await inventarioRepo.calcularExistencia(articuloId: articulo.id);
        final lote = enLote[articulo.id]!;

        expect(lote.disponible, individual.disponible, reason: 'disponible de ${articulo.folio}');
        expect(lote.asignado, individual.asignado, reason: 'asignado de ${articulo.folio}');
        expect(lote.danado, individual.danado, reason: 'danado de ${articulo.folio}');
        expect(lote.perdido, individual.perdido, reason: 'perdido de ${articulo.folio}');
        expect(lote.enProceso, individual.enProceso, reason: 'enProceso de ${articulo.folio}');
        expect(lote.total, individual.total, reason: 'total de ${articulo.folio}');
      }
    });

    test('la regla de existencia se mantiene: enProceso suma, baja no', () async {
      final articulo = await crearArticulo(manejaSerie: true);
      for (final estatus in EstatusArticuloUnidad.values) {
        await unidad(articulo.id, estatus);
      }

      final lote = (await inventarioRepo.calcularExistenciaPorArticulos([articulo]))[articulo.id]!;

      // Ocho estatus, una unidad cada uno.
      expect(lote.disponible, 1);
      expect(lote.asignado, 1);
      expect(lote.danado, 1);
      expect(lote.perdido, 1);
      expect(lote.enProceso, 3, reason: 'lavandería + reparación + pendiente de desecho');
      expect(lote.total, 7, reason: 'los 8 estatus menos la baja');
      expect(lote.total, lote.disponible + lote.asignado + lote.danado + lote.perdido + lote.enProceso);
    });

    test('el costo promedio coincide, incluidos redondeo, sin costo y artículos con variante', () async {
      final articulos = await sembrar(25);

      final enLote = await inventarioRepo.calcularCostoPromedioPorArticulo(articulos.map((a) => a.id));

      for (final articulo in articulos) {
        final individual = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);
        expect(enLote[articulo.id], individual, reason: 'costo promedio de ${articulo.folio}');
      }

      // Promedio ponderado real, no media simple: 40 a $100 y 20 a $175
      // dan $125, no $137.50. Los artículos por cantidad del dataset son
      // exactamente ese caso.
      final conCosto = [
        for (final a in articulos)
          if (!a.manejaSerie && !a.manejaVariante && enLote[a.id] != null) a,
      ];
      expect(conCosto, isNotEmpty, reason: 'el dataset trae artículos por cantidad con costo capturado');
      for (final a in conCosto) {
        expect(enLote[a.id], 12500, reason: 'promedio ponderado de ${a.folio}');
      }
    });

    test('el promedio ponderado redondea igual en las dos rutas', () async {
      final articulo = await crearArticulo(manejaSerie: false);
      // 3 a $1.00 y 1 a $2.01 -> 501/4 = 125.25 -> 125 centavos.
      await movimiento(articulo.id, TipoMovimientoInventario.entrada, 3, costoUnitario: 100);
      await movimiento(articulo.id, TipoMovimientoInventario.entrada, 1, costoUnitario: 201);

      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id), 125);
      expect((await inventarioRepo.calcularCostoPromedioPorArticulo([articulo.id]))[articulo.id], 125);
    });

    test('un artículo CON variante no tiene costo a nivel de artículo en ninguna de las dos rutas', () async {
      final articulo = await crearArticulo(manejaSerie: false, manejaVariante: true);
      final chica = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'Chica');
      final grande = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'Grande');
      await movimiento(articulo.id, TipoMovimientoInventario.entrada, 10, costoUnitario: 5000, varianteId: chica.id);
      await movimiento(articulo.id, TipoMovimientoInventario.entrada, 10, costoUnitario: 30000, varianteId: grande.id);

      // Un solo número no representaría dos tallas con costos tan
      // distintos: la respuesta correcta es "pregunta por talla", no un
      // promedio inventado entre ellas.
      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id), isNull);
      expect((await inventarioRepo.calcularCostoPromedioPorArticulo([articulo.id])).containsKey(articulo.id), isFalse,
          reason: 'el lote tiene que responder lo mismo que la lectura individual');

      // Por talla sí hay costo, y es el de esa talla.
      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id, varianteId: chica.id), 5000);
      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id, varianteId: grande.id), 30000);
    });

    test('un artículo sin costo capturado no aparece en el mapa — nunca vale 0', () async {
      final articulo = await crearArticulo(manejaSerie: false);
      await movimiento(articulo.id, TipoMovimientoInventario.entrada, 5);

      expect(await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id), isNull);
      expect((await inventarioRepo.calcularCostoPromedioPorArticulo([articulo.id])).containsKey(articulo.id), isFalse);
    });

    test('el resumen completo es idéntico al que producía el bucle por artículo', () async {
      await sembrar(30);

      final legacy = await resumenLegacyPorArticulo(
        articuloRepo: articuloRepo,
        inventarioRepo: inventarioRepo,
        asignacionRepo: asignacionRepo,
      );
      final nuevo = await construirCasoDeUso().ejecutar();

      expect(nuevo.existenciaTotal, legacy.existenciaTotal);
      expect(nuevo.valorAproximado, legacy.valorAproximado);
      expect(nuevo.articulosConValorExcluido, legacy.articulosConValorExcluido);
      expect(nuevo.asignacionesVigentes, legacy.asignacionesVigentes);
      expect(nuevo.danadosPerdidos, legacy.danadosPerdidos);
      expect(nuevo.descuentosPendientes, legacy.descuentosPendientes);
      expect(nuevo.movimientosEnPeriodo, legacy.movimientosEnPeriodo);
      expect(nuevo.unidadesPorEstatus, legacy.unidadesPorEstatus);

      // Y no es un empate vacío: hay cifras que comparar.
      expect(nuevo.existenciaTotal, greaterThan(0));
      expect(nuevo.valorAproximado, greaterThan(0));
      expect(nuevo.articulosConValorExcluido, greaterThan(0));
    });

    test('la base vacía sigue dando ceros, sin reventar', () async {
      final resumen = await construirCasoDeUso().ejecutar();

      expect(resumen.existenciaTotal, 0);
      expect(resumen.valorAproximado, 0);
      expect(resumen.articulosConValorExcluido, 0);
      expect(resumen.unidadesPorEstatus, isEmpty);
      expect(await inventarioRepo.calcularExistenciaPorArticulos(const []), isEmpty);
    });
  });

  group('Complejidad — el número de consultas dejó de depender de los artículos', () {
    /// Cuántas consultas cuesta el resumen para [articulos] artículos.
    Future<int> consultasDelResumen(int articulos) async {
      await sembrar(articulos);
      contador.reiniciar();
      await construirCasoDeUso().ejecutar();
      return contador.selects;
    }

    Future<int> consultasDelLegacy(int articulos) async {
      await sembrar(articulos);
      contador.reiniciar();
      await resumenLegacyPorArticulo(
        articuloRepo: articuloRepo,
        inventarioRepo: inventarioRepo,
        asignacionRepo: asignacionRepo,
      );
      return contador.selects;
    }

    test('el bucle anterior SÍ crecía con el número de artículos', () async {
      final conDiez = await consultasDelLegacy(10);
      expect(conDiez, greaterThanOrEqualTo(10),
          reason: 'el oráculo tiene que seguir siendo el N+1 real, o no prueba nada');
    });

    test('0, 1, 10 y 100 artículos cuestan el mismo número de consultas', () async {
      // Cada tamaño necesita su propia base: el conteo se mide sobre una
      // ejecución limpia.
      final medidas = <int, int>{};
      for (final cantidad in [0, 1, 10, 100]) {
        await db.close();
        contador = ContadorDeConsultas(NativeDatabase.memory());
        db = AppDatabase(contador);
        articuloRepo = ArticuloRepositoryImpl(db);
        inventarioRepo = InventarioRepositoryImpl(db);
        asignacionRepo = AsignacionRepositoryImpl(db);
        consecutivo = 0;
        await db.select(db.articulo).get();

        medidas[cantidad] = await consultasDelResumen(cantidad);
      }

      // La propiedad arquitectónica: constante, no lineal.
      expect(medidas[100], medidas[10],
          reason: 'pasar de 10 a 100 artículos no puede costar ni una consulta más: $medidas');
      // Con UN artículo se lee una tabla menos: el dataset de tamaño 1
      // sólo trae un serializado, así que la consulta de movimientos ni
      // se lanza. Esa diferencia es fija, no proporcional.
      expect(medidas[10]! - medidas[1]!, lessThanOrEqualTo(1), reason: '$medidas');
      // Con la base vacía las tres lecturas en lote ni se lanzan
      // (movimientos, unidades y entradas con costo). Ese es el costo
      // COMPLETO de tener artículos: tres consultas, haya 1 o 100.
      expect(medidas[100]! - medidas[0]!, lessThanOrEqualTo(3),
          reason: 'tener artículos cuesta tres consultas fijas, no tres por artículo: $medidas');
    });

    test('100 artículos cuestan mucho menos que el bucle anterior', () async {
      final enLote = await consultasDelResumen(100);

      await db.close();
      contador = ContadorDeConsultas(NativeDatabase.memory());
      db = AppDatabase(contador);
      articuloRepo = ArticuloRepositoryImpl(db);
      inventarioRepo = InventarioRepositoryImpl(db);
      asignacionRepo = AsignacionRepositoryImpl(db);
      consecutivo = 0;
      await db.select(db.articulo).get();
      final legacy = await consultasDelLegacy(100);

      expect(legacy, greaterThan(100), reason: 'dos consultas por artículo');
      expect(enLote, lessThan(20), reason: 'un puñado fijo: $enLote');
      expect(enLote * 5, lessThan(legacy), reason: 'lote=$enLote legacy=$legacy');
    });

    test('las existencias en lote cuestan dos consultas, haya 1 o 100 artículos', () async {
      final articulos = await sembrar(100);

      contador.reiniciar();
      await inventarioRepo.calcularExistenciaPorArticulos(articulos);
      expect(contador.selects, 2, reason: 'una de movimientos y una de unidades');

      contador.reiniciar();
      await inventarioRepo.calcularExistenciaPorArticulos(articulos.take(1));
      expect(contador.selects, lessThanOrEqualTo(2));

      contador.reiniciar();
      await inventarioRepo.calcularCostoPromedioPorArticulo(articulos.map((a) => a.id));
      expect(contador.selects, 1, reason: 'una sola consulta de entradas');
    });
  });

  group('Volumen — 100 artículos mezclados', () {
    test('el resumen sigue cuadrando contra el bucle artículo por artículo', () async {
      final articulos = await sembrar(100);
      expect(articulos, hasLength(100));

      final legacy = await resumenLegacyPorArticulo(
        articuloRepo: articuloRepo,
        inventarioRepo: inventarioRepo,
        asignacionRepo: asignacionRepo,
      );
      final nuevo = await construirCasoDeUso().ejecutar();

      expect(nuevo.existenciaTotal, legacy.existenciaTotal);
      expect(nuevo.valorAproximado, legacy.valorAproximado);
      expect(nuevo.articulosConValorExcluido, legacy.articulosConValorExcluido);
      expect(nuevo.unidadesPorEstatus, legacy.unidadesPorEstatus);

      // Las 20 series del dataset aportan 3 unidades en proceso cada
      // una: el estado intermedio sigue contando como existencia.
      expect(nuevo.unidadesPorEstatus[EstatusArticuloUnidad.enLavanderia.name], greaterThan(0));
      expect(nuevo.unidadesPorEstatus[EstatusArticuloUnidad.baja.name], greaterThan(0));
    });

    test('existencia y costo de los 100 coinciden uno a uno con la lectura individual', () async {
      final articulos = await sembrar(100);

      final existencias = await inventarioRepo.calcularExistenciaPorArticulos(articulos);
      final costos = await inventarioRepo.calcularCostoPromedioPorArticulo(articulos.map((a) => a.id));

      for (final articulo in articulos) {
        final individual = articulo.manejaSerie
            ? await inventarioRepo.calcularExistenciaUnidades(articulo.id)
            : await inventarioRepo.calcularExistencia(articuloId: articulo.id);
        expect(existencias[articulo.id]!.total, individual.total, reason: articulo.folio);
        expect(existencias[articulo.id]!.disponible, individual.disponible, reason: articulo.folio);
        expect(existencias[articulo.id]!.enProceso, individual.enProceso, reason: articulo.folio);
        expect(costos[articulo.id], await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id),
            reason: articulo.folio);
      }
    });
  });
}
