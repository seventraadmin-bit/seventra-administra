// Etapa 15 — Eliminación física de Compra (Maestro), patrón exacto de
// la Etapa 11D. Cubre: sin historia (gastoDirecto e inventario simple,
// serializado), elegible aunque ya esté cancelada, su propio Egreso se
// elimina junto con ella (nunca un bloqueo), y bloqueo real por
// historia posterior (Asignacion sobre la variante/unidad generada).

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CancelarCompraUseCase cancelarCompra;
  late EliminarCompraFisicamenteUseCase eliminarCompra;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, generarCodigo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
    eliminarCompra = EliminarCompraFisicamenteUseCase(compraRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloDePrueba({
    String nombre = 'Camisola',
    bool manejaVariante = false,
    bool manejaSerie = false,
  }) async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    final categoria = (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: manejaSerie,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba() {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  group('Compra sin historia posterior', () {
    test('Maestro elimina físicamente una Compra de gasto directo, incluyendo su Egreso', () async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final egresoId = compra.egresoId!;

      final r = await eliminarCompra.ejecutar(
        compraId: compra.id,
        motivo: 'Compra de prueba, nunca fue real',
        actorUsuarioId: 'usuario-maestro',
      );

      expect(r, isA<EliminarCompraFisicamenteExitoso>());
      expect(await compraRepo.obtenerPorId(compra.id), isNull);
      final egresoSigueExistiendo = await (db.select(db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull();
      expect(egresoSigueExistiendo, isNull, reason: 'el Egreso propio se elimina junto con la Compra, nunca es un bloqueo');
    });

    test('Compra con entrada de Inventario simple (sin variante) sin asignaciones es elegible', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final r = await eliminarCompra.ejecutar(compraId: compra.id, motivo: 'prueba', actorUsuarioId: 'usuario-maestro');

      expect(r, isA<EliminarCompraFisicamenteExitoso>());
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 0, reason: 'la entrada generada se elimina junto con la Compra');
    });

    test('Compra serializada sin asignar a nadie es elegible', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 1,
            costoUnitario: 250000,
            numerosSerie: const ['SN-0001'],
          ),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final unidades = await compraRepo.listarUnidadesGeneradas(compra.id);
      expect(unidades, hasLength(1));

      final r = await eliminarCompra.ejecutar(compraId: compra.id, motivo: 'prueba', actorUsuarioId: 'usuario-maestro');

      expect(r, isA<EliminarCompraFisicamenteExitoso>());
      final unidadSigueExistiendo =
          await (db.select(db.articuloUnidad)..where((t) => t.id.equals(unidades.single.id))).getSingleOrNull();
      expect(unidadSigueExistiendo, isNull);
    });

    test('una Compra ya cancelada también es elegible (caso real: limpiar captura de prueba)', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 2, costoUnitario: 33000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final cancelacion = await cancelarCompra.ejecutar(compraId: compra.id, motivo: 'Duplicada por error');
      expect(cancelacion, isA<CancelarCompraExitosa>());

      final r = await eliminarCompra.ejecutar(compraId: compra.id, motivo: 'limpieza de prueba', actorUsuarioId: 'usuario-maestro');
      expect(r, isA<EliminarCompraFisicamenteExitoso>());
    });

    test('exige motivo', () async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final r = await eliminarCompra.ejecutar(compraId: compra.id, motivo: '   ');
      expect(r, isA<EliminarCompraFisicamenteMotivoRequerido>());
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull);
    });

    test('rechaza una Compra inexistente', () async {
      final r = await eliminarCompra.ejecutar(compraId: 'no-existe', motivo: 'cualquiera');
      expect(r, isA<EliminarCompraFisicamenteNoExiste>());
    });
  });

  group('Compra con historia posterior real — siempre bloqueada', () {
    test('rechaza si el artículo por cantidad recibido ya tiene una Asignacion registrada', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final empleado = await crearEmpleadoDePrueba();
      final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
      await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 2,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      );

      final r = await eliminarCompra.ejecutar(compraId: compra.id, motivo: 'intento', actorUsuarioId: 'usuario-maestro');

      expect(r, isA<EliminarCompraFisicamenteTieneDependencias>());
      expect((r as EliminarCompraFisicamenteTieneDependencias).detalle, contains('asignaciones registradas'));
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull, reason: 'nunca se elimina cuando está bloqueado');
    });

    test('rechaza si la unidad serializada generada ya fue asignada a un empleado', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 1,
            costoUnitario: 250000,
            numerosSerie: const ['SN-0002'],
          ),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final unidad = (await compraRepo.listarUnidadesGeneradas(compra.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
      await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      );

      final r = await eliminarCompra.ejecutar(compraId: compra.id, motivo: 'intento', actorUsuarioId: 'usuario-maestro');

      expect(r, isA<EliminarCompraFisicamenteTieneDependencias>());
      expect((r as EliminarCompraFisicamenteTieneDependencias).detalle, contains(unidad.codigo));
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull);
    });
  });
}
