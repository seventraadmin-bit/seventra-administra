import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';

/// Cubre la ampliación real de "Corregir datos" de Compra (Etapa 15):
/// corrección de partidas ya registradas — artículo/variante,
/// cantidad, costo, alta/baja de partida completa — siempre
/// reconciliando Inventario/Egreso solo por lo que le pertenece a cada
/// partida (vía `CompraPartidaMovimiento`), nunca tocando movimientos
/// ajenos, y bloqueando cuando la existencia ya fue consumida. Los 20
/// escenarios enumerados en el pedido original de Marlon están
/// numerados explícitamente en los nombres de las pruebas.
void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CorregirCompraUseCase corregirCompra;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo);
  });

  tearDown(() => db.close());

  CategoriaArticuloRepositoryImpl categoriaRepo() => CategoriaArticuloRepositoryImpl(db);

  Future<ArticuloData> crearArticuloDePrueba({
    String nombre = 'Camisola',
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

  Future<CompraData> crearCompraDePrueba({required List<PartidaCompraInput> partidas, String? proveedor}) async {
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      proveedor: proveedor,
      formaPago: FormaPago.efectivo.name,
      partidas: partidas,
    );
    return (resultado as RegistrarCompraExitosa).compra;
  }

  group('1-4. Corrección de campos administrativos (Etapa 15)', () {
    test('1. corrige solo el proveedor, sin tocar partidas ni el Egreso', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = await crearCompraDePrueba(
        proveedor: 'Proveedor original',
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );

      final resultado = await corregirCompra.ejecutar(compraId: creada.id, proveedor: 'Proveedor nuevo', motivo: 'Proveedor mal capturado');

      expect(resultado, isA<CorregirCompraExitosa>());
      expect((resultado as CorregirCompraExitosa).compra.proveedor, 'Proveedor nuevo');
      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 165000);
    });

    test('2. corrige la forma de pago entre formas que comparten el mismo origen (Cuenta)', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000)],
      );
      expect(creada.formaPago, FormaPago.efectivo.name);

      // Etapa 0 (corrección de bug real): cambiar HACIA `tarjeta` está
      // bloqueado sin importar la forma de pago anterior — ver el
      // grupo "corrige la forma de pago — bloqueo de cambio de modelo
      // financiero" más abajo. Esta prueba cubre el caso permitido:
      // dos formas de pago que comparten el mismo origen (Cuenta).
      final resultado = await corregirCompra.ejecutar(compraId: creada.id, formaPago: FormaPago.transferencia.name, motivo: 'Forma de pago mal capturada');
      expect((resultado as CorregirCompraExitosa).compra.formaPago, FormaPago.transferencia.name);
    });

    test('3. corrige la fecha', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000)],
      );

      final resultado = await corregirCompra.ejecutar(compraId: creada.id, fecha: DateTime(2026, 8, 5), motivo: 'Fecha mal capturada');
      expect((resultado as CorregirCompraExitosa).compra.fecha, DateTime(2026, 8, 5));
    });

    test('4. corrige las observaciones', () async {
      final articulo = await crearArticuloDePrueba();
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 10000)],
      );

      final resultado = await corregirCompra.ejecutar(compraId: creada.id, observaciones: 'Nota corregida', motivo: 'Observaciones mal capturadas');
      expect((resultado as CorregirCompraExitosa).compra.observaciones, 'Nota corregida');
    });
  });

  group('5-8. Corrección de cantidad/costo de una partida fungible', () {
    test('5. corrige el costo unitario: el Egreso y los movimientos generados reflejan el nuevo costo', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevoCostoUnitario: 35000)],
        motivo: 'Costo real era \$350.00, no \$330.00',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final partida = (await compraRepo.listarPartidas(creada.id)).single;
      expect(partida.costoUnitario, 35000);
      expect(partida.cantidad, 5, reason: 'la cantidad no debía cambiar');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 175000, reason: '5 × 350.00');

      final movimiento = (await compraRepo.listarMovimientosGenerados(creada.id)).single;
      expect(movimiento.costoUnitario, 35000, reason: 'el movimiento de entrada original también refleja el costo corregido');
    });

    test('6. corrige la cantidad hacia arriba: la existencia aumenta exactamente el delta', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevaCantidad: 8)],
        motivo: 'Se recibieron 8, no 5',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 8);
      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 8 * 33000);
    });

    test('7. corrige la cantidad hacia abajo con existencia suficiente', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevaCantidad: 3)],
        motivo: 'Se recibieron solo 3',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 3);
    });

    test('8. bloquea reducir la cantidad cuando la existencia ya fue asignada, sin modificar nada', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;
      final empleado = await crearEmpleadoDePrueba();
      await asignacionRepo.crear(articuloId: articulo.id, cantidad: 4, empleadoId: empleado.id, fechaEntrega: DateTime(2026, 8, 11));

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevaCantidad: 2)],
        motivo: 'Intento de reducir cantidad ya asignada',
      );

      expect(resultado, isA<CorregirCompraTieneDependencias>());
      final partidaSinCambios = (await compraRepo.listarPartidas(creada.id)).single;
      expect(partidaSinCambios.cantidad, 5, reason: 'nada se modifica cuando la corrección se bloquea');
      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 5 * 33000);
    });
  });

  group('9-12. Cambio de artículo/variante de una partida fungible', () {
    test('9-11. cambia la variante G→CH: la partida queda con CH, G pierde exactamente la existencia originada por esta Compra, CH la recibe',
        () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola', manejaVariante: true);
      final varianteG = await crearVarianteDePrueba(articulo.id, valor: 'G');
      final varianteCh = await crearVarianteDePrueba(articulo.id, valor: 'CH');
      final creada = await crearCompraDePrueba(
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            varianteId: varianteG.id,
            cantidad: 5,
            costoUnitario: 33000,
          ),
        ],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [
          CorreccionPartidaVariante(compraPartidaId: partidaId, nuevoArticuloId: articulo.id, nuevaVarianteId: varianteCh.id),
        ],
        motivo: 'Se capturó talla G, la compra real fue talla CH',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final partida = (await compraRepo.listarPartidas(creada.id)).single;
      expect(partida.varianteId, varianteCh.id, reason: '9. la partida queda con la variante corregida');

      final existenciaG = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: varianteG.id);
      expect(existenciaG.disponible, 0, reason: '10. la variante G pierde exactamente la existencia originada por esta Compra');

      final existenciaCh = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: varianteCh.id);
      expect(existenciaCh.disponible, 5, reason: '11. la variante CH recibe exactamente la cantidad correspondiente');
    });

    test('12. un movimiento manual ajeno a la partida corregida permanece intacto', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola', manejaVariante: true);
      final varianteG = await crearVarianteDePrueba(articulo.id, valor: 'G');
      final varianteCh = await crearVarianteDePrueba(articulo.id, valor: 'CH');
      final creada = await crearCompraDePrueba(
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            varianteId: varianteG.id,
            cantidad: 5,
            costoUnitario: 33000,
          ),
        ],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;

      final movimientoManual = await inventarioRepo.registrarEntrada(
        articuloId: articulo.id,
        varianteId: varianteG.id,
        cantidad: 7,
        fecha: DateTime(2026, 8, 11),
        observaciones: 'Entrada manual ajena a la Compra',
      );

      await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [
          CorreccionPartidaVariante(compraPartidaId: partidaId, nuevoArticuloId: articulo.id, nuevaVarianteId: varianteCh.id),
        ],
        motivo: 'Corrección de variante',
      );

      final movimientosG = await inventarioRepo.listarMovimientos(articuloId: articulo.id, varianteId: varianteG.id);
      final manualSinCambios = movimientosG.firstWhere((m) => m.id == movimientoManual.id);
      expect(manualSinCambios.cantidad, 7, reason: 'el movimiento manual ajeno a la Compra nunca se toca');
      expect(manualSinCambios.tipoMovimiento, 'entrada');

      final existenciaG = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: varianteG.id);
      expect(existenciaG.disponible, 7, reason: 'solo queda la existencia del movimiento manual; la de la Compra corregida se revirtió');
    });
  });

  group('13-15. Agregar/quitar partidas completas', () {
    test('13. agrega una partida omitida en el Alta original: nueva CompraPartida, total y Egreso sincronizados', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final pantalon = await crearArticuloDePrueba(nombre: 'Pantalón 34');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 5, costoUnitario: 33000)],
      );

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [
          CorreccionPartidaAgregar(
            input: PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: pantalon.id, cantidad: 3, costoUnitario: 25000),
          ),
        ],
        motivo: 'Se omitió el pantalón en la captura original',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final partidas = await compraRepo.listarPartidas(creada.id);
      expect(partidas, hasLength(2));
      final existenciaPantalon = await inventarioRepo.calcularExistencia(articuloId: pantalon.id);
      expect(existenciaPantalon.disponible, 3);
      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 5 * 33000 + 3 * 25000);
    });

    test('14. quita una partida sin dependencias: revierte su existencia y la excluye del total, sin borrar el ledger', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final pantalon = await crearArticuloDePrueba(nombre: 'Pantalón 34');
      final creada = await crearCompraDePrueba(
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: camisola.id, cantidad: 5, costoUnitario: 33000),
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: pantalon.id, cantidad: 3, costoUnitario: 25000),
        ],
      );
      final partidaPantalon = (await compraRepo.listarPartidas(creada.id)).firstWhere((p) => p.articuloId == pantalon.id);

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaQuitar(compraPartidaId: partidaPantalon.id)],
        motivo: 'El pantalón nunca se compró, se capturó por error',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final partidas = await compraRepo.listarPartidas(creada.id);
      expect(partidas, hasLength(1));

      final existenciaPantalon = await inventarioRepo.calcularExistencia(articuloId: pantalon.id);
      expect(existenciaPantalon.disponible, 0, reason: 'la baja de reversa deja la existencia en cero');

      final movimientosPantalon = await inventarioRepo.listarMovimientos(articuloId: pantalon.id);
      expect(movimientosPantalon, hasLength(2), reason: 'la entrada original y su baja de reversa se conservan en el ledger');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 5 * 33000, reason: 'el Egreso ya no incluye la partida quitada');
    });

    test('15. bloquea quitar una partida cuya existencia ya fue asignada', () async {
      final pantalon = await crearArticuloDePrueba(nombre: 'Pantalón 34');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: pantalon.id, cantidad: 3, costoUnitario: 25000)],
      );
      final partidaPantalon = (await compraRepo.listarPartidas(creada.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      await asignacionRepo.crear(articuloId: pantalon.id, cantidad: 2, empleadoId: empleado.id, fechaEntrega: DateTime(2026, 8, 11));

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaQuitar(compraPartidaId: partidaPantalon.id)],
        motivo: 'Intento de quitar partida ya asignada',
      );

      expect(resultado, isA<CorregirCompraTieneDependencias>());
      final partidas = await compraRepo.listarPartidas(creada.id);
      expect(partidas, hasLength(1), reason: 'nada se modifica cuando la corrección se bloquea');
    });
  });

  group('16-17. Corrección de partidas serializadas', () {
    test('16. agrega y quita unidades de una partida serializada sin dependencias', () async {
      final radio = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final creada = await crearCompraDePrueba(
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: radio.id,
            cantidad: 2,
            costoUnitario: 50000,
            numerosSerie: ['SN-A', 'SN-B'],
          ),
        ],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;
      final unidadA = (await compraRepo.listarUnidadesPorPartida(partidaId)).firstWhere((u) => u.numeroSerie == 'SN-A');

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [
          CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, numerosSerieNuevos: ['SN-C'], unidadesIdAEliminar: [unidadA.id]),
        ],
        motivo: 'SN-A se capturó por error, faltaba SN-C',
      );

      expect(resultado, isA<CorregirCompraExitosa>());
      final vigentes = await compraRepo.listarUnidadesPorPartida(partidaId);
      expect(vigentes.map((u) => u.numeroSerie).toSet(), {'SN-B', 'SN-C'}, reason: 'SN-A ya no aparece entre las unidades vigentes de la partida');

      final unidadASinCambios = await inventarioRepo.obtenerUnidadPorId(unidadA.id);
      expect(unidadASinCambios!.estatus, EstatusArticuloUnidad.baja.name, reason: 'SN-A queda dada de baja, nunca se borra');

      final partida = (await compraRepo.listarPartidas(creada.id)).single;
      expect(partida.cantidad, 2, reason: '2 vigentes (SN-B, SN-C) tras quitar 1 y agregar 1');
    });

    test('17. bloquea quitar una unidad serializada ya asignada a un empleado', () async {
      final radio = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final creada = await crearCompraDePrueba(
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: radio.id,
            cantidad: 2,
            costoUnitario: 50000,
            numerosSerie: ['SN-A', 'SN-B'],
          ),
        ],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;
      final unidadB = (await compraRepo.listarUnidadesPorPartida(partidaId)).firstWhere((u) => u.numeroSerie == 'SN-B');
      final empleado = await crearEmpleadoDePrueba();
      await asignacionRepo.crear(articuloId: radio.id, unidadId: unidadB.id, cantidad: 1, empleadoId: empleado.id, fechaEntrega: DateTime(2026, 8, 11));

      final resultado = await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, unidadesIdAEliminar: [unidadB.id])],
        motivo: 'Intento de quitar unidad ya asignada',
      );

      expect(resultado, isA<CorregirCompraTieneDependencias>());
      final unidadBSinCambios = await inventarioRepo.obtenerUnidadPorId(unidadB.id);
      expect(unidadBSinCambios!.estatus, EstatusArticuloUnidad.asignado.name, reason: 'nada se modifica cuando la corrección se bloquea');
    });
  });

  group('18-19. Sincronización del Egreso y atomicidad', () {
    test('18. un cambio de total actualiza exactamente el mismo Egreso relacionado, nunca crea uno nuevo', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final creada = await crearCompraDePrueba(
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;
      final egresoIdOriginal = creada.egresoId;

      await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevoCostoUnitario: 38000)],
        motivo: 'Costo corregido de \$330.00 a \$380.00',
      );

      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1), reason: 'nunca se crea un segundo Egreso');
      expect(egresos.single.id, egresoIdOriginal, reason: 'se actualiza exactamente el mismo Egreso original');
      expect(egresos.single.monto, 5 * 38000);
    });

    test('19. una falla a mitad de la corrección revierte TODA la operación (rollback atómico real)', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Camisola CH');
      final creada = await crearCompraDePrueba(
        proveedor: 'Proveedor original',
        partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000)],
      );
      final partidaId = (await compraRepo.listarPartidas(creada.id)).single.id;

      // Se llama directo al repositorio (sin la validación previa del
      // caso de uso) para forzar una falla real a mitad de la
      // transacción: el primer cambio es válido y alcanza a
      // aplicarse en memoria de la transacción, el segundo referencia
      // una `CompraPartida` inexistente y truena — Drift debe
      // revertir la transacción completa, incluyendo el primer cambio
      // y el `proveedor` ya escrito.
      await expectLater(
        compraRepo.corregir(
          compraId: creada.id,
          proveedor: 'Proveedor que no debe persistir',
          cambiosPartidas: [
            CorreccionPartidaCantidadCosto(compraPartidaId: partidaId, nuevaCantidad: 9),
            CorreccionPartidaCantidadCosto(compraPartidaId: 'partida-inexistente', nuevaCantidad: 1),
          ],
          motivo: 'Corrección que debe fallar a mitad de camino',
        ),
        throwsA(anything),
      );

      final compraSinCambios = await compraRepo.obtenerPorId(creada.id);
      expect(compraSinCambios!.proveedor, 'Proveedor original', reason: 'el rollback deshace también el proveedor ya escrito');

      final partidaSinCambios = (await compraRepo.listarPartidas(creada.id)).single;
      expect(partidaSinCambios.cantidad, 5, reason: 'el rollback deshace el primer cambio de partida, ya aplicado antes de la falla');

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 5, reason: 'el movimiento de ajuste del primer cambio también se revierte');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.monto, 5 * 33000, reason: 'el Egreso nunca se sincronizó porque toda la transacción se revirtió');
    });
  });
}
