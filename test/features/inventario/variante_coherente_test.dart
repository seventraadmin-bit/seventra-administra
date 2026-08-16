// Etapa 15 — reproducción real del bug reportado: CAMISOLA mostraba
// Total general 1/Disponible 1 pero el desglose por talla mostraba
// CH/EXG/G/M/XXG todos en 0. Diagnóstico confirmado directo sobre la
// base real (solo lectura): NO existía ningún `MovimientoInventario`
// con `varianteId == null` para ningún artículo con variante — los 3
// movimientos de CAMISOLA tenían todos un `varianteId` real y válido,
// y el recálculo manual replicando `calcularExistencia` daba CH=1,
// resto=0, exactamente coincidente con el Total general. La
// inconsistencia reportada no tenía origen en los datos ni en la
// lógica de cálculo — la causa más probable es que la app corriendo
// en ese momento no tenía compilado el cambio de desglose por
// variante todavía (`riseg_one.exe` requiere recompilar tras cambios
// de Dart, no hace hot-reload fuera de una sesión `flutter run`).
//
// Aun así, el pedido explícito de Marlon (regla 3) es blindar el
// dominio para que esta clase de inconsistencia sea estructuralmente
// imposible en el futuro: un movimiento por cantidad de un Artículo
// con variante SIEMPRE debe traer `varianteId`, sin importar el
// llamador. Esta prueba cubre esa invariante en cada punto de entrada
// real (`registrarEntrada`/`registrarBaja`/`registrarAjuste`,
// directo en el repositorio — el mismo punto que usa la composición
// interna de `CompraRepositoryImpl`, que nunca pasa por los casos de
// uso de UI) y confirma que ningún intento bloqueado deja rastro.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticulo(String nombre, {required bool manejaVariante}) async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso)
        .categoria;
    final resultado = await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: false,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  group('Artículo CON variante — varianteId nulo siempre se rechaza', () {
    test('registrarEntrada con varianteId null lanza VarianteInvalidaException y no inserta nada', () async {
      final articulo = await crearArticulo('CAMISOLA', manejaVariante: true);
      await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');

      expect(
        () => inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 8, 13)),
        throwsA(isA<VarianteInvalidaException>()),
      );

      final movimientos = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(movimientos, isEmpty, reason: 'el intento bloqueado no debe dejar ningún movimiento huérfano');
    });

    test('registrarBaja con varianteId null lanza VarianteInvalidaException, incluso con existencia real en otra variante', () async {
      final articulo = await crearArticulo('CAMISOLA', manejaVariante: true);
      final ch = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');
      await inventarioRepo.registrarEntrada(articuloId: articulo.id, varianteId: ch.id, cantidad: 5, fecha: DateTime(2026, 8, 13));

      expect(
        () => inventarioRepo.registrarBaja(articuloId: articulo.id, cantidad: 1, observaciones: 'Prueba'),
        throwsA(isA<VarianteInvalidaException>()),
      );

      final existenciaCh = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: ch.id);
      expect(existenciaCh.disponible, 5, reason: 'el intento bloqueado no debe afectar la existencia real');
    });

    test('registrarAjuste (entrada y salida) con varianteId null lanza VarianteInvalidaException', () async {
      final articulo = await crearArticulo('CAMISOLA', manejaVariante: true);
      await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');

      expect(
        () => inventarioRepo.registrarAjuste(articuloId: articulo.id, cantidad: 1, esEntrada: true, observaciones: 'Conteo'),
        throwsA(isA<VarianteInvalidaException>()),
      );
      expect(
        () => inventarioRepo.registrarAjuste(articuloId: articulo.id, cantidad: 1, esEntrada: false, observaciones: 'Conteo'),
        throwsA(isA<VarianteInvalidaException>()),
      );
    });

    test('la composición interna de Compra (sin pasar por RegistrarCompraUseCase) también queda bloqueada — '
        'ningún caller puede saltarse la invariante', () async {
      final articulo = await crearArticulo('CAMISOLA', manejaVariante: true);
      await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');
      final egresoRepo = EgresoRepositoryImpl(db);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);

      // Llamado directo al repositorio, como si un caller nuevo se
      // olvidara de validar `varianteId` antes — exactamente el
      // escenario que la Etapa 15 pide impedir estructuralmente.
      await expectLater(
        compraRepo.crear(
          folioCompra: 'COM-TEST-0001',
          fecha: DateTime(2026, 8, 13),
          formaPago: FormaPago.efectivo.name,
          partidas: [
            PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 33000),
          ],
        ),
        throwsA(isA<VarianteInvalidaException>()),
      );

      // Nada debe haber quedado a medias: ni Compra, ni Egreso, ni
      // movimiento — la transacción completa se revierte.
      final compras = await compraRepo.listar();
      expect(compras, isEmpty, reason: 'la transacción de Compra debe revertirse por completo');
      final movimientos = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(movimientos, isEmpty);
    });
  });

  group('Artículo SIN variante — varianteId provisto siempre se rechaza (invariante inversa)', () {
    test('registrarEntrada con varianteId no nulo para un artículo sin variante lanza VarianteInvalidaException', () async {
      final articuloConVariante = await crearArticulo('CAMISOLA', manejaVariante: true);
      final varianteAjena = await articuloRepo.crearVariante(articuloId: articuloConVariante.id, valor: 'CH');
      final articuloSinVariante = await crearArticulo('GUANTES', manejaVariante: false);

      expect(
        () => inventarioRepo.registrarEntrada(
          articuloId: articuloSinVariante.id,
          varianteId: varianteAjena.id,
          cantidad: 1,
          fecha: DateTime(2026, 8, 13),
        ),
        throwsA(isA<VarianteInvalidaException>()),
      );
    });
  });

  group('Invariante Total general = suma de variantes (cierre, con datos válidos reales)', () {
    test('para cualquier combinación de movimientos válidos, el Total general nunca difiere de la suma de sus variantes', () async {
      final articulo = await crearArticulo('CAMISOLA', manejaVariante: true);
      final ch = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'CH');
      final g = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'G');
      final m = await articuloRepo.crearVariante(articuloId: articulo.id, valor: 'M');

      await inventarioRepo.registrarEntrada(articuloId: articulo.id, varianteId: ch.id, cantidad: 3, fecha: DateTime(2026, 8, 13));
      await inventarioRepo.registrarEntrada(articuloId: articulo.id, varianteId: g.id, cantidad: 2, fecha: DateTime(2026, 8, 13));
      await inventarioRepo.registrarBaja(articuloId: articulo.id, varianteId: ch.id, cantidad: 1, observaciones: 'Prueba');
      await inventarioRepo.registrarAjuste(articuloId: articulo.id, varianteId: m.id, cantidad: 4, esEntrada: true, observaciones: 'Conteo');

      final general = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      var suma = 0;
      for (final varianteId in [ch.id, g.id, m.id]) {
        suma += (await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: varianteId)).total;
      }

      expect(general.total, suma);
      expect(general.total, 8, reason: '3-1 (CH) + 2 (G) + 4 (M)');
    });
  });
}
