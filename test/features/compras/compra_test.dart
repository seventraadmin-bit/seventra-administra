import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';

/// Cubre el dominio Compras (Etapa 10) — captura una sola vez que
/// genera automáticamente las entradas de Inventario y exactamente un
/// Egreso por Compra. Verifica en particular: partidas mixtas
/// (Inventario + Gasto directo) sin doble código de suma, artículos
/// serializados (N unidades por partida), la trazabilidad "Origen:
/// Compra" hacia Inventario, y la reversión estructurada al cancelar
/// (nunca edita el histórico, bloquea si alguna unidad generada ya no
/// está disponible).
void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl inventarioAsignacionRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CorregirCompraUseCase corregirCompra;
  late CancelarCompraUseCase cancelarCompra;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    inventarioAsignacionRepo = AsignacionRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, generarCodigo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
  });

  tearDown(() => db.close());

  CategoriaArticuloRepositoryImpl categoriaRepo() => CategoriaArticuloRepositoryImpl(db);

  Future<ArticuloData> crearArticuloDePrueba({
    String nombre = 'Camisola CH',
    bool manejaVariante = false,
    bool manejaSerie = false,
  }) async {
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo());
    final categoria = (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo(), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: manejaSerie,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<ArticuloVarianteData> crearVarianteDePrueba(String articuloId, {String valor = 'CH'}) {
    return articuloRepo.crearVariante(articuloId: articuloId, valor: valor);
  }

  Future<EmpleadoData> crearEmpleadoDePrueba({int numeroEmpleado = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numeroEmpleado,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numeroEmpleado',
            rfc: 'PEXJ900101AB$numeroEmpleado',
            nss: '1234567890$numeroEmpleado',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  group('RegistrarCompraUseCase — partida de Inventario', () {
    test('registra una compra con una partida de inventario simple', () async {
      final articulo = await crearArticuloDePrueba();

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        proveedor: 'Uniformes del Centro',
        formaPago: FormaPago.tarjeta.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 10,
            costoUnitario: 18000,
          ),
        ],
      );

      expect(resultado, isA<RegistrarCompraExitosa>());
      final compra = (resultado as RegistrarCompraExitosa).compra;
      expect(compra.folioCompra, 'COM-000001');
      expect(compra.proveedor, 'Uniformes del Centro');
      expect(compra.egresoId, isNotNull);

      final movimientos = await compraRepo.listarMovimientosGenerados(compra.id);
      expect(movimientos, hasLength(1));
      expect(movimientos.single.cantidad, 10);
      expect(movimientos.single.costoUnitario, 18000);
      expect(movimientos.single.tipoMovimiento, 'entrada');

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 10, reason: 'la entrada generada por la Compra es la misma que produciría registrarEntrada directo');
    });

    test('genera exactamente un Egreso por el monto total de la partida', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 10, costoUnitario: 18000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.id, compra.egresoId);
      expect(egreso.monto, 180000);
      expect(egreso.folioEgreso, 'EGR-000001');
      expect(egreso.concepto, contains(compra.folioCompra));
    });

    test('partida con variante trae varianteId en el movimiento', () async {
      final articulo = await crearArticuloDePrueba(manejaVariante: true);
      final variante = await crearVarianteDePrueba(articulo.id);

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            varianteId: variante.id,
            cantidad: 5,
            costoUnitario: 25000,
          ),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final movimientos = await compraRepo.listarMovimientosGenerados(compra.id);
      expect(movimientos.single.varianteId, variante.id);
    });

    test('rechaza variante inválida (artículo no maneja variante pero se envía una)', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            varianteId: 'variante-inexistente',
            cantidad: 5,
            costoUnitario: 25000,
          ),
        ],
      );
      expect(resultado, isA<RegistrarCompraPartidaVarianteInvalida>());
    });

    test('rechaza artículo inexistente', () async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: 'no-existe', cantidad: 1, costoUnitario: 100),
        ],
      );
      expect(resultado, isA<RegistrarCompraPartidaArticuloNoExiste>());
    });
  });

  group('RegistrarCompraUseCase — artículos serializados', () {
    test('partida serializada con cantidad 3 genera 3 ArticuloUnidad y 3 MovimientoInventario', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.transferencia.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 3,
            costoUnitario: 50000,
            numerosSerie: ['SN-001', 'SN-002', 'SN-003'],
            marca: 'Motorola',
          ),
        ],
      );

      expect(resultado, isA<RegistrarCompraExitosa>());
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final movimientos = await compraRepo.listarMovimientosGenerados(compra.id);
      expect(movimientos, hasLength(3));
      expect(movimientos.every((m) => m.cantidad == 1), isTrue);

      final unidades = await compraRepo.listarUnidadesGeneradas(compra.id);
      expect(unidades, hasLength(3));
      expect(unidades.map((u) => u.numeroSerie).toSet(), {'SN-001', 'SN-002', 'SN-003'});
      expect(unidades.every((u) => u.estatus == EstatusArticuloUnidad.disponible.name), isTrue);
      expect(unidades.every((u) => u.marca == 'Motorola'), isTrue);

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 150000);
    });

    test('rechaza números de serie duplicados dentro de la misma partida', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 2,
            costoUnitario: 50000,
            numerosSerie: ['SN-001', 'SN-001'],
          ),
        ],
      );
      expect(resultado, isA<RegistrarCompraPartidaNumerosSerieInvalidos>());
    });

    test('rechaza cantidad de series distinta a la cantidad de la partida', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 3,
            costoUnitario: 50000,
            numerosSerie: ['SN-001', 'SN-002'],
          ),
        ],
      );
      expect(resultado, isA<RegistrarCompraPartidaNumerosSerieInvalidos>());
    });
  });

  group('RegistrarCompraUseCase — Gasto directo y partidas mixtas', () {
    test('partida de gasto directo no genera MovimientoInventario pero sí cuenta hacia el Egreso', () async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
        ],
      );
      expect(resultado, isA<RegistrarCompraExitosa>());
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final movimientos = await compraRepo.listarMovimientosGenerados(compra.id);
      expect(movimientos, isEmpty);

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 45000);
    });

    test('rechaza gasto directo sin concepto', () async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, cantidad: 1, costoUnitario: 45000),
        ],
      );
      expect(resultado, isA<RegistrarCompraPartidaConceptoRequerido>());
    });

    test('compra mixta: un solo Egreso suma ambas partidas, solo la de inventario genera movimiento', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final pantalon = await crearArticuloDePrueba(nombre: 'Pantalón 34');

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        proveedor: 'Uniformes del Centro',
        formaPago: FormaPago.tarjeta.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 10, costoUnitario: 18000),
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: pantalon.id, cantidad: 5, costoUnitario: 25000),
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Bolsa/empaque', cantidad: 1, costoUnitario: 10000),
        ],
      );

      expect(resultado, isA<RegistrarCompraExitosa>());
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final total = await compraRepo.calcularTotal(compra.id);
      expect(total, 315000, reason: '10×180 + 5×250 + 1×100 = 3,150.00');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 315000);

      final movimientos = await compraRepo.listarMovimientosGenerados(compra.id);
      expect(movimientos, hasLength(2), reason: 'solo las 2 partidas de inventario generan movimiento, el gasto directo no');
    });

    test('rechaza una compra sin partidas', () async {
      final resultado = await registrarCompra.ejecutar(fecha: DateTime(2026, 8, 10), formaPago: FormaPago.efectivo.name, partidas: []);
      expect(resultado, isA<RegistrarCompraListaVacia>());
    });

    test('folios de Compra y Egreso son secuenciales', () async {
      final articulo = await crearArticuloDePrueba();
      Future<RegistrarCompraResultado> registrar() => registrarCompra.ejecutar(
            fecha: DateTime(2026, 8, 10),
            formaPago: FormaPago.efectivo.name,
            partidas: [
              PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 100),
            ],
          );
      await registrar();
      await registrar();

      final compras = await compraRepo.listar();
      expect(compras.map((c) => c.folioCompra).toSet(), {'COM-000001', 'COM-000002'});

      final egresos = await db.select(db.egreso).get();
      expect(egresos.map((e) => e.folioEgreso).toSet(), {'EGR-000001', 'EGR-000002'});
    });

    test('forma de pago "otro" exige descripción', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.otro.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 100),
        ],
      );
      expect(resultado, isA<RegistrarCompraFormaPagoOtroDescripcionRequerida>());
    });
  });

  group('CorregirCompraUseCase', () {
    test('corrige campos administrativos sin tocar partidas ni el monto del Egreso', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        proveedor: 'Proveedor original',
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        proveedor: 'Proveedor correcto',
        motivo: 'Error de captura',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      expect((resultado as CorregirCompraExitosa).compra.proveedor, 'Proveedor correcto');

      final partidas = await compraRepo.listarPartidas(creada.id);
      expect(partidas.single.cantidad, 1, reason: 'corregir nunca toca partidas');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 10000, reason: 'corregir nunca toca el monto del Egreso');

      final eventos = await compraRepo.listarEventos(creada.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['registrada', 'corregida']));
    });

    test('rechaza corregir una Compra cancelada', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;
      await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Cancelación de prueba');

      final resultado = await corregirCompra.ejecutar(compraId: creada.id, proveedor: 'x', motivo: 'y');
      expect(resultado, isA<CorregirCompraCancelada>());
    });
  });

  group('CancelarCompraUseCase', () {
    test('cancela: revierte Inventario con movimientos baja, cancela el Egreso, conserva el histórico original', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 10, costoUnitario: 18000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      final resultado = await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Devolución al proveedor');
      expect(resultado, isA<CancelarCompraExitosa>());

      final compraCancelada = (resultado as CancelarCompraExitosa).compra;
      expect(compraCancelada.estatus, 'cancelada');
      expect(compraCancelada.motivoCancelacion, 'Devolución al proveedor');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'cancelado');

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 0, reason: 'la baja compensatoria revierte la existencia');

      final movimientosDelArticulo = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(movimientosDelArticulo, hasLength(2), reason: 'el movimiento entrada original sigue existiendo, más el baja compensatorio');
      expect(movimientosDelArticulo.map((m) => m.tipoMovimiento), containsAll(['entrada', 'baja']));

      final entradaOriginal = movimientosDelArticulo.firstWhere((m) => m.tipoMovimiento == 'entrada');
      expect(entradaOriginal.cantidad, 10, reason: 'el movimiento entrada original nunca se edita');
    });

    test('cancela una compra serializada: cada unidad queda en estatus baja, no en disponible', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 2,
            costoUnitario: 50000,
            numerosSerie: ['SN-100', 'SN-101'],
          ),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Compra duplicada por error');

      final unidades = await compraRepo.listarUnidadesGeneradas(creada.id);
      expect(unidades.every((u) => u.estatus == EstatusArticuloUnidad.baja.name), isTrue);
    });

    test('bloquea la cancelación si una unidad generada ya está asignada, sin modificar nada', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 1,
            costoUnitario: 50000,
            numerosSerie: ['SN-200'],
          ),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      final unidad = (await compraRepo.listarUnidadesGeneradas(creada.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      );

      final resultado = await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Intento de cancelación');
      expect(resultado, isA<CancelarCompraBloqueadaPorUnidadesNoDisponibles>());
      final unidadesBloqueantes = (resultado as CancelarCompraBloqueadaPorUnidadesNoDisponibles).unidades;
      expect(unidadesBloqueantes.single.id, unidad.id);

      final compraSinCambios = await compraRepo.obtenerPorId(creada.id);
      expect(compraSinCambios!.estatus, 'registrada', reason: 'nada se modifica cuando la cancelación se bloquea');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'registrado');

      final movimientosDelArticulo = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(movimientosDelArticulo.where((m) => m.tipoMovimiento == 'baja'), isEmpty);
    });

    test('rechaza cancelar una Compra ya cancelada', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;
      await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Primera cancelación');

      final resultado = await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Segunda cancelación');
      expect(resultado, isA<CancelarCompraYaCancelada>());
    });

    test('cancelar una compra de solo gasto directo cancela únicamente el Egreso', () async {
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      final resultado = await cancelarCompra.ejecutar(compraId: creada.id, motivo: 'Ya no se necesitaba');
      expect(resultado, isA<CancelarCompraExitosa>());

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'cancelado');
    });
  });

  group('Origen navegable (Compra → MovimientoInventario)', () {
    test('obtenerOrigenPorMovimiento resuelve el folio correcto', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;
      final movimiento = (await compraRepo.listarMovimientosGenerados(creada.id)).single;

      final origen = await compraRepo.obtenerOrigenPorMovimiento(movimiento.id);
      expect(origen, isNotNull);
      expect(origen!.compraId, creada.id);
      expect(origen.folioCompra, creada.folioCompra);
    });

    test('un movimiento que no vino de una Compra no resuelve origen', () async {
      final articulo = await crearArticuloDePrueba();
      final movimiento = await inventarioRepo.registrarEntrada(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 8, 10));

      final origen = await compraRepo.obtenerOrigenPorMovimiento(movimiento.id);
      expect(origen, isNull);
    });
  });

  group('Reportes — filtros y total en rango', () {
    test('filtra por rango de fechas, folio, proveedor y estatus', () async {
      final articulo = await crearArticuloDePrueba();
      Future<CompraData> registrar(DateTime fecha, String proveedor) async {
        final r = await registrarCompra.ejecutar(
          fecha: fecha,
          proveedor: proveedor,
          formaPago: FormaPago.efectivo.name,
          partidas: [
            PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000),
          ],
        );
        return (r as RegistrarCompraExitosa).compra;
      }

      await registrar(DateTime(2026, 6, 1), 'Office Depot');
      final compraJulio = await registrar(DateTime(2026, 7, 15), 'Mercado Libre');
      await registrar(DateTime(2026, 8, 1), 'Office Depot');

      final porRango = await compraRepo.listar(desde: DateTime(2026, 7, 1), hasta: DateTime(2026, 7, 31));
      expect(porRango, hasLength(1));
      expect(porRango.single.id, compraJulio.id);

      final porProveedor = await compraRepo.listar(proveedor: 'Office');
      expect(porProveedor, hasLength(2));

      final porFolio = await compraRepo.listar(folio: compraJulio.folioCompra);
      expect(porFolio, hasLength(1));
      expect(porFolio.single.id, compraJulio.id);
    });

    test('total comprado en rango excluye Compras canceladas', () async {
      final articulo = await crearArticuloDePrueba();
      final r1 = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 5),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 20000),
        ],
      );
      final r2 = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 6),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 30000),
        ],
      );
      final compra2 = (r2 as RegistrarCompraExitosa).compra;
      await cancelarCompra.ejecutar(compraId: compra2.id, motivo: 'Cancelada');

      final total = await compraRepo.totalCompradoEnRango(desde: DateTime(2026, 8, 1), hasta: DateTime(2026, 8, 31));
      expect(total, 20000, reason: 'la Compra cancelada no cuenta hacia el total');
      expect(r1, isA<RegistrarCompraExitosa>());
    });
  });

  group('Comprobante opcional', () {
    test('una Compra sin comprobante sigue siendo válida', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000),
        ],
      );
      expect(resultado, isA<RegistrarCompraExitosa>());
    });
  });
}
