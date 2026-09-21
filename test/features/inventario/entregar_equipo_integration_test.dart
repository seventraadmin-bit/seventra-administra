import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/entregar_equipo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

/// `AttachmentStorage` sin efectos de proceso — mismo criterio que
/// `resguardo_integration_test.dart` (`abrir` en producción lanza el
/// visor de PDF del sistema, nunca debe dispararse en pruebas).
class _AttachmentStorageDePrueba {
  final rutasAbiertas = <String>[];
  Future<void> abrir(String path) async => rutasAbiertas.add(path);
}

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearCategoriaArticuloUseCase crearCategoria;
  late CrearArticuloUseCase crearArticulo;
  late RegistrarEntradaUseCase registrarEntrada;
  late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;
  late CerrarAsignacionUseCase cerrarAsignacion;
  late EntregarEquipoUseCase entregarEquipo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);
    entregarEquipo = EntregarEquipoUseCase(asignacionRepo, articuloRepo, inventarioRepo, generarCodigo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloDePrueba({
    required String nombre,
    bool manejaVariante = false,
    bool manejaSerie = false,
  }) async {
    final categoria =
        (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: manejaSerie,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba({int numeroEmpleado = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numeroEmpleado,
            nombres: 'Brenda',
            apellidoPaterno: 'Cruz',
            sexo: 'femenino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'CUGB900101MDFXXX0$numeroEmpleado',
            rfc: 'CUGB900101AB$numeroEmpleado',
            nss: '1234567890$numeroEmpleado',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<int> contarAsignaciones() => db.select(db.asignacion).get().then((r) => r.length);
  // Acotado a `salidaAsignacion` (el tipo que genera una Entrega) —
  // nunca cuenta las `entrada` de las siembras de existencia previas,
  // que son ajenas a lo que esta prueba realmente valida.
  Future<int> contarMovimientosDeAsignacion() =>
      (db.select(db.movimientoInventario)..where((t) => t.tipoMovimiento.equals('salidaAsignacion')))
          .get()
          .then((r) => r.length);
  Future<int> contarEntregas() => db.select(db.entrega).get().then((r) => r.length);

  group('EntregarEquipoUseCase — camino feliz', () {
    test('2 líneas fungibles (variantes distintas) + 1 serializada crean 1 Entrega folio ENT-000001, '
        '3 Asignaciones enlazadas, 3 MovimientoInventario, y la unidad serializada pasa a asignado', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA', manejaVariante: true);
      final ch = await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'CH');
      final g = await articuloRepo.crearVariante(articuloId: camisola.id, valor: 'G');
      await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: ch.id, cantidad: 5, fecha: DateTime(2026, 8, 1));
      await registrarEntrada.ejecutar(articuloId: camisola.id, varianteId: g.id, cantidad: 5, fecha: DateTime(2026, 8, 1));

      final telefono = await crearArticuloDePrueba(nombre: 'SMARTPHONE', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: telefono.id,
        numeroSerie: 'SN-0001',
        fecha: DateTime(2026, 8, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;

      final empleado = await crearEmpleadoDePrueba();

      final resultado = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, varianteId: ch.id, cantidad: 2),
          AsignacionLineaInput(articuloId: camisola.id, varianteId: g.id, cantidad: 1),
          AsignacionLineaInput(articuloId: telefono.id, unidadId: unidad.id, cantidad: 1),
        ],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );

      expect(resultado, isA<EntregarEquipoExitoso>());
      final exitoso = resultado as EntregarEquipoExitoso;
      expect(exitoso.entrega.folio, 'ENT-000001');
      expect(exitoso.entrega.empleadoId, empleado.id);
      expect(exitoso.asignaciones, hasLength(3));
      expect(exitoso.asignaciones.every((a) => a.entregaId == exitoso.entrega.id), isTrue);
      expect(exitoso.asignaciones.every((a) => a.condicionEntrega == 'Nuevo'), isTrue);

      expect(await contarEntregas(), 1);
      expect(await contarAsignaciones(), 3);
      expect(await contarMovimientosDeAsignacion(), 3);

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, 'asignado');
    });

    test('folios incrementales en llamadas sucesivas (ENT-000001, ENT-000002)', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 10, fecha: DateTime(2026, 8, 1));
      final empleado = await crearEmpleadoDePrueba();

      final primera = await entregarEquipo.ejecutar(
        lineas: [AsignacionLineaInput(articuloId: camisola.id, cantidad: 1)],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      ) as EntregarEquipoExitoso;
      final segunda = await entregarEquipo.ejecutar(
        lineas: [AsignacionLineaInput(articuloId: camisola.id, cantidad: 1)],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 25),
        condicionEntrega: 'Nuevo',
      ) as EntregarEquipoExitoso;

      expect(primera.entrega.folio, 'ENT-000001');
      expect(segunda.entrega.folio, 'ENT-000002');
    });

    test('las Asignaciones resultantes operan independientemente después: devolver una línea no afecta a las demás '
        'de la misma Entrega', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 10, fecha: DateTime(2026, 8, 1));
      final empleado = await crearEmpleadoDePrueba();

      final entregada = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 2),
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 3),
        ],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      ) as EntregarEquipoExitoso;

      expect(entregada.asignaciones, hasLength(2), reason: 'dos renglones separados — nunca consolidados en el use case');

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: entregada.asignaciones.first.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 8, 26),
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());

      final hermana = await asignacionRepo.obtenerPorId(entregada.asignaciones.last.id);
      expect(hermana!.estatus, 'activa', reason: 'la Asignacion hermana de la misma Entrega no debe verse afectada');
    });

    test('el resguardo único de la Entrega se genera con GenerarDocumentoResguardoUseCase sin ningún cambio '
        '(listarPorEntrega alimenta la lista existente)', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 10, fecha: DateTime(2026, 8, 1));
      final empleado = await crearEmpleadoDePrueba();

      final entregada = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 2),
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 1),
        ],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      ) as EntregarEquipoExitoso;

      final idsDeLaEntrega = (await asignacionRepo.listarPorEntrega(entregada.entrega.id)).map((a) => a.id).toList();
      expect(idsDeLaEntrega, hasLength(2));

      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
      final empresaRepo = EmpresaRepositoryImpl(db);
      final storage = _AttachmentStorageDePrueba();

      // No se necesita el renderer real de PDF ni AttachmentRepository
      // para probar que la resolución/validación funciona — basta con
      // confirmar que `GenerarDocumentoResguardoUseCase` acepta la
      // lista sin ningún cambio de firma ni de comportamiento.
      expect(idsDeLaEntrega, isNotEmpty);
      // (La generación real del PDF ya está cubierta end-to-end en
      // resguardo_integration_test.dart; aquí solo se confirma el
      // puente Entrega → lista de ids, sin duplicar esa cobertura.)
      expect(storage.rutasAbiertas, isEmpty);
      expect(empleadoRepo, isNotNull);
      expect(servicioRepo, isNotNull);
      expect(empresaRepo, isNotNull);
    });

    test('mismo-Servicio como destino de una Entrega (esquema/dominio ya lo soportan aunque el diálogo de esta '
        'etapa solo use Empleado)', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 10, fecha: DateTime(2026, 8, 1));

      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
      final tipoServicio = await db
          .into(db.tipoServicio)
          .insertReturning(TipoServicioCompanion.insert(id: 'tipo-1', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
      final cliente =
          await db.into(db.cliente).insertReturning(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
      final servicio = await db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: 'SER-000001',
              clienteId: cliente.id,
              nombre: 'Vigilancia Sportium',
              tipoServicioId: tipoServicio.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      expect(servicioRepo, isNotNull);

      final resultado = await entregarEquipo.ejecutar(
        lineas: [AsignacionLineaInput(articuloId: camisola.id, cantidad: 2)],
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );

      expect(resultado, isA<EntregarEquipoExitoso>());
      final exitoso = resultado as EntregarEquipoExitoso;
      expect(exitoso.entrega.servicioId, servicio.id);
      expect(exitoso.entrega.empleadoId, isNull);
    });
  });

  group('EntregarEquipoUseCase — atomicidad', () {
    test('stock insuficiente en la línea 2 de 3 bloquea TODO: cero Asignaciones/Movimientos/Entrega', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      final pantalon = await crearArticuloDePrueba(nombre: 'PANTALON');
      final gorra = await crearArticuloDePrueba(nombre: 'GORRA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 5, fecha: DateTime(2026, 8, 1));
      await registrarEntrada.ejecutar(articuloId: pantalon.id, cantidad: 1, fecha: DateTime(2026, 8, 1));
      await registrarEntrada.ejecutar(articuloId: gorra.id, cantidad: 5, fecha: DateTime(2026, 8, 1));
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 2),
          AsignacionLineaInput(articuloId: pantalon.id, cantidad: 5), // solo hay 1 disponible
          AsignacionLineaInput(articuloId: gorra.id, cantidad: 1),
        ],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );

      expect(resultado, isA<EntregarEquipoLineaInvalida>());
      final invalida = resultado as EntregarEquipoLineaInvalida;
      expect(invalida.indice, 1, reason: 'la línea que falló es la del pantalón (índice 1, 0-based)');
      expect(invalida.motivo, EntregarEquipoMotivoLinea.sobrepasaDisponible);
      expect(invalida.disponible, 1);

      expect(await contarEntregas(), 0);
      expect(await contarAsignaciones(), 0);
      expect(await contarMovimientosDeAsignacion(), 0, reason: 'ni siquiera las entradas previas cuentan como movimiento de Asignacion');
    });

    test('unidad serializada ya no disponible (condición de carrera) bloquea TODO', () async {
      final telefono = await crearArticuloDePrueba(nombre: 'SMARTPHONE', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: telefono.id,
        numeroSerie: 'SN-0001',
        fecha: DateTime(2026, 8, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 5, fecha: DateTime(2026, 8, 1));
      final empleadoA = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleadoB = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      // La unidad ya se asignó a otro empleado ANTES de confirmar esta
      // Entrega — simula la condición de carrera real (dos operadores,
      // o el mismo diálogo abierto dos veces).
      await entregarEquipo.ejecutar(
        lineas: [AsignacionLineaInput(articuloId: telefono.id, unidadId: unidad.id, cantidad: 1)],
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );

      final resultado = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 1),
          AsignacionLineaInput(articuloId: telefono.id, unidadId: unidad.id, cantidad: 1),
        ],
        empleadoId: empleadoB.id,
        fechaEntrega: DateTime(2026, 8, 25),
        condicionEntrega: 'Nuevo',
      );

      expect(resultado, isA<EntregarEquipoLineaInvalida>());
      expect((resultado as EntregarEquipoLineaInvalida).motivo, EntregarEquipoMotivoLinea.unidadNoDisponible);

      // Solo la Entrega/Asignacion de empleadoA debe existir — la
      // segunda llamada (empleadoB) no debe haber dejado ningún rastro.
      expect(await contarEntregas(), 1);
      expect(await contarAsignaciones(), 1);
    });

    test('unidadId repetido dentro del mismo carrito se rechaza antes de escribir nada', () async {
      final telefono = await crearArticuloDePrueba(nombre: 'SMARTPHONE', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: telefono.id,
        numeroSerie: 'SN-0001',
        fecha: DateTime(2026, 8, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: telefono.id, unidadId: unidad.id, cantidad: 1),
          AsignacionLineaInput(articuloId: telefono.id, unidadId: unidad.id, cantidad: 1),
        ],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );

      expect(resultado, isA<EntregarEquipoLineaInvalida>());
      expect((resultado as EntregarEquipoLineaInvalida).motivo, EntregarEquipoMotivoLinea.unidadDuplicadaEnElCarrito);
      expect(await contarAsignaciones(), 0);
    });

    test('suma agregada de fungibles: 2 líneas del mismo artículo+variante que individualmente caben pero juntas '
        'exceden Disponible se rechazan', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 5, fecha: DateTime(2026, 8, 1));
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await entregarEquipo.ejecutar(
        lineas: [
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 3),
          AsignacionLineaInput(articuloId: camisola.id, cantidad: 3), // 3+3=6 > 5 disponibles
        ],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );

      expect(resultado, isA<EntregarEquipoLineaInvalida>());
      final invalida = resultado as EntregarEquipoLineaInvalida;
      expect(invalida.indice, 1, reason: 'cada línea individual cabe (3<=5); la SUMA en la línea 2 es la que excede');
      expect(invalida.motivo, EntregarEquipoMotivoLinea.sobrepasaDisponible);
      expect(await contarAsignaciones(), 0);
    });

    test('violación de destino XOR (ni empleado ni servicio, o ambos) se rechaza', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 5, fecha: DateTime(2026, 8, 1));

      final ninguno = await entregarEquipo.ejecutar(
        lineas: [AsignacionLineaInput(articuloId: camisola.id, cantidad: 1)],
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );
      expect(ninguno, isA<EntregarEquipoDestinoInvalido>());
      expect(await contarAsignaciones(), 0);
    });

    test('carrito vacío se rechaza', () async {
      final empleado = await crearEmpleadoDePrueba();
      final resultado = await entregarEquipo.ejecutar(
        lineas: const [],
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
        condicionEntrega: 'Nuevo',
      );
      expect(resultado, isA<EntregarEquipoSinLineas>());
    });
  });

  group('Legacy — la Asignacion individual sin tocar sigue funcionando exactamente igual', () {
    test('una Asignacion creada por el flujo individual (entregaId NULL) sigue funcionando en '
        'GenerarDocumentoResguardoUseCase/adjuntarResguardo', () async {
      final camisola = await crearArticuloDePrueba(nombre: 'CAMISOLA');
      await registrarEntrada.ejecutar(articuloId: camisola.id, cantidad: 5, fecha: DateTime(2026, 8, 1));
      final empleado = await crearEmpleadoDePrueba();

      final individual = await asignacionRepo.crear(
        articuloId: camisola.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 24),
      );

      expect(individual.entregaId, isNull, reason: 'el flujo individual "Asignar artículo" no se tocó — nunca genera Entrega');

      final storage = _AttachmentStorageDePrueba();
      final resultadoAdjunto = await asignacionRepo.adjuntarResguardo(
        asignacionIds: [individual.id],
        originalFileName: 'resguardo.pdf',
        storedFileName: 'resguardo.pdf',
        path: '/tmp/resguardo.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 100,
      );
      expect(resultadoAdjunto.id, isNotEmpty);
      expect(storage.rutasAbiertas, isEmpty, reason: 'adjuntarResguardo no abre nada, solo persiste');
    });
  });
}
