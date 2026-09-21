import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/obtener_origen_compra_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/regularizar_articulo_serializado_usecase.dart';

/// Cubre la regularización de existencia legacy (Etapa 9D, segundo
/// ajuste posterior) — caso real: "SMARTPHONE" comprado con
/// `manejaSerie: false` por error, que quedó como existencia por
/// cantidad en vez de `ArticuloUnidad`. Verifica: la única excepción
/// controlada a "`manejaSerie` nunca cambia", la división 1:N del
/// movimiento por cantidad sin alterar la existencia total, el
/// re-ligado de `CompraPartidaMovimiento` (Origen sigue navegable), y
/// todas las validaciones que bloquean un uso incorrecto.
void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late CompraRepositoryImpl compraRepo;
  late RegistrarCompraUseCase registrarCompra;
  late RegularizarArticuloSerializadoUseCase regularizar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    regularizar = RegularizarArticuloSerializadoUseCase(articuloRepo, inventarioRepo, generarCodigo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloMalConfigurado({String nombre = 'SMARTPHONE', bool manejaVariante = false}) async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: false,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  group('RegularizarArticuloSerializadoUseCase — caso real (SMARTPHONE vía Compra)', () {
    test('divide la entrada de una Compra en N unidades, marca manejaSerie=true y re-liga el Origen', () async {
      final articulo = await crearArticuloMalConfigurado();

      final compraResultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        proveedor: 'Tienda de teléfonos',
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 179400),
        ],
      );
      final compra = (compraResultado as RegistrarCompraExitosa).compra;
      final movimientoOriginal = (await compraRepo.listarMovimientosGenerados(compra.id)).single;

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimientoOriginal.id,
        unidades: const [
          DatosUnidadRegularizacionInput(numeroSerie: 'SN-REAL-0001', marca: 'Samsung', modelo: 'A15', imei: '111122223333444'),
        ],
      );

      expect(resultado, isA<RegularizarArticuloSerializadoExitoso>());
      final unidad = (resultado as RegularizarArticuloSerializadoExitoso).unidades.single;
      expect(unidad.numeroSerie, 'SN-REAL-0001');
      expect(unidad.marca, 'Samsung');
      expect(unidad.modelo, 'A15');

      final articuloActualizado = await articuloRepo.obtenerPorId(articulo.id);
      expect(articuloActualizado!.manejaSerie, isTrue);

      final movimientos = await db.select(db.movimientoInventario).get();
      expect(movimientos, hasLength(1), reason: 'el movimiento por cantidad original se borra, queda solo el nuevo de unidad');
      expect(movimientos.single.unidadId, unidad.id);
      expect(movimientos.single.cantidad, 1);
      expect(movimientos.single.costoUnitario, 179400, reason: 'preserva el costo del movimiento original');
      expect(movimientos.single.fecha, movimientoOriginal.fecha, reason: 'preserva la fecha del movimiento original');

      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.total, 1, reason: 'la existencia total no cambia con la regularización');

      final origenUseCase = ObtenerOrigenCompraUseCase(compraRepo);
      final origen = await origenUseCase.obtenerParaMovimientos([movimientos.single.id]);
      expect(origen[movimientos.single.id]?.compraId, compra.id, reason: 'el Origen: Compra sigue navegable desde la unidad nueva');

      final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
      expect(telefono?.imei, '111122223333444');
    });

    test('regulariza 2 unidades desde un movimiento cantidad=2, sin cambiar la existencia total', () async {
      final articulo = await crearArticuloMalConfigurado();
      final movimiento = await inventarioRepo.registrarEntrada(
        articuloId: articulo.id,
        cantidad: 2,
        costoUnitario: 100000,
        fecha: DateTime(2026, 1, 1),
      );

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: const [
          DatosUnidadRegularizacionInput(numeroSerie: 'SN-A'),
          DatosUnidadRegularizacionInput(numeroSerie: 'SN-B'),
        ],
      );

      expect(resultado, isA<RegularizarArticuloSerializadoExitoso>());
      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.total, 2);
    });

    test('entrada manual sin Compra asociada: regulariza igual, sin Origen (no falla al no encontrar puente)', () async {
      final articulo = await crearArticuloMalConfigurado();
      final movimiento = await inventarioRepo.registrarEntrada(
        articuloId: articulo.id,
        cantidad: 1,
        fecha: DateTime(2026, 1, 1),
      );

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: const [DatosUnidadRegularizacionInput(numeroSerie: 'SN-MANUAL')],
      );

      expect(resultado, isA<RegularizarArticuloSerializadoExitoso>());
    });
  });

  group('RegularizarArticuloSerializadoUseCase — validaciones', () {
    test('rechaza un Artículo inexistente', () async {
      final resultado = await regularizar.ejecutar(
        articuloId: 'no-existe',
        movimientoInventarioId: 'no-existe',
        unidades: const [],
      );
      expect(resultado, isA<RegularizarArticuloSerializadoArticuloNoExiste>());
    });

    test('rechaza un Artículo que ya maneja serie (nada que regularizar)', () async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
      final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
      final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final articulo = ((await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Ya serializado', manejaVariante: false, manejaSerie: true)) as CrearArticuloExitoso).articulo;

      final resultado = await regularizar.ejecutar(articuloId: articulo.id, movimientoInventarioId: 'x', unidades: const []);
      expect(resultado, isA<RegularizarArticuloSerializadoArticuloYaManejaSerie>());
    });

    test('rechaza un Artículo con variante (fuera de alcance)', () async {
      final articulo = await crearArticuloMalConfigurado(manejaVariante: true);
      final resultado = await regularizar.ejecutar(articuloId: articulo.id, movimientoInventarioId: 'x', unidades: const []);
      expect(resultado, isA<RegularizarArticuloSerializadoArticuloManejaVariante>());
    });

    test('rechaza un movimiento inexistente', () async {
      final articulo = await crearArticuloMalConfigurado();
      final resultado = await regularizar.ejecutar(articuloId: articulo.id, movimientoInventarioId: 'no-existe', unidades: const []);
      expect(resultado, isA<RegularizarArticuloSerializadoMovimientoNoExiste>());
    });

    test('rechaza un movimiento que no es entrada (ej. baja)', () async {
      final articulo = await crearArticuloMalConfigurado();
      await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final baja = await inventarioRepo.registrarBaja(articuloId: articulo.id, cantidad: 1, observaciones: 'merma');

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: baja.id,
        unidades: const [DatosUnidadRegularizacionInput(numeroSerie: 'SN-X')],
      );
      expect(resultado, isA<RegularizarArticuloSerializadoMovimientoNoElegible>());
    });

    test('rechaza un movimiento de otro Artículo', () async {
      final articuloA = await crearArticuloMalConfigurado(nombre: 'A');
      final articuloB = await crearArticuloMalConfigurado(nombre: 'B');
      final movimientoB = await inventarioRepo.registrarEntrada(articuloId: articuloB.id, cantidad: 1, fecha: DateTime(2026, 1, 1));

      final resultado = await regularizar.ejecutar(
        articuloId: articuloA.id,
        movimientoInventarioId: movimientoB.id,
        unidades: const [DatosUnidadRegularizacionInput(numeroSerie: 'SN-X')],
      );
      expect(resultado, isA<RegularizarArticuloSerializadoMovimientoNoElegible>());
    });

    test('rechaza cuando la cantidad de unidades capturadas no coincide con la cantidad del movimiento', () async {
      final articulo = await crearArticuloMalConfigurado();
      final movimiento = await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 2, fecha: DateTime(2026, 1, 1));

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: const [DatosUnidadRegularizacionInput(numeroSerie: 'SN-UNICA')],
      );
      expect(resultado, isA<RegularizarArticuloSerializadoCantidadNoCoincide>());
    });

    test('rechaza número de serie vacío', () async {
      final articulo = await crearArticuloMalConfigurado();
      final movimiento = await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 1, 1));

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: const [DatosUnidadRegularizacionInput(numeroSerie: '  ')],
      );
      expect(resultado, isA<RegularizarArticuloSerializadoNumeroSerieRequerido>());
    });

    test('rechaza números de serie duplicados dentro de la misma captura', () async {
      final articulo = await crearArticuloMalConfigurado();
      final movimiento = await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 2, fecha: DateTime(2026, 1, 1));

      final resultado = await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: const [
          DatosUnidadRegularizacionInput(numeroSerie: 'SN-REPETIDO'),
          DatosUnidadRegularizacionInput(numeroSerie: 'SN-REPETIDO'),
        ],
      );
      expect(resultado, isA<RegularizarArticuloSerializadoNumeroSerieDuplicado>());
    });

    test('no crea ninguna unidad ni toca manejaSerie cuando la validación falla', () async {
      final articulo = await crearArticuloMalConfigurado();
      final movimiento = await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 2, fecha: DateTime(2026, 1, 1));

      await regularizar.ejecutar(
        articuloId: articulo.id,
        movimientoInventarioId: movimiento.id,
        unidades: const [DatosUnidadRegularizacionInput(numeroSerie: 'SN-UNICA')],
      );

      final articuloTrasFallo = await articuloRepo.obtenerPorId(articulo.id);
      expect(articuloTrasFallo!.manejaSerie, isFalse);
      final unidades = await db.select(db.articuloUnidad).get();
      expect(unidades, isEmpty);
      final movimientos = await db.select(db.movimientoInventario).get();
      expect(movimientos, hasLength(1), reason: 'el movimiento original sigue intacto');
    });
  });
}
