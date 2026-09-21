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
    equipoRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, inventarioAsignacionRepo);
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);

    crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
    darDeBaja = DarDeBajaLineaTelefonicaUseCase(lineaRepo);
    asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);
    cambiarAsignacion = CambiarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoRepo, lineaRepo);
    retirarAsignacion = RetirarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoRepo, lineaRepo);
    asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo, asignacionLineaRepo);
    cambiarEquipo = CambiarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo, asignacionLineaRepo);
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

    test('rechaza una unidad que ya trae otra línea — un teléfono, una SIM', () async {
      final linea = await crearLineaDePrueba();
      final otraLinea = await crearLineaDePrueba(numero: '7229999999');
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: otraLinea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaUnidadYaTraeOtraLinea>());
    });

    test('rechaza una unidad que no puede traer una SIM (dada de baja)', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await inventarioRepo.registrarBajaUnidad(unidadId: unidad.id, observaciones: 'Robada');

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaUnidadNoDisponible>());
    });

    test('una unidad YA entregada en Inventario sí es asociable — es el orden correcto', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 1, 1),
      );
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsociarEquipoLineaTelefonicaExitoso>(), reason: '$resultado');
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

  group('Inventario manda: Telefonía nunca mueve la custodia (Rebanada 2)', () {
    /// Entrega el aparato por el camino de Inventario — el único que
    /// puede crear custodia.
    Future<void> entregarEnInventario(String articuloId, String unidadId, {String? empleadoId, String? servicioId}) async {
      await inventarioAsignacionRepo.crear(
        articuloId: articuloId,
        unidadId: unidadId,
        cantidad: 1,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaEntrega: DateTime(2026, 1, 1),
      );
    }

    test('§8 — asignar la línea cuando su equipo NO tiene custodia se rechaza, y nada se persiste', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      expect(resultado, isA<AsignarLineaTelefonicaIncoherenteConEquipo>());
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);
      expect(await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id), isNull,
          reason: 'Telefonía jamás crea custodia');
    });

    test('§9 — asignar la línea al MISMO destino que la custodia sí se permite, y no toca Inventario', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, empleadoId: empleado.id);
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );
      // La asociación ya alineó la línea; se retira para probar el alta.
      final yaCreada = await asignacionLineaRepo.obtenerActivaPorLinea(linea.id);
      expect(yaCreada, isNotNull, reason: '§7: asociar con custodia alinea la línea');
      expect(yaCreada!.empleadoId, empleado.id);

      final custodia = await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id);
      expect(custodia!.empleadoId, empleado.id, reason: 'la custodia es la misma de antes, intacta');
    });

    test('§11 — cambiar la asignación dejando el equipo en manos del anterior se rechaza', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, empleadoId: empleado.id);
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );
      final vigente = (await asignacionLineaRepo.obtenerActivaPorLinea(linea.id))!;

      final resultado = await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: vigente.id,
        fecha: DateTime(2026, 3, 1),
        nuevoServicioId: servicio.id,
      );

      expect(resultado, isA<CambiarAsignacionLineaTelefonicaIncoherenteConEquipo>());
      final sigue = await asignacionLineaRepo.obtenerActivaPorLinea(linea.id);
      expect(sigue!.id, vigente.id, reason: 'el rechazo ocurre ANTES de persistir');
      expect(sigue.empleadoId, empleado.id);
    });

    test('§12 — retirar la asignación con el equipo todavía custodiado se rechaza (el caso MILOYILE)', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, servicioId: servicio.id);
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );
      final vigente = (await asignacionLineaRepo.obtenerActivaPorLinea(linea.id))!;

      final resultado = await retirarAsignacion.ejecutar(
        asignacionLineaTelefonicaId: vigente.id,
        fechaTermino: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<RetirarAsignacionLineaTelefonicaEquipoCustodiado>());
      expect((await asignacionLineaRepo.obtenerActivaPorLinea(linea.id))!.id, vigente.id);
    });

    test('§19 — retirar el equipo NO devuelve el aparato: la custodia sigue igual', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, servicioId: servicio.id);
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 2, 1));

      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNull, reason: 'la línea sí queda sin equipo');
      final custodia = await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id);
      expect(custodia, isNotNull, reason: 'desvincular la SIM no devuelve físicamente el teléfono');
      expect(custodia!.servicioId, servicio.id);
      expect((await inventarioRepo.obtenerUnidadPorId(unidad.id))!.estatus, EstatusArticuloUnidad.asignado.name);
    });

    test('§19 — cambiar de equipo conserva el historial y no mueve ninguna custodia', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidadVieja = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-TEL-A');
      final unidadNueva = await crearUnidadTelefonoDePrueba(articulo.id, numeroSerie: 'SN-TEL-B');
      await entregarEnInventario(articulo.id, unidadVieja.id, servicioId: servicio.id);
      await entregarEnInventario(articulo.id, unidadNueva.id, servicioId: servicio.id);
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidadVieja.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      final resultado = await cambiarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        nuevaUnidadId: unidadNueva.id,
        fecha: DateTime(2026, 3, 1),
      );
      expect(resultado, isA<CambiarEquipoLineaTelefonicaExitoso>(), reason: '$resultado');

      expect((await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadVieja.id))!.servicioId, servicio.id,
          reason: 'el teléfono viejo sigue donde Inventario lo dejó');
      expect((await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidadNueva.id))!.servicioId, servicio.id);

      final historial = await equipoRepo.listarPorLinea(linea.id);
      expect(historial, hasLength(2), reason: 'se cierra un periodo y se abre otro, nunca se reescribe');
      expect(historial.where((e) => e.fechaFin == null), hasLength(1));
    });

    test('§10 — asociar un equipo cuya custodia es de OTRO destino se rechaza', () async {
      final linea = await crearLineaDePrueba();
      final servicioA = await crearServicioDePrueba();
      final servicioB = await crearServicioDePrueba(codigo: 'SER-000002');
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, servicioId: servicioB.id);
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, servicioId: servicioA.id, fechaInicio: DateTime(2026, 1, 1));

      final resultado = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      expect(resultado, isA<AsociarEquipoLineaTelefonicaDestinosDistintos>());
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNull);
    });

    test('§7 — asociar sin confirmar la alineación no persiste nada; confirmando, alinea SÓLO la línea', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, servicioId: servicio.id);

      final sinConfirmar = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
      );
      expect(sinConfirmar, isA<AsociarEquipoLineaTelefonicaRequiereAlinearLinea>());
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNull);
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);

      final custodiaAntes = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!;
      final confirmando = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
        alinearLineaConCustodia: true,
      );
      expect(confirmando, isA<AsociarEquipoLineaTelefonicaExitoso>(), reason: '$confirmando');
      expect((await asignacionLineaRepo.obtenerActivaPorLinea(linea.id))!.servicioId, servicio.id);
      expect((await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!.id, custodiaAntes.id,
          reason: 'la MISMA fila de custodia: Inventario no se tocó');
    });

    test('baja de línea cierra asignación y equipo, y NO devuelve el teléfono a Inventario', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await entregarEnInventario(articulo.id, unidad.id, servicioId: servicio.id);
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNull);
      expect((await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!.servicioId, servicio.id,
          reason: 'que se cancele la SIM no recupera el aparato — eso lo decide Inventario');
    });

    test('baja de línea sin asignación ni equipo vigentes no falla (no-op)', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);
      expect(resultado, isA<DarDeBajaLineaTelefonicaExitoso>());
    });

    test('obtenerCustodiaInventarioActual refleja la custodia real de Inventario, sin duplicar datos', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefonoDePrueba();
      final unidad = await crearUnidadTelefonoDePrueba(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 1));

      expect(await equipoRepo.obtenerCustodiaInventarioActual(unidad.id), isNull);

      await entregarEnInventario(articulo.id, unidad.id, servicioId: servicio.id);

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
