import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_equipo_linea_telefonica_usecase.dart';

/// Cubre el hilo de `actorUsuarioId` en Telefonía (Etapa 9D, punto 11):
/// `AsignacionLineaTelefonica`/`LineaTelefonicaEquipo` ya recibían el
/// parámetro desde 9B, pero las columnas no existían y el valor se
/// descartaba silenciosamente; `RecargaLineaTelefonica.actorUsuarioId`
/// ya tenía columna desde 11D pero el UseCase/repositorio nunca lo
/// aceptaban, así que siempre quedaba `null`. Esta suite confirma que
/// las 3 ahora sí persisten un actor real, y que un actor `null` (sin
/// sesión) sigue sin romper ninguna FK.
void main() {
  late AppDatabase db;

  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl inventarioAsignacionRepo;
  late AsignacionLineaTelefonicaRepositoryImpl asignacionLineaRepo;
  late LineaTelefonicaEquipoRepositoryImpl equipoLineaRepo;
  late LineaTelefonicaRepositoryImpl lineaRepo;
  late RecargaLineaTelefonicaRepositoryImpl recargaRepo;

  late CrearCategoriaArticuloUseCase crearCategoria;
  late CrearArticuloUseCase crearArticulo;
  late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;
  late CrearLineaTelefonicaUseCase crearLinea;
  late AsignarLineaTelefonicaUseCase asignarLinea;
  late RetirarAsignacionLineaTelefonicaUseCase retirarAsignacion;
  late AsociarEquipoLineaTelefonicaUseCase asociarEquipo;
  late CambiarEquipoLineaTelefonicaUseCase cambiarEquipo;
  late RetirarEquipoLineaTelefonicaUseCase retirarEquipo;
  late RegistrarRecargaLineaTelefonicaUseCase registrarRecarga;

  const actorId = 'actor-de-prueba';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value(actorId), nombre: 'Actor de prueba', nombreUsuario: actorId, passwordHash: 'x'),
        );

    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    inventarioAsignacionRepo = AsignacionRepositoryImpl(db);
    asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
    equipoLineaRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, inventarioAsignacionRepo, inventarioRepo);
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoLineaRepo);
    recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db);

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
    crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
    asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoLineaRepo);
    retirarAsignacion = RetirarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoLineaRepo);
    asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoLineaRepo, inventarioRepo);
    cambiarEquipo = CambiarEquipoLineaTelefonicaUseCase(lineaRepo, equipoLineaRepo, inventarioRepo);
    retirarEquipo = RetirarEquipoLineaTelefonicaUseCase(equipoLineaRepo);
    registrarRecarga = RegistrarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo);
  });

  tearDown(() => db.close());

  Future<LineaTelefonicaData> crearLineaDePrueba({String? numero}) async {
    final resultado = await crearLinea.ejecutar(numero: numero, operador: 'telcel', modalidadSim: 'fisica');
    return (resultado as CrearLineaTelefonicaExitoso).linea;
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

  Future<ArticuloData> crearArticuloTelefonoDePrueba() async {
    final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
    final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Smartphone', manejaSerie: true);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<ArticuloUnidadData> crearUnidadTelefonoDePrueba(String articuloId, {String numeroSerie = 'SN-TEL-0001'}) async {
    // `AsociarEquipoLineaTelefonicaUseCase` exige que la unidad ya tenga
    // una fila `ArticuloUnidadTelefono` (que sea, de hecho, un teléfono),
    // así que el IMEI se captura ya desde el alta.
    final resultado = await registrarEntradaUnidad.ejecutar(
      articuloId: articuloId,
      numeroSerie: numeroSerie,
      imei: '35$numeroSerie',
      fecha: DateTime(2026, 1, 1),
    );
    return (resultado as RegistrarEntradaUnidadExitoso).unidad;
  }

  group('AsignacionLineaTelefonica.actorUsuarioId', () {
    test('se persiste al crear (asignar)', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
        actorUsuarioId: actorId,
      );

      final asignacion = (resultado as AsignarLineaTelefonicaExitoso).asignacion;
      expect(asignacion.actorUsuarioId, actorId);
    });

    test('se persiste al cerrar (retirar)', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;

      final resultado = await retirarAsignacion.ejecutar(
        asignacionLineaTelefonicaId: asignacion.id,
        fechaTermino: DateTime(2026, 2, 1),
        actorUsuarioId: actorId,
      );

      expect((resultado as RetirarAsignacionLineaTelefonicaExitoso).asignacion.actorUsuarioId, actorId);
    });

    test('se persiste al cambiar responsable — la fila NUEVA lleva el actor del cambio', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);
      final asignacion1 = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado1.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;

      final nueva = await asignacionLineaRepo.cambiarResponsable(
        asignacionLineaTelefonicaActualId: asignacion1.id,
        fecha: DateTime(2026, 3, 1),
        nuevoEmpleadoId: empleado2.id,
        actorUsuarioId: actorId,
      );

      expect(nueva.actorUsuarioId, actorId);
    });
  });

  group('LineaTelefonicaEquipo.actorUsuarioId', () {
    test('se persiste al asociar', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);

      final resultado = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
        actorUsuarioId: actorId,
      );

      expect((resultado as AsociarEquipoLineaTelefonicaExitoso).equipo.actorUsuarioId, actorId);
    });

    test('se persiste al retirar', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));

      await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 2, 1), actorUsuarioId: actorId);

      final historial = await equipoLineaRepo.listarPorLinea(linea.id);
      expect(historial.single.actorUsuarioId, actorId);
    });

    test('se persiste al cambiar de equipo — la fila NUEVA lleva el actor del cambio', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidadVieja = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-VIEJA');
      final unidadNueva = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-NUEVA');
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidadVieja.id, fechaInicio: DateTime(2026, 1, 5));

      final resultado = await cambiarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        nuevaUnidadId: unidadNueva.id,
        fecha: DateTime(2026, 3, 1),
        actorUsuarioId: actorId,
      );

      expect((resultado as CambiarEquipoLineaTelefonicaExitoso).equipo.actorUsuarioId, actorId);
    });
  });

  group('RecargaLineaTelefonica.actorUsuarioId', () {
    test('ahora sí se puebla al registrar una recarga con un actor real', () async {
      final linea = await crearLineaDePrueba();

      final resultado = await registrarRecarga.ejecutar(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 2, 1),
        importe: 20000,
        actorUsuarioId: actorId,
      );

      final recarga = (resultado as RegistrarRecargaLineaTelefonicaExitoso).recarga;
      expect(recarga.actorUsuarioId, actorId);

      final filaDirecta = await (db.select(db.recargaLineaTelefonica)..where((t) => t.id.equals(recarga.id))).getSingle();
      expect(filaDirecta.actorUsuarioId, actorId, reason: 'antes de la Etapa 9D la columna existía pero siempre quedaba null');
    });
  });

  group('Sin sesión (actor null) — nunca rompe la FK', () {
    test('asignar/retirar/cambiar responsable de línea con actorUsuarioId null', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      final asignacion = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado1.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      expect(asignacion.actorUsuarioId, isNull);

      final cambiada = await asignacionLineaRepo.cambiarResponsable(
        asignacionLineaTelefonicaActualId: asignacion.id,
        fecha: DateTime(2026, 2, 1),
        nuevoEmpleadoId: empleado2.id,
      );
      expect(cambiada.actorUsuarioId, isNull);

      final retirada = await retirarAsignacion.ejecutar(asignacionLineaTelefonicaId: cambiada.id, fechaTermino: DateTime(2026, 3, 1));
      expect((retirada as RetirarAsignacionLineaTelefonicaExitoso).asignacion.actorUsuarioId, isNull);
    });

    test('asociar/cambiar/retirar equipo con actorUsuarioId null', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidadVieja = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-VIEJA-2');
      final unidadNueva = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-NUEVA-2');

      final asociado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidadVieja.id, fechaInicio: DateTime(2026, 1, 5));
      expect((asociado as AsociarEquipoLineaTelefonicaExitoso).equipo.actorUsuarioId, isNull);

      final cambiado = await cambiarEquipo.ejecutar(lineaTelefonicaId: linea.id, nuevaUnidadId: unidadNueva.id, fecha: DateTime(2026, 2, 1));
      expect((cambiado as CambiarEquipoLineaTelefonicaExitoso).equipo.actorUsuarioId, isNull);

      final resultado = await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 3, 1));
      expect(resultado, isA<RetirarEquipoLineaTelefonicaExitoso>());
    });

    test('registrar recarga con actorUsuarioId null', () async {
      final linea = await crearLineaDePrueba();

      final resultado = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 2, 1), importe: 10000);

      expect((resultado as RegistrarRecargaLineaTelefonicaExitoso).recarga.actorUsuarioId, isNull);
    });
  });
}
