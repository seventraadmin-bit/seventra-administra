// Etapa 15 — reproducción real del bug reportado: CAMISOLA-CH quedó
// en Total -1 / Disponible -1 tras una secuencia de Compra+cancelar
// repetida y eliminación física. Causa raíz confirmada inspeccionando
// la base real: `CompraRepositoryImpl.cancelar()` generaba su baja de
// reversa SIN vincularla a `CompraPartidaMovimiento` — al eliminar
// físicamente la Compra ya cancelada, `eliminarFisicamente` borraba la
// entrada (la única que sí conocía) pero nunca la baja de reversa,
// dejándola huérfana y la existencia en negativo.
//
// Esta prueba cubre los 9 casos pedidos: entrada manual, baja manual
// válida/bloqueada por 0/bloqueada por exceso, Compra+cancelación
// exacta a 0, cancelación idempotente, aislamiento por variante,
// eliminación física sin baja compensatoria nueva, y la invariante de
// dominio (nunca negativo) tanto por el caso de uso como directo en el
// repositorio.

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
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';
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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    registrarBaja = RegistrarBajaUseCase(inventarioRepo, articuloRepo);
    registrarAjuste = RegistrarAjusteUseCase(inventarioRepo, articuloRepo);
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
    eliminarCompraFisicamente = EliminarCompraFisicamenteUseCase(compraRepo);
  });

  tearDown(() => db.close());

  Future<(ArticuloData, ArticuloVarianteData, ArticuloVarianteData)> crearCamisolaCHyG() async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    final categoria = (await crearCategoria.ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final articulo = ((await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: 'CAMISOLA',
      manejaVariante: true,
      manejaSerie: false,
    )) as CrearArticuloExitoso)
        .articulo;
    final ch = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');
    final g = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'G');
    return (articulo, ch, g);
  }

  test('1. entrada manual +1 refleja existencia real', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    final resultado = await registrarEntrada.ejecutar(
      articuloId: articulo.id,
      varianteId: ch.id,
      cantidad: 1,
      fecha: DateTime(2026, 8, 12),
    );
    expect(resultado, isA<RegistrarEntradaExitoso>());
    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 1);
    expect(existencia.total, 1);
  });

  test('2. baja manual válida reduce exactamente la cantidad dada de baja', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 3, fecha: DateTime(2026, 8, 12));

    final resultado =
        await registrarBaja.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, observaciones: 'Prenda dañada');

    expect(resultado, isA<RegistrarBajaExitoso>());
    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 2);
  });

  test('3. baja manual con existencia 0 queda bloqueada con el disponible real en el resultado', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();

    final resultado =
        await registrarBaja.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, observaciones: 'Prueba');

    expect(resultado, isA<RegistrarBajaSobrepasaDisponible>());
    expect((resultado as RegistrarBajaSobrepasaDisponible).disponible, 0);
    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 0, reason: 'el intento bloqueado nunca debe insertar el movimiento');
  });

  test('4. baja mayor a la existencia disponible queda bloqueada', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 2, fecha: DateTime(2026, 8, 12));

    final resultado =
        await registrarBaja.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 3, observaciones: 'Prueba');

    expect(resultado, isA<RegistrarBajaSobrepasaDisponible>());
    expect((resultado as RegistrarBajaSobrepasaDisponible).disponible, 2);
    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 2, reason: 'la existencia no cambia cuando la baja se rechaza');
  });

  test('4b. lo mismo aplica a Ajuste de salida (ajusteSalida)', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, fecha: DateTime(2026, 8, 12));

    final resultado = await registrarAjuste.ejecutar(
      articuloId: articulo.id,
      varianteId: ch.id,
      cantidad: 5,
      esEntrada: false,
      observaciones: 'Conteo físico',
    );

    expect(resultado, isA<RegistrarAjusteSobrepasaDisponible>());
    expect((resultado as RegistrarAjusteSobrepasaDisponible).disponible, 1);
  });

  test('5. Compra +1 y cancelación vuelven exactamente a 0 (nunca -1)', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 12),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, varianteId: ch.id, cantidad: 1, costoUnitario: 33000),
      ],
    );
    final compra = (resultado as RegistrarCompraExitosa).compra;

    var existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 1);

    final cancelacion = await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.compraDePrueba);
    expect(cancelacion, isA<CancelarCompraExitosa>());

    existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 0);
    expect(existencia.total, 0);
  });

  test('6. reintentar cancelar la misma Compra no duplica la reversa (idempotencia)', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 12),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, varianteId: ch.id, cantidad: 1, costoUnitario: 33000),
      ],
    );
    final compra = (resultado as RegistrarCompraExitosa).compra;

    final primeraCancelacion = await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.compraDePrueba);
    expect(primeraCancelacion, isA<CancelarCompraExitosa>());

    // Reintento — simula refrescar/reintentar el flujo de cancelación.
    final segundaCancelacion = await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.compraNoRealizada);
    expect(segundaCancelacion, isA<CancelarCompraYaCancelada>());

    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 0, reason: 'una segunda baja de reversa dejaría esto en -1');

    final movimientos = await inventarioRepo.listarMovimientos(articuloId: articulo.id, varianteId: ch.id);
    expect(movimientos, hasLength(2), reason: 'exactamente una entrada y una baja, nunca dos bajas');
  });

  test('7. Compra de talla CH no afecta la existencia de talla G', () async {
    final (articulo, ch, g) = await crearCamisolaCHyG();
    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: g.id, cantidad: 5, fecha: DateTime(2026, 8, 12));

    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 12),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, varianteId: ch.id, cantidad: 1, costoUnitario: 33000),
      ],
    );
    final compra = (resultado as RegistrarCompraExitosa).compra;
    await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.compraDePrueba);

    final existenciaCh = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    final existenciaG = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: g.id);
    expect(existenciaCh.disponible, 0);
    expect(existenciaG.disponible, 5, reason: 'la Compra/cancelación de CH nunca debe tocar G');
  });

  test('8. eliminación física de una Compra cancelada elimina entrada y reversa juntas, sin generar una baja nueva', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 12),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, varianteId: ch.id, cantidad: 1, costoUnitario: 33000),
      ],
    );
    final compra = (resultado as RegistrarCompraExitosa).compra;
    await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.compraDePrueba);

    final eliminacion = await eliminarCompraFisicamente.ejecutar(
      compraId: compra.id,
      motivo: MotivoEliminacionFisicaCompra.registroDePrueba,
    );
    expect(eliminacion, isA<EliminarCompraFisicamenteExitoso>());

    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 0);
    expect(existencia.total, 0, reason: 'ni la entrada ni su reversa deben sobrevivir');

    final movimientos = await inventarioRepo.listarMovimientos(articuloId: articulo.id, varianteId: ch.id);
    expect(movimientos, isEmpty, reason: 'la eliminación física borra tanto la entrada como su baja de reversa — '
        'nunca deja una huérfana ni genera una nueva');
  });

  test('9. la existencia nunca queda negativa incluso llamando al repositorio directo (invariante de dominio)', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();

    expect(
      () => inventarioRepo.registrarBaja(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, observaciones: 'Prueba'),
      throwsA(isA<ExistenciaInsuficienteException>()),
      reason: 'la protección debe existir en el dominio, no solo en el caso de uso de la UI',
    );

    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, fecha: DateTime(2026, 8, 12));
    expect(
      () => inventarioRepo.registrarAjuste(
        articuloId: articulo.id,
        varianteId: ch.id,
        cantidad: 2,
        esEntrada: false,
        observaciones: 'Prueba',
      ),
      throwsA(isA<ExistenciaInsuficienteException>()),
    );

    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, greaterThanOrEqualTo(0));
  });

  test('9b. dos Compras de la misma variante, ambas canceladas y eliminadas físicamente, terminan exactamente en 0 '
      '(reproduce el incidente real: dos Compras contribuyendo cada una su propia baja de reversa)', () async {
    final (articulo, ch, _) = await crearCamisolaCHyG();

    Future<String> comprarYCancelar() async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 12),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, varianteId: ch.id, cantidad: 1, costoUnitario: 33000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.compraDePrueba);
      return compra.id;
    }

    final compraId1 = await comprarYCancelar();
    final compraId2 = await comprarYCancelar();

    await eliminarCompraFisicamente.ejecutar(compraId: compraId1, motivo: MotivoEliminacionFisicaCompra.registroDePrueba);
    await eliminarCompraFisicamente.ejecutar(compraId: compraId2, motivo: MotivoEliminacionFisicaCompra.registroDePrueba);

    // La entrada manual real que sí debe sobrevivir intacta.
    await registrarEntrada.ejecutar(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, fecha: DateTime(2026, 8, 12));

    final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
    expect(existencia.disponible, 1, reason: 'nunca -1 — el incidente real reproducido y corregido');
  });
}
