// Etapa 15 — desglose de existencia por talla/variante en el
// expediente del Artículo. Cubre el cálculo (nunca contadores
// duplicados, siempre derivado de `MovimientoInventario` vía
// `calcularExistencia`) para un artículo con varias variantes
// (CAMISOLA: CH/EXG/G/M/XXG, el caso real reportado), verificando
// explícitamente: la invariante Total general = suma de variantes, que
// una operación sobre una variante nunca toca otra (entrada, baja,
// ajuste, Compra, cancelación, eliminación física), y que la
// validación de baja/ajuste-salida es siempre contra el disponible de
// ESA variante, nunca el global del artículo.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/eliminar_compra_fisicamente_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late CompraRepositoryImpl compraRepo;
  late RegistrarEntradaUseCase registrarEntrada;
  late RegistrarBajaUseCase registrarBaja;
  late RegistrarAjusteUseCase registrarAjuste;
  late RegistrarCompraUseCase registrarCompra;
  late CancelarCompraUseCase cancelarCompra;
  late EliminarCompraFisicamenteUseCase eliminarCompraFisicamente;

  late ArticuloData camisola;
  late String ch, exg, g, m, xxg;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    registrarBaja = RegistrarBajaUseCase(inventarioRepo, articuloRepo);
    registrarAjuste = RegistrarAjusteUseCase(inventarioRepo, articuloRepo);
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, generarCodigo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
    eliminarCompraFisicamente = EliminarCompraFisicamenteUseCase(compraRepo);

    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
        .categoria;
    camisola = ((await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
      categoriaId: categoria.id,
      nombre: 'CAMISOLA',
      manejaVariante: true,
      manejaSerie: false,
    )) as CrearArticuloExitoso)
        .articulo;
    ch = (await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'CH')).id;
    exg = (await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'EXG')).id;
    g = (await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'G')).id;
    m = (await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'M')).id;
    xxg = (await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'XXG')).id;
  });

  tearDown(() => db.close());

  Future<int> disponible(String varianteId) async =>
      (await inventarioRepo.calcularExistencia(articuloId: camisola.id, varianteId: varianteId)).disponible;

  test('Total general del artículo es exactamente la suma del Total de cada variante', () async {
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: ch, cantidad: 1, fecha: DateTime(2026, 8, 12));
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: g, cantidad: 3, fecha: DateTime(2026, 8, 12));
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: m, cantidad: 2, fecha: DateTime(2026, 8, 12));

    final general = await inventarioRepo.calcularExistencia(articuloId: camisola.id);
    var sumaTotal = 0;
    var sumaDisponible = 0;
    var sumaDanado = 0;
    var sumaPerdido = 0;
    for (final varianteId in [ch, exg, g, m, xxg]) {
      final e = await inventarioRepo.calcularExistencia(articuloId: camisola.id, varianteId: varianteId);
      sumaTotal += e.total;
      sumaDisponible += e.disponible;
      sumaDanado += e.danado;
      sumaPerdido += e.perdido;
    }

    expect(general.total, sumaTotal);
    expect(general.disponible, sumaDisponible);
    expect(general.danado, sumaDanado);
    expect(general.perdido, sumaPerdido);
    expect(general.total, 6);
  });

  test('entrada/baja/ajuste en CH nunca modifican la existencia de EXG/G/M/XXG', () async {
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: g, cantidad: 10, fecha: DateTime(2026, 8, 12));
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: ch, cantidad: 5, fecha: DateTime(2026, 8, 12));

    await registrarBaja.ejecutar(articuloId: camisola.id, varianteId: ch, cantidad: 2, observaciones: 'Prenda dañada');
    await registrarAjuste.ejecutar(
      articuloId: camisola.id,
      varianteId: ch,
      cantidad: 1,
      esEntrada: true,
      observaciones: 'Conteo físico',
    );

    expect(await disponible(ch), 4, reason: '5 - 2 + 1');
    expect(await disponible(g), 10, reason: 'nunca debe cambiar por operaciones sobre CH');
    expect(await disponible(exg), 0);
    expect(await disponible(m), 0);
    expect(await disponible(xxg), 0);
  });

  test('baja de CH queda bloqueada aunque G tenga existencia, con el disponible real de CH (no el global) en el resultado', () async {
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: g, cantidad: 10, fecha: DateTime(2026, 8, 12));
    // CH permanece en 0 — nunca se registró entrada para esa variante.

    final resultado = await registrarBaja.ejecutar(articuloId: camisola.id, varianteId: ch, cantidad: 1, observaciones: 'Prueba');

    expect(resultado, isA<RegistrarBajaSobrepasaDisponible>());
    expect((resultado as RegistrarBajaSobrepasaDisponible).disponible, 0, reason: 'el disponible de CH, no el global (10 en G)');
    expect(await disponible(ch), 0);
    expect(await disponible(g), 10, reason: 'el intento bloqueado sobre CH no debe tocar G');
  });

  test('Compra, cancelación y eliminación física en variante CH nunca afectan G/M/EXG/XXG', () async {
    await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: g, cantidad: 10, fecha: DateTime(2026, 8, 12));

    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 12),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, varianteId: ch, cantidad: 1, costoUnitario: 33000),
      ],
    );
    final compra = (resultado as RegistrarCompraExitosa).compra;
    expect(await disponible(ch), 1);
    expect(await disponible(g), 10, reason: 'la Compra de CH no debe tocar G');

    await cancelarCompra.ejecutar(compraId: compra.id, motivo: 'Prueba');
    expect(await disponible(ch), 0);
    expect(await disponible(g), 10, reason: 'cancelar la Compra de CH no debe tocar G');

    await eliminarCompraFisicamente.ejecutar(compraId: compra.id, motivo: 'Limpieza');
    expect(await disponible(ch), 0);
    expect(await disponible(g), 10, reason: 'eliminar físicamente la Compra de CH no debe tocar G');
    expect(await disponible(exg), 0);
    expect(await disponible(m), 0);
    expect(await disponible(xxg), 0);
  });
}
