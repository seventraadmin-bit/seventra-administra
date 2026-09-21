// Etapa 15 — "Eliminar cadena de prueba" de Compra (Maestro). A
// diferencia de `EliminarCompraFisicamenteUseCase` (bloquea ante
// CUALQUIER historia posterior), esta acción SÍ elimina la cadena
// derivada completa (Asignación/movimientos/descuento) — pero
// EXCLUSIVAMENTE por relación exacta de IDs, y solo si nada cruzó un
// punto irreversible real.
//
// Para SERIALIZADOS la atribución es directa (`unidadId`). Para POR
// CANTIDAD (fungible) — caso real reportado por Marlon (COM-000022,
// PANTALON NEGRO COMANDO) — la atribución se demuestra por
// reconciliación agregada: si esta Compra es el ÚNICO origen de
// existencia de ese artículo/variante (ninguna otra Compra ni ajuste de
// entrada) y no hay ninguna baja/ajuste de salida manual, CUALQUIER
// Asignación sobre ese artículo/variante queda demostrada por
// eliminación — ver el doc comment de `_motivoBloqueoAtribucionFungible`
// en `CompraRepositoryImpl`. Si cualquiera de las dos condiciones falla,
// bloquea exactamente igual que la eliminación física normal — nunca se
// relaja por debajo de eso.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/eliminar_cadena_prueba_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/data/tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late RegistrarCompraUseCase registrarCompra;
  late EliminarCadenaPruebaCompraUseCase eliminarCadenaPrueba;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late EliminarNominaFisicamenteUseCase eliminarNomina;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    eliminarCadenaPrueba = EliminarCadenaPruebaCompraUseCase(compraRepo);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);

    nominaRepo = NominaRepositoryImpl(db, asignacionRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina =
        GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    eliminarNomina = EliminarNominaFisicamenteUseCase(nominaRepo);

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

  var empleadoContador = 0;
  Future<EmpleadoData> crearEmpleadoDePrueba({int sueldoMensualAdministrativo = 1500000}) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: empleadoContador,
            nombres: 'Empleado$n',
            apellidoPaterno: 'Apellido$n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX$n',
            rfc: 'PEXJ900101$n',
            nss: '100000000$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  var articuloContador = 0;
  Future<ArticuloData> crearArticuloDePrueba({bool manejaSerie = false}) async {
    articuloContador++;
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final categoria =
        (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Categoria$articuloContador') as CrearCategoriaArticuloExitoso).categoria;
    final resultado = await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
      categoriaId: categoria.id,
      nombre: 'PANTALON NEGRO COMANDO $articuloContador',
      manejaVariante: false,
      manejaSerie: manejaSerie,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<CompraData> comprarUnidadSerializada(ArticuloData articulo, String serie) async {
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(
          destino: DestinoCompraPartida.inventario.name,
          articuloId: articulo.id,
          cantidad: 1,
          costoUnitario: 20000,
          numerosSerie: [serie],
        ),
      ],
    );
    return (resultado as RegistrarCompraExitosa).compra;
  }

  group('Eliminar cadena de prueba — casos permitidos (unidad serializada)', () {
    test('Compra sin historia posterior: el resumen no reporta nada por limpiar y la eliminación normal ya basta', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0001');

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isFalse);
      expect(resumen.entradasInventario, 1);
      expect(resumen.asignaciones, isEmpty, reason: 'sin ninguna Asignación/movimiento derivado por limpiar');
      expect(resumen.descuentosPendientes, 0);
    });

    test('Compra con asignación: la eliminación física normal queda bloqueada, la cadena de prueba SÍ es elegible', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0002');
      final unidad = (await compraRepo.listarUnidadesGeneradas(compra.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidad.id, cantidad: 1, empleadoId: empleado.id, fechaEntrega: DateTime(2026, 8, 11));

      final resumenNormal = await compraRepo.obtenerResumenEliminacionFisica(compra.id);
      expect(resumenNormal.bloqueado, isTrue, reason: 'la eliminación normal SÍ debe seguir bloqueada');

      final resumenCadena = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumenCadena.bloqueado, isFalse, reason: 'la cadena de prueba es la alternativa segura');
      expect(resumenCadena.asignaciones, hasLength(1));
    });

    test('elimina entrada, asignación, movimientos derivados y Egreso relacionados — todo junto', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0003');
      final egresoId = compra.egresoId!;
      final unidad = (await compraRepo.listarUnidadesGeneradas(compra.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      final asignacionCreada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacionCreada.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 8, 12),
      );

      final r = await eliminarCadenaPrueba.ejecutar(
        compraId: compra.id,
        motivo: MotivoCadenaPruebaCompra.pruebaFuncional,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      expect(await compraRepo.obtenerPorId(compra.id), isNull);
      expect(await (db.select(db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull(), isNull);
      expect(await (db.select(db.articuloUnidad)..where((t) => t.id.equals(unidad.id))).getSingleOrNull(), isNull);
      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacionCreada.id))).getSingleOrNull(), isNull);
      final movimientosRestantes = await (db.select(db.movimientoInventario)..where((t) => t.unidadId.equals(unidad.id))).get();
      expect(movimientosRestantes, isEmpty, reason: 'la entrada original y la devolución derivada se eliminan juntas');

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 0, reason: 'Inventario queda exactamente como antes de crear la prueba');
      expect(existencia.disponible, greaterThanOrEqualTo(0), reason: 'nunca una existencia negativa');
    });

    test('si existe un DescuentoInventario pendiente derivado, también se limpia', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0004');
      final unidad = (await compraRepo.listarUnidadesGeneradas(compra.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      final asignacionCreada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacionCreada.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 8, 12),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleado.id,
      );
      final descuento = (await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id)).single;
      expect(descuento.estatus, EstatusDescuentoInventario.pendiente.name);

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isFalse);
      expect(resumen.descuentosPendientes, 1);
      expect(resumen.totalDescuentosPendientes, 20000);

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      expect(await (db.select(db.descuentoInventario)..where((t) => t.id.equals(descuento.id))).getSingleOrNull(), isNull);
    });
  });

  group('Eliminar cadena de prueba — puntos irreversibles: bloquean TODO, nada se toca', () {
    test('descuento ya Aplicado en una Nómina Borrador bloquea la cadena completa (nada se elimina)', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0005');
      final unidad = (await compraRepo.listarUnidadesGeneradas(compra.id)).single;
      final empleado = await crearEmpleadoDePrueba();
      final asignacionCreada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacionCreada.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 8, 12),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleado.id,
      );

      final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
      final descuento = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
      expect(descuento.estatus, EstatusDescuentoInventario.aplicado.name);

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains('aplicado'));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraTieneDependencias>());

      // Todo o nada: nada se tocó.
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull);
      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacionCreada.id))).getSingleOrNull(), isNotNull);
      expect(await (db.select(db.descuentoInventario)..where((t) => t.id.equals(descuento.id))).getSingleOrNull(), isNotNull);

      // Tras resolver del lado de Nómina (Borrador → eliminación física
      // real, ya revierte el descuento a pendiente), la cadena de
      // prueba de la Compra sí procede.
      final eliminacionNomina = await eliminarNomina.ejecutar(
        nominaId: nomina.id,
        motivo: MotivoEliminacionFisicaNomina.nominaDePrueba,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(eliminacionNomina, isA<EliminarNominaFisicamenteExitoso>());

      final resumenTrasResolver = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumenTrasResolver.bloqueado, isFalse);

      final r2 = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r2, isA<EliminarCadenaPruebaCompraExitoso>());
    });

    test('artículo por cantidad con una baja/ajuste manual ajeno posterior sigue bloqueado — no es reversible', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      // Un ajuste manual de salida (merma/conteo) no tiene ninguna
      // `Asignacion` detrás — "Eliminar cadena de prueba" no sabe cómo
      // desandarlo, así que bloquea aunque el origen sí sea único.
      final ajuste = await RegistrarAjusteUseCase(inventarioRepo, articuloRepo).ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        esEntrada: false,
        observaciones: 'Merma detectada en conteo físico',
      );
      expect(ajuste, isA<RegistrarAjusteExitoso>());

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains('baja o un ajuste manual'));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraTieneDependencias>());
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull);
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 4, reason: 'nada se tocó — el ajuste manual sigue vigente');
    });

    test('dos Compras diferentes del mismo artículo: la existencia mezclada bloquea limpiar cualquiera de las dos', () async {
      final articulo = await crearArticuloDePrueba();
      final resultadoA = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 3, costoUnitario: 33000),
        ],
      );
      final compraA = (resultadoA as RegistrarCompraExitosa).compra;
      final resultadoB = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 12),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 2, costoUnitario: 33000),
        ],
      );
      final compraB = (resultadoB as RegistrarCompraExitosa).compra;

      final resumenA = await eliminarCadenaPrueba.obtenerResumen(compraA.id);
      expect(resumenA.bloqueado, isTrue);
      expect(resumenA.detalleBloqueo, contains('otro origen'));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compraA.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraTieneDependencias>());

      // Ninguna de las dos se toca — el pool está mezclado, sin forma
      // de saber cuánto pertenece a cada una.
      expect(await compraRepo.obtenerPorId(compraA.id), isNotNull);
      expect(await compraRepo.obtenerPorId(compraB.id), isNotNull);
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 5, reason: 'las dos Compras siguen intactas');
    });

    test('existencia previa (de otro origen, no de esta Compra) bloquea y permanece intacta', () async {
      final articulo = await crearArticuloDePrueba();
      // Existencia previa NO originada por ninguna Compra (ej.: alta
      // inicial de inventario existente al adoptar el sistema).
      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 8, 1));

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 20000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains('otro origen'));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraTieneDependencias>());
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 11, reason: 'la existencia previa (10) + la de esta Compra (1) permanecen intactas');
    });
  });

  group('Eliminar cadena de prueba — por cantidad (fungible): atribución demostrable', () {
    test('Compra +1 → asignación de 1 → devolución → eliminar cadena limpia todo y regresa exactamente al estado previo', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 20000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final egresoId = compra.egresoId!;
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(asignacionId: asignacion.id, motivo: MotivoCierreAsignacion.desgaste, fechaCierre: DateTime(2026, 8, 12));

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isFalse);
      expect(resumen.asignaciones, hasLength(1));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      expect(await compraRepo.obtenerPorId(compra.id), isNull);
      expect(await (db.select(db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull(), isNull);
      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacion.id))).getSingleOrNull(), isNull);
      final movimientosRestantes = await (db.select(db.movimientoInventario)..where((t) => t.articuloId.equals(articulo.id))).get();
      expect(movimientosRestantes, isEmpty);

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 0);
      expect(existencia.disponible, 0);
      expect(existencia.asignado, 0);
      expect(existencia.danado, 0);
      expect(existencia.perdido, 0);
    });

    test('Compra +1 → asignación → daño → descuento pendiente → eliminar cadena limpia todo incluyendo el descuento', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 20000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 8, 12),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleado.id,
      );
      final descuento = (await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id)).single;

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isFalse);
      expect(resumen.descuentosPendientes, 1);
      expect(resumen.totalDescuentosPendientes, 20000);

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      expect(await (db.select(db.descuentoInventario)..where((t) => t.id.equals(descuento.id))).getSingleOrNull(), isNull);
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 0);
      expect(existencia.danado, 0);
    });

    test('Compra +N con movimientos completamente atribuibles (varias asignaciones) se limpia correctamente', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 33000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final empleadoA = await crearEmpleadoDePrueba();
      final empleadoB = await crearEmpleadoDePrueba();
      final asignacionA = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 2,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      final asignacionB = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 3,
        empleadoId: empleadoB.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(asignacionId: asignacionA.id, motivo: MotivoCierreAsignacion.desgaste, fechaCierre: DateTime(2026, 8, 12));
      // asignacionB se queda activa — también debe limpiarse.

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isFalse);
      expect(resumen.asignaciones, hasLength(2));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacionA.id))).getSingleOrNull(), isNull);
      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacionB.id))).getSingleOrNull(), isNull);
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 0);
      expect(existencia.asignado, 0);
    });

    test('cantidad parcialmente utilizada (parte sigue disponible, sin otro origen): atribución demostrable, se limpia', () async {
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
      await crearAsignacion.ejecutar(articuloId: articulo.id, cantidad: 2, empleadoId: empleado.id, fechaEntrega: DateTime(2026, 8, 11));
      // Las otras 3 unidades siguen disponibles, sin usarse — también
      // son atribuibles (mismo origen único) y deben limpiarse.

      final existenciaAntes = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existenciaAntes.disponible, 3);
      expect(existenciaAntes.asignado, 2);

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isFalse, reason: 'origen único, sin ambigüedad, aunque solo parte se haya usado');

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      final existenciaDespues = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existenciaDespues.total, 0);
      expect(existenciaDespues.disponible, 0);
    });

    test('descuento fungible ya Aplicado en una Nómina sigue bloqueando la cadena completa', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 1, costoUnitario: 20000),
        ],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 8, 12),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleado.id,
      );

      final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
      final descuento = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
      expect(descuento.estatus, EstatusDescuentoInventario.aplicado.name);

      final resumen = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains('aplicado'));

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraTieneDependencias>());
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull);
      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacion.id))).getSingleOrNull(), isNotNull);

      // Igual que en lo serializado: resolver desde el lado de Nómina
      // desbloquea la cadena de la Compra.
      final eliminacionNomina = await eliminarNomina.ejecutar(nominaId: nomina.id, motivo: MotivoEliminacionFisicaNomina.nominaDePrueba);
      expect(eliminacionNomina, isA<EliminarNominaFisicamenteExitoso>());

      final resumenTrasResolver = await eliminarCadenaPrueba.obtenerResumen(compra.id);
      expect(resumenTrasResolver.bloqueado, isFalse);
      final r2 = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r2, isA<EliminarCadenaPruebaCompraExitoso>());
    });
  });

  group('Eliminar cadena de prueba — aislamiento exacto (nunca por coincidencia)', () {
    test('no toca asignaciones/unidades de OTRA Compra del mismo artículo ni de otro empleado', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compraA = await comprarUnidadSerializada(articulo, 'SN-A-0001');
      final compraB = await comprarUnidadSerializada(articulo, 'SN-B-0001');
      final unidadA = (await compraRepo.listarUnidadesGeneradas(compraA.id)).single;
      final unidadB = (await compraRepo.listarUnidadesGeneradas(compraB.id)).single;
      final empleadoA = await crearEmpleadoDePrueba();
      final empleadoB = await crearEmpleadoDePrueba();

      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidadA.id, cantidad: 1, empleadoId: empleadoA.id, fechaEntrega: DateTime(2026, 8, 11));
      final asignacionB = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidadB.id,
        cantidad: 1,
        empleadoId: empleadoB.id,
        fechaEntrega: DateTime(2026, 8, 11),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final r = await eliminarCadenaPrueba.ejecutar(compraId: compraA.id, motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      expect(await compraRepo.obtenerPorId(compraA.id), isNull);
      expect(await compraRepo.obtenerPorId(compraB.id), isNotNull, reason: 'la Compra B es ajena, nunca debe tocarse');
      expect(await (db.select(db.articuloUnidad)..where((t) => t.id.equals(unidadB.id))).getSingleOrNull(), isNotNull);
      expect(await (db.select(db.asignacion)..where((t) => t.id.equals(asignacionB.id))).getSingleOrNull(), isNotNull);

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 1, reason: 'solo queda la unidad B, intacta');
    });
  });

  group('Eliminar cadena de prueba — motivo y auditoría', () {
    test('motivo "Otro" sin detalle se rechaza', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0006');
      final r = await eliminarCadenaPrueba.ejecutar(compraId: compra.id, motivo: MotivoCadenaPruebaCompra.otro);
      expect(r, isA<EliminarCadenaPruebaCompraDetalleRequerido>());
      expect(await compraRepo.obtenerPorId(compra.id), isNotNull);
    });

    test('rechaza una Compra inexistente', () async {
      final r = await eliminarCadenaPrueba.ejecutar(compraId: 'no-existe', motivo: MotivoCadenaPruebaCompra.pruebaFuncional);
      expect(r, isA<EliminarCadenaPruebaCompraNoExiste>());
    });

    test('la auditoría (EliminacionFisicaEvento) sobrevive a la Compra eliminada, sin FK a lo borrado', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final compra = await comprarUnidadSerializada(articulo, 'SN-0007');

      final r = await eliminarCadenaPrueba.ejecutar(
        compraId: compra.id,
        motivo: MotivoCadenaPruebaCompra.pruebaDeIntegracion,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(r, isA<EliminarCadenaPruebaCompraExitoso>());

      final evento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(compra.id))).getSingleOrNull();
      expect(evento, isNotNull);
      expect(evento!.tipoEntidad, 'compra');
      expect(evento.motivoCodigo, MotivoCadenaPruebaCompra.pruebaDeIntegracion.name);
      expect(evento.actorUsuarioId, 'usuario-maestro');
      expect(evento.snapshotJson, contains(compra.folioCompra));
    });
  });
}
