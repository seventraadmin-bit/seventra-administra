import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_equipo_linea_telefonica_usecase.dart';

/// Cubre Asignaciones y equipo asociado de Telefonía (Etapa 9B) —
/// destino Empleado/Servicio con FK reales, una sola vigente, cambio de
/// equipo sin crear una línea nueva, y sobre todo el punto más
/// importante de 9B: la sincronización activa de custodia con
/// Inventario vía composición de repositorios (nunca duplicando datos,
/// siempre respetando el destino real que Inventario reporta —
/// guardia de divergencia incluida).
void main() {
  late AppDatabase db;

  late LineaTelefonicaRepositoryImpl lineaRepo;
  late AsignacionLineaTelefonicaRepositoryImpl asignacionLineaRepo;
  late LineaTelefonicaEquipoRepositoryImpl equipoRepo;
  late AsignacionRepositoryImpl inventarioAsignacionRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late ArticuloRepositoryImpl articuloRepo;

  late CrearLineaTelefonicaUseCase crearLinea;
  late DarDeBajaLineaTelefonicaUseCase darDeBaja;
  late AsignarLineaTelefonicaUseCase asignarLinea;
  late CambiarAsignacionLineaTelefonicaUseCase cambiarAsignacion;
  late RetirarAsignacionLineaTelefonicaUseCase retirarAsignacion;
  late AsociarEquipoLineaTelefonicaUseCase asociarEquipo;
  late CambiarEquipoLineaTelefonicaUseCase cambiarEquipo;
  late RetirarEquipoLineaTelefonicaUseCase retirarEquipo;

  late CrearCategoriaArticuloUseCase crearCategoria;
  late CrearArticuloUseCase crearArticulo;
  late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());

    asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
    inventarioAsignacionRepo = AsignacionRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    articuloRepo = ArticuloRepositoryImpl(db);
    equipoRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, inventarioAsignacionRepo, inventarioRepo);
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);

    crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
    darDeBaja = DarDeBajaLineaTelefonicaUseCase(lineaRepo);
    asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);
    cambiarAsignacion = CambiarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoRepo);
    retirarAsignacion = RetirarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoRepo);
    asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo);
    cambiarEquipo = CambiarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo);
    retirarEquipo = RetirarEquipoLineaTelefonicaUseCase(equipoRepo);

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
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

  Future<ServicioData> crearServicioDePrueba({String codigo = 'SER-000001'}) async {
    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-servicio-$codigo', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
    final cliente =
        await db.into(db.cliente).insertReturning(ClienteCompanion.insert(codigo: 'CLI-$codigo', nombreComercial: 'Sportium'));
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: codigo,
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<ArticuloData> crearArticuloTelefonoDePrueba() async {
    final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
    final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Smartphone', manejaSerie: true);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<ArticuloUnidadData> crearUnidadTelefonoDePrueba(String articuloId, {String numeroSerie = 'SN-TEL-0001'}) async {
    final resultado = await registrarEntradaUnidad.ejecutar(
      articuloId: articuloId,
      numeroSerie: numeroSerie,
      imei: '35$numeroSerie',
      fecha: DateTime(2026, 1, 1),
    );
    return (resultado as RegistrarEntradaUnidadExitoso).unidad;
  }

  Future<ArticuloUnidadData> crearUnidadNoTelefonoDePrueba(String articuloId, {String numeroSerie = 'SN-RADIO-0001'}) async {
    final resultado = await registrarEntradaUnidad.ejecutar(
      articuloId: articuloId,
      numeroSerie: numeroSerie,
      fecha: DateTime(2026, 1, 1),
    );
    return (resultado as RegistrarEntradaUnidadExitoso).unidad;
  }

  group('AsignarLineaTelefonicaUseCase', () {
    test('asigna a un Empleado', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));

      expect(resultado, isA<AsignarLineaTelefonicaExitoso>());
      final asignacion = (resultado as AsignarLineaTelefonicaExitoso).asignacion;
      expect(asignacion.empleadoId, empleado.id);
      expect(asignacion.servicioId, isNull);
    });

    test('asigna a un Servicio', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();

      final resultado = await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 5));

      expect(resultado, isA<AsignarLineaTelefonicaExitoso>());
      expect((resultado as AsignarLineaTelefonicaExitoso).asignacion.servicioId, servicio.id);
    });

    test('rechaza ni empleado ni servicio, o ambos', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final ninguno = await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, fechaInicio: DateTime(2026, 1, 5));
      expect(ninguno, isA<AsignarLineaTelefonicaDestinoInvalido>());

      final ambos = await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 1, 5),
      );
      expect(ambos, isA<AsignarLineaTelefonicaDestinoInvalido>());
    });

    test('rechaza asignar una línea que ya tiene asignación vigente (solo una vigente)', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado1.id, fechaInicio: DateTime(2026, 1, 5));
      final segundoIntento =
          await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado2.id, fechaInicio: DateTime(2026, 1, 6));

      expect(segundoIntento, isA<AsignarLineaTelefonicaYaAsignada>());
    });

    test('índice único parcial rechaza a nivel de BD una segunda asignación vigente para la misma línea', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      await asignacionLineaRepo.crear(lineaTelefonicaId: linea.id, empleadoId: empleado1.id, fechaInicio: DateTime(2026, 1, 5));

      await expectLater(
        asignacionLineaRepo.crear(lineaTelefonicaId: linea.id, empleadoId: empleado2.id, fechaInicio: DateTime(2026, 1, 6)),
        throwsA(anything),
        reason: 'idx_asignacion_linea_telefonica_vigente protege incluso saltándose el caso de uso',
      );
    });

    test('rechaza asignar una línea dada de baja', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      final resultado = await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsignarLineaTelefonicaLineaDeBaja>());
    });
  });

  group('CambiarAsignacionLineaTelefonicaUseCase', () {
    test('cambio Empleado→Servicio: cierra la anterior y crea la nueva', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final asignacionEmpleado = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;

      final resultado = await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: asignacionEmpleado.id,
        fecha: DateTime(2026, 3, 1),
        nuevoServicioId: servicio.id,
      );

      expect(resultado, isA<CambiarAsignacionLineaTelefonicaExitoso>());
      final nueva = (resultado as CambiarAsignacionLineaTelefonicaExitoso).nuevaAsignacion;
      expect(nueva.servicioId, servicio.id);

      final anteriorCerrada = await asignacionLineaRepo.obtenerPorId(asignacionEmpleado.id);
      expect(anteriorCerrada!.fechaTermino, DateTime(2026, 3, 1));
      expect(anteriorCerrada.motivoTermino, 'cambioResponsable');
    });

    test('cambio Servicio→Empleado', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final empleado = await crearEmpleadoDePrueba();

      final asignacionServicio = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;

      final resultado = await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: asignacionServicio.id,
        fecha: DateTime(2026, 3, 1),
        nuevoEmpleadoId: empleado.id,
      );

      expect(resultado, isA<CambiarAsignacionLineaTelefonicaExitoso>());
      expect((resultado as CambiarAsignacionLineaTelefonicaExitoso).nuevaAsignacion.empleadoId, empleado.id);
    });

    test('el historial conserva ambas filas intactas tras el cambio', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final primera = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      await cambiarAsignacion.ejecutar(asignacionLineaTelefonicaActualId: primera.id, fecha: DateTime(2026, 3, 1), nuevoServicioId: servicio.id);

      final historial = await asignacionLineaRepo.listarPorLinea(linea.id);
      expect(historial, hasLength(2));
    });

    test('rechaza cambiar una asignación ya cerrada', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();
      final asignacion = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      await retirarAsignacion.ejecutar(asignacionLineaTelefonicaId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      final resultado =
          await cambiarAsignacion.ejecutar(asignacionLineaTelefonicaActualId: asignacion.id, fecha: DateTime(2026, 3, 1), nuevoServicioId: servicio.id);
      expect(resultado, isA<CambiarAsignacionLineaTelefonicaYaCerrada>());
    });
  });

  group('RetirarAsignacionLineaTelefonicaUseCase', () {
    test('retira con motivo liberacion, la línea queda sin asignación', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;

      final resultado = await retirarAsignacion.ejecutar(asignacionLineaTelefonicaId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      expect(resultado, isA<RetirarAsignacionLineaTelefonicaExitoso>());
      expect((resultado as RetirarAsignacionLineaTelefonicaExitoso).asignacion.motivoTermino, 'liberacion');
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);
    });

    test('rechaza retirar una asignación ya cerrada', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      await retirarAsignacion.ejecutar(asignacionLineaTelefonicaId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      final segundoIntento = await retirarAsignacion.ejecutar(asignacionLineaTelefonicaId: asignacion.id, fechaTermino: DateTime(2026, 2, 2));
      expect(segundoIntento, isA<RetirarAsignacionLineaTelefonicaYaCerrada>());
    });
  });

  group('AsociarEquipoLineaTelefonicaUseCase', () {
    test('asocia una unidad de tipo teléfono disponible', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));

      expect(resultado, isA<AsociarEquipoLineaTelefonicaExitoso>());
      expect((resultado as AsociarEquipoLineaTelefonicaExitoso).equipo.unidadId, unidad.id);
    });

    test('rechaza una unidad que no es teléfono (sin ArticuloUnidadTelefono)', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadNoTelefonoDePrueba(articulo.id);

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaUnidadNoEsTelefono>());
    });

    test('rechaza una unidad no disponible', () async {
      final linea = await crearLineaDePrueba();
      final otraLinea = await crearLineaDePrueba(numero: '7229999999');
      final otroEmpleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      // El equipo queda "asignado" en Inventario solo cuando la línea
      // dueña tiene, a su vez, una asignación vigente — la sincronización
      // se dispara ahí, no al asociar el equipo por sí solo.
      await asignarLinea.ejecutar(lineaTelefonicaId: otraLinea.id, empleadoId: otroEmpleado.id, fechaInicio: DateTime(2026, 1, 1));
      await asociarEquipo.ejecutar(lineaTelefonicaId: otraLinea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaUnidadNoDisponible>());
    });

    test('rechaza si la línea ya tiene un equipo vigente', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad1 = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-TEL-0001');
      final unidad2 = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-TEL-0002');
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad1.id, fechaInicio: DateTime(2026, 1, 5));

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad2.id, fechaInicio: DateTime(2026, 2, 1));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaYaTieneEquipo>());
    });

    test('rechaza asociar equipo a una línea dada de baja', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaLineaDeBaja>());
    });
  });

  group('CambiarEquipoLineaTelefonicaUseCase — ejemplo de Marlon: cambiar de teléfono sin crear una línea nueva', () {
    test('sustituye el equipo, la línea (código y número) no cambia, el historial conserva ambas filas', () async {
      final linea = await crearLineaDePrueba(numero: '7221234567');
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidadVieja = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'UNI-000003');
      final unidadNueva = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'UNI-000020');
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidadVieja.id, fechaInicio: DateTime(2026, 1, 5));

      final resultado =
          await cambiarEquipo.ejecutar(lineaTelefonicaId: linea.id, nuevaUnidadId: unidadNueva.id, fecha: DateTime(2026, 7, 1));

      expect(resultado, isA<CambiarEquipoLineaTelefonicaExitoso>());
      expect((resultado as CambiarEquipoLineaTelefonicaExitoso).equipo.unidadId, unidadNueva.id);

      final lineaTrasCambio = await lineaRepo.obtenerPorId(linea.id);
      expect(lineaTrasCambio!.numero, '7221234567', reason: 'cambiar el teléfono nunca crea una línea nueva');
      expect(lineaTrasCambio.id, linea.id);

      final historial = await equipoRepo.listarPorLinea(linea.id);
      expect(historial, hasLength(2));

      final unidadViejaLiberada = await inventarioRepo.obtenerUnidadPorId(unidadVieja.id);
      expect(unidadViejaLiberada!.estatus, EstatusArticuloUnidad.disponible.name, reason: 'la unidad sustituida vuelve a estar disponible');
    });

    test('rechaza cambiar equipo si la línea no tiene uno vigente', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);

      final resultado = await cambiarEquipo.ejecutar(lineaTelefonicaId: linea.id, nuevaUnidadId: unidad.id, fecha: DateTime(2026, 1, 5));
      expect(resultado, isA<CambiarEquipoLineaTelefonicaSinEquipoVigente>());
    });
  });

  group('RetirarEquipoLineaTelefonicaUseCase', () {
    test('retira sin reemplazo, la línea queda sin equipo', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));

      final resultado = await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 2, 1));

      expect(resultado, isA<RetirarEquipoLineaTelefonicaExitoso>());
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNull);
    });

    test('rechaza retirar si no hay equipo vigente', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 2, 1));
      expect(resultado, isA<RetirarEquipoLineaTelefonicaSinEquipoVigente>());
    });
  });

  group('Consistencia con Inventario (punto 5 de 9B — el más importante)', () {
    test('asignar la línea sincroniza la custodia real en Inventario cuando moverEquipoAsociado=true', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      final custodia = await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id);
      expect(custodia, isNotNull, reason: 'Inventario sigue siendo la única fuente de custodia — Telefonía compone su caso de uso real');
      expect(custodia!.empleadoId, empleado.id);

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, EstatusArticuloUnidad.asignado.name);
    });

    test('asignar la línea con moverEquipoAsociado=false no toca Inventario ("no automatismos sorprendentes")', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
        moverEquipoAsociado: false,
      );

      expect(await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id), isNull);
    });

    test('cambio de asignación Empleado→Servicio mueve la custodia: cierra la anterior en Inventario y abre la nueva', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));
      final asignacionEmpleado = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      final custodiaOriginalId = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!.id;

      await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: asignacionEmpleado.id,
        fecha: DateTime(2026, 3, 1),
        nuevoServicioId: servicio.id,
      );

      final custodiaNueva = await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id);
      expect(custodiaNueva, isNotNull);
      expect(custodiaNueva!.servicioId, servicio.id);
      expect(custodiaNueva.empleadoId, isNull);

      final custodiaOriginalCerrada = await inventarioAsignacionRepo.obtenerPorId(custodiaOriginalId);
      expect(custodiaOriginalCerrada!.estatus, 'devuelta');
    });

    test('retirar la asignación libera la custodia en Inventario, la unidad vuelve a disponible', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));
      final asignacion = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;

      await retirarAsignacion.ejecutar(asignacionLineaTelefonicaId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      expect(await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id), isNull);
      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, EstatusArticuloUnidad.disponible.name);
    });

    test('guardia de divergencia: si Inventario reasigna la unidad directamente, retirar el equipo no la pisa', () async {
      // La guardia de divergencia vive en las operaciones de EQUIPO
      // (retirar/cambiar), que capturan el destino esperado de la línea
      // sin haberlo modificado ellas mismas — a diferencia de
      // `sincronizarConAsignacionVigente` (usada por Asignar/Cambiar/
      // Retirar ASIGNACIÓN), que documentadamente sí mueve la custodia
      // al nuevo destino de la línea (o la libera si éste quedó nulo),
      // porque ahí el usuario pidió explícitamente "mover equipo
      // asociado" para ese cambio de destino.
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado1.id, fechaInicio: DateTime(2026, 1, 5));
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      // La asignación de la línea sigue vigente con empleado1 — nunca se
      // toca en este escenario.

      // Alguien reasigna la unidad directamente en Inventario, sin
      // pasar por Telefonía — simula "entregaron físicamente el
      // teléfono equivocado" (escenario real que el punto 5 describe).
      final custodiaOriginal = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!;
      await inventarioAsignacionRepo.cerrar(
        asignacionId: custodiaOriginal.id,
        motivo: 'otro',
        fechaCierre: DateTime(2026, 1, 20),
        observacionesCierre: 'Reasignado manualmente desde Inventario.',
      );
      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado2.id,
        fechaEntrega: DateTime(2026, 1, 20),
      );

      await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 2, 1));

      final custodiaTrasRetiro = await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id);
      expect(custodiaTrasRetiro, isNotNull, reason: 'la reasignación manual hecha en Inventario nunca se pisa desde Telefonía');
      expect(custodiaTrasRetiro!.empleadoId, empleado2.id);
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNull, reason: 'la línea sí queda sin equipo — solo la custodia divergente se protege');
    });

    test('cambiar de equipo mueve la custodia del equipo viejo al nuevo, ambos coherentes con el destino de la línea', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidadVieja = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-TEL-A');
      final unidadNueva = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-TEL-B');
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidadVieja.id, fechaInicio: DateTime(2026, 1, 1));
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 5));

      await cambiarEquipo.ejecutar(lineaTelefonicaId: linea.id, nuevaUnidadId: unidadNueva.id, fecha: DateTime(2026, 3, 1));

      expect(await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadVieja.id), isNull);
      final custodiaNueva = await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadNueva.id);
      expect(custodiaNueva, isNotNull);
      expect(custodiaNueva!.servicioId, servicio.id);
    });

    test('baja de línea cierra asignación y equipo, libera la custodia, pero no da de baja el teléfono físico', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));

      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      final asignacionCerrada = await asignacionLineaRepo.obtenerActivaPorLinea(linea.id);
      expect(asignacionCerrada, isNull);
      final equipoCerrado = await equipoRepo.obtenerActualPorLinea(linea.id);
      expect(equipoCerrado, isNull);

      expect(await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id), isNull, reason: 'la custodia se libera');
      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(
        unidadActualizada!.estatus,
        EstatusArticuloUnidad.disponible.name,
        reason: 'la baja de la línea nunca da de baja el teléfono físico — sigue siendo un activo de Inventario, ahora disponible',
      );
    });

    test('baja de línea sin asignación ni equipo vigentes no falla (no-op)', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);
      expect(resultado, isA<DarDeBajaLineaTelefonicaExitoso>());
    });

    test('obtenerCustodiaInventarioActual refleja la custodia real reportada por Inventario, sin duplicar datos', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      expect(await equipoRepo.obtenerCustodiaInventarioActual(unidad.id), isNull);

      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 5));

      final custodia = await equipoRepo.obtenerCustodiaInventarioActual(unidad.id);
      expect(custodia!.servicioId, servicio.id);
    });

    test('obtenerActualPorUnidad resuelve la línea actual desde el expediente de la unidad de Inventario', () async {
      final linea = await crearLineaDePrueba(numero: '7221234567');
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);

      expect(await equipoRepo.obtenerActualPorUnidad(unidad.id), isNull);

      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));

      final equipo = await equipoRepo.obtenerActualPorUnidad(unidad.id);
      expect(equipo!.lineaTelefonicaId, linea.id);
    });
  });
}
