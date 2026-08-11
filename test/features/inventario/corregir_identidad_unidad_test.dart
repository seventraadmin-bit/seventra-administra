import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_identidad_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/equipo_telefonico_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';

/// Cubre `CorregirIdentidadUnidadUseCase` (Etapa 9D, tercer ajuste
/// posterior) — corrección de número de serie/marca/modelo/IMEI 1/
/// IMEI 2 de una `ArticuloUnidad` ya existente, cuando se capturó mal
/// al darla de alta (caso real: la Compra de un SMARTPHONE con un
/// número de serie equivocado). Verifica en particular: nunca cambia
/// cantidad/costo/existencia/Compra/Egreso/MovimientoInventario, nunca
/// crea historial falso, conserva asignaciones/línea/credencial
/// existentes (misma unidad física), rechaza duplicados con mensaje
/// entendible, y audita cada campo cambiado con su valor anterior/nuevo.
void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CorregirIdentidadUnidadUseCase corregir;

  const actorId = 'usuario-prueba';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    corregir = CorregirIdentidadUnidadUseCase(inventarioRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value(actorId), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloSerializado({String nombre = 'SMARTPHONE'}) async {
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: nombre, manejaVariante: false, manejaSerie: true);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<ArticuloUnidadData> crearUnidad(
    String articuloId, {
    String numeroSerie = 'SN-MAL-001',
    String? imei,
  }) async {
    final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await registrarEntradaUnidad.ejecutar(
      articuloId: articuloId,
      numeroSerie: numeroSerie,
      imei: imei,
      fecha: DateTime(2026, 1, 1),
      costoUnitario: 179400,
    );
    return (resultado as RegistrarEntradaUnidadExitoso).unidad;
  }

  group('CorregirIdentidadUnidadUseCase — casos base', () {
    test('corrige el número de serie de una unidad sin historial', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id);

      final resultado = await corregir.ejecutar(
        unidadId: unidad.id,
        motivo: 'Se capturó mal al dar de alta.',
        numeroSerie: 'SN-CORRECTA-001',
        actorUsuarioId: actorId,
      );

      expect(resultado, isA<CorregirIdentidadUnidadExitoso>());
      final corregida = (resultado as CorregirIdentidadUnidadExitoso).unidad;
      expect(corregida.numeroSerie, 'SN-CORRECTA-001');
      expect(corregida.id, unidad.id, reason: 'mismo ArticuloUnidad.id');
      expect(corregida.codigo, unidad.codigo, reason: 'mismo código UNI-...');

      final eventos = await inventarioRepo.listarEventosUnidad(unidad.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.campo, 'numeroSerie');
      expect(eventos.single.valorAnterior, 'SN-MAL-001');
      expect(eventos.single.valorNuevo, 'SN-CORRECTA-001');
      expect(eventos.single.actorUsuarioId, actorId);
      expect(eventos.single.motivo, 'Se capturó mal al dar de alta.');
    });

    test('guardar el mismo número de serie actual no genera falso duplicado ni evento', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id, numeroSerie: 'SN-YA-CORRECTA');

      final resultado = await corregir.ejecutar(
        unidadId: unidad.id,
        motivo: 'Confirmar dato.',
        numeroSerie: 'SN-YA-CORRECTA',
      );

      expect(resultado, isA<CorregirIdentidadUnidadExitoso>());
      final eventos = await inventarioRepo.listarEventosUnidad(unidad.id);
      expect(eventos, isEmpty, reason: 'sin cambio real, sin evento');
    });

    test('rechaza una nueva serie que ya pertenece a otra unidad, con mensaje entendible', () async {
      final articulo = await crearArticuloSerializado();
      await crearUnidad(articulo.id, numeroSerie: 'SN-YA-EXISTE');
      final unidadB = await crearUnidad(articulo.id, numeroSerie: 'SN-B');

      final resultado = await corregir.ejecutar(unidadId: unidadB.id, motivo: 'prueba', numeroSerie: 'SN-YA-EXISTE');

      expect(resultado, isA<CorregirIdentidadUnidadNumeroSerieDuplicado>());
      expect(
        (resultado as CorregirIdentidadUnidadNumeroSerieDuplicado).detalle,
        'El número de serie/IMEI ya está registrado en otra unidad.',
      );

      final unidadBTrasFallo = await inventarioRepo.obtenerUnidadPorId(unidadB.id);
      expect(unidadBTrasFallo!.numeroSerie, 'SN-B', reason: 'nada cambió tras el rechazo');
    });

    test('motivo obligatorio', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id);

      final resultado = await corregir.ejecutar(unidadId: unidad.id, motivo: '   ', numeroSerie: 'SN-X');
      expect(resultado, isA<CorregirIdentidadUnidadMotivoRequerido>());
    });

    test('número de serie no puede quedar vacío', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id);

      final resultado = await corregir.ejecutar(unidadId: unidad.id, motivo: 'prueba', numeroSerie: '   ');
      expect(resultado, isA<CorregirIdentidadUnidadNumeroSerieRequerido>());
    });

    test('unidad inexistente', () async {
      final resultado = await corregir.ejecutar(unidadId: 'no-existe', motivo: 'prueba', numeroSerie: 'SN-X');
      expect(resultado, isA<CorregirIdentidadUnidadNoExiste>());
    });

    test('corrige marca y modelo sin tocar el número de serie', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id);

      final resultado = await corregir.ejecutar(unidadId: unidad.id, motivo: 'prueba', marca: 'Samsung', modelo: 'A15');
      final corregida = (resultado as CorregirIdentidadUnidadExitoso).unidad;
      expect(corregida.numeroSerie, unidad.numeroSerie);
      expect(corregida.marca, 'Samsung');
      expect(corregida.modelo, 'A15');
    });
  });

  group('CorregirIdentidadUnidadUseCase — IMEI', () {
    test('corrige IMEI 1 e IMEI 2, con evento por cada uno', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id, imei: '111111111111111');

      final resultado = await corregir.ejecutar(
        unidadId: unidad.id,
        motivo: 'IMEI mal capturado.',
        imei: '222222222222222',
        imei2: '333333333333333',
      );

      expect(resultado, isA<CorregirIdentidadUnidadExitoso>());
      final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
      expect(telefono!.imei, '222222222222222');
      expect(telefono.imei2, '333333333333333');

      final eventos = await inventarioRepo.listarEventosUnidad(unidad.id);
      expect(eventos.map((e) => e.campo).toSet(), {'imei1', 'imei2'});
    });

    test('rechaza un IMEI que ya pertenece a otro equipo', () async {
      final articulo = await crearArticuloSerializado();
      await crearUnidad(articulo.id, numeroSerie: 'SN-1', imei: '111111111111111');
      final unidadB = await crearUnidad(articulo.id, numeroSerie: 'SN-2', imei: '222222222222222');

      final resultado = await corregir.ejecutar(unidadId: unidadB.id, motivo: 'prueba', imei: '111111111111111');
      expect(resultado, isA<CorregirIdentidadUnidadImeiDuplicado>());
    });

    test('IMEI 1 e IMEI 2 no pueden terminar siendo el mismo valor', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id, imei: '111111111111111');

      final resultado = await corregir.ejecutar(unidadId: unidad.id, motivo: 'prueba', imei2: '111111111111111');
      expect(resultado, isA<CorregirIdentidadUnidadImeiDuplicado>());
    });
  });

  group('CorregirIdentidadUnidadUseCase — conserva relaciones existentes', () {
    test('conserva la asignación vigente al corregir el número de serie', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id);
      final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
      final empleado = await db.into(db.empleado).insertReturning(
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
      final asignacion = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      await corregir.ejecutar(unidadId: unidad.id, motivo: 'prueba', numeroSerie: 'SN-CORRECTA');

      final vigente = await asignacionRepo.obtenerPorId(asignacion.asignacion.id);
      expect(vigente!.estatus, 'activa', reason: 'la asignación sigue vigente, sin tocar');
      expect(vigente.empleadoId, empleado.id);
      expect(vigente.unidadId, unidad.id);
    });

    test('conserva línea telefónica asociada y credencial al corregir IMEI', () async {
      final articulo = await crearArticuloSerializado();
      final unidad = await crearUnidad(articulo.id, imei: '111111111111111');

      final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
      final equipoLineaRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, asignacionRepo, inventarioRepo);
      final lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoLineaRepo);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
      final asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoLineaRepo, inventarioRepo);

      final linea = (await crearLinea.ejecutar(operador: 'telcel', modalidadSim: 'fisica')) as CrearLineaTelefonicaExitoso;
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 15));

      final equipoRepo = EquipoTelefonicoRepositoryImpl(db);
      await equipoRepo.guardarCorreo(unidadId: unidad.id, correo: 'equipo@riseg.com');

      final equipoLineaAntes = await equipoLineaRepo.obtenerActualPorUnidad(unidad.id);

      final resultado = await corregir.ejecutar(
        unidadId: unidad.id,
        motivo: 'IMEI mal capturado.',
        imei: '999999999999999',
      );
      expect(resultado, isA<CorregirIdentidadUnidadExitoso>());

      final equipoLineaDespues = await equipoLineaRepo.obtenerActualPorUnidad(unidad.id);
      expect(equipoLineaDespues!.id, equipoLineaAntes!.id, reason: 'la asociación con la línea no se toca');
      expect(equipoLineaDespues.lineaTelefonicaId, linea.linea.id);

      final credencial = await equipoRepo.obtenerCredencial(unidad.id);
      expect(credencial!.correo, 'equipo@riseg.com', reason: 'la credencial no se toca');

      final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
      expect(telefono!.imei, '999999999999999');
    });
  });

  group('CorregirIdentidadUnidadUseCase — no altera la cadena Compra → Inventario → Finanzas', () {
    Future<
        ({
          CompraData compra,
          EgresoData egreso,
          ArticuloUnidadData unidad,
        })> registrarCompraSerializadaDePrueba() async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
      final registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final articulo = await crearArticuloSerializado();

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        proveedor: 'Tienda de teléfonos',
        formaPago: FormaPago.tarjeta.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 1,
            costoUnitario: 179400,
            numerosSerie: const ['SN-MAL-CAPTURADA'],
          ),
        ],
      ) as RegistrarCompraExitosa;

      final egreso = await db.select(db.egreso).getSingle();
      final unidad = (await inventarioRepo.listarUnidades(articulo.id)).single;
      return (compra: resultado.compra, egreso: egreso, unidad: unidad);
    }

    test('la Compra no cambia', () async {
      final fixture = await registrarCompraSerializadaDePrueba();
      await corregir.ejecutar(unidadId: fixture.unidad.id, motivo: 'prueba', numeroSerie: 'SN-CORRECTA');

      final compraDespues = await db.select(db.compra).getSingle();
      expect(compraDespues.folioCompra, fixture.compra.folioCompra);
      expect(compraDespues.proveedor, fixture.compra.proveedor);
      expect(compraDespues.estatus, fixture.compra.estatus);
      expect(compraDespues.egresoId, fixture.compra.egresoId);
    });

    test('el Egreso no cambia', () async {
      final fixture = await registrarCompraSerializadaDePrueba();
      await corregir.ejecutar(unidadId: fixture.unidad.id, motivo: 'prueba', numeroSerie: 'SN-CORRECTA');

      final egresoDespues = await db.select(db.egreso).getSingle();
      expect(egresoDespues.id, fixture.egreso.id);
      expect(egresoDespues.monto, fixture.egreso.monto);
      expect(egresoDespues.folioEgreso, fixture.egreso.folioEgreso);
    });

    test('el MovimientoInventario no cambia (ni cantidad ni nuevo movimiento)', () async {
      final fixture = await registrarCompraSerializadaDePrueba();
      final movimientosAntes = await db.select(db.movimientoInventario).get();

      await corregir.ejecutar(unidadId: fixture.unidad.id, motivo: 'prueba', numeroSerie: 'SN-CORRECTA');

      final movimientosDespues = await db.select(db.movimientoInventario).get();
      expect(movimientosDespues, hasLength(movimientosAntes.length), reason: 'sin nuevo MovimientoInventario');
      expect(movimientosDespues.single.cantidad, movimientosAntes.single.cantidad);
      expect(movimientosDespues.single.costoUnitario, movimientosAntes.single.costoUnitario);
      expect(movimientosDespues.single.unidadId, fixture.unidad.id);
    });

    test('la existencia no cambia', () async {
      final fixture = await registrarCompraSerializadaDePrueba();
      final articuloId = fixture.unidad.articuloId;
      final existenciaAntes = await inventarioRepo.calcularExistenciaUnidades(articuloId);

      await corregir.ejecutar(unidadId: fixture.unidad.id, motivo: 'prueba', numeroSerie: 'SN-CORRECTA');

      final existenciaDespues = await inventarioRepo.calcularExistenciaUnidades(articuloId);
      expect(existenciaDespues.total, existenciaAntes.total);
      expect(existenciaDespues.disponible, existenciaAntes.disponible);
    });

    test('mismo ArticuloUnidad.id y código UNI-... tras la corrección', () async {
      final fixture = await registrarCompraSerializadaDePrueba();

      final resultado = await corregir.ejecutar(unidadId: fixture.unidad.id, motivo: 'prueba', numeroSerie: 'SN-CORRECTA');
      final corregida = (resultado as CorregirIdentidadUnidadExitoso).unidad;

      expect(corregida.id, fixture.unidad.id);
      expect(corregida.codigo, fixture.unidad.codigo);
      expect(corregida.numeroSerie, 'SN-CORRECTA');
    });

    test('RegistrarCompraUseCase rechaza un número de serie ya usado por otra unidad, con el mismo mensaje', () async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
      final registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final articulo = await crearArticuloSerializado();
      await crearUnidad(articulo.id, numeroSerie: 'SN-YA-EXISTE');

      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 1,
            costoUnitario: 100000,
            numerosSerie: const ['SN-YA-EXISTE'],
          ),
        ],
      );

      expect(resultado, isA<RegistrarCompraPartidaNumeroSerieDuplicado>());
      expect((resultado as RegistrarCompraPartidaNumeroSerieDuplicado).numeroSerie, 'SN-YA-EXISTE');

      final compras = await db.select(db.compra).get();
      expect(compras, isEmpty, reason: 'ninguna Compra se registró tras el rechazo');
    });
  });
}
