// Coherencia Línea ↔ Equipo ↔ Custodia de Inventario (Rebanada 2).
//
// El caso real que originó la etapa: la línea 7291220187 sin asignación,
// su equipo UNI-000001 bajo custodia de MILOYILE, y Telefonía mostrando
// sólo una advertencia a toro pasado.
//
// Lo que estas pruebas fijan:
//   1. la regla central es UNA, pura, y compara por tipo + FK — nunca
//      por el nombre que se muestra;
//   2. ningún flujo normal de Telefonía puede dejar la contradicción;
//   3. resolver una inconsistencia histórica exige motivo y no toca
//      Inventario;
//   4. cuando Inventario mueve la custodia, la línea la sigue.

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
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_de_unidad_coordinador.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/asignacion_linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/obtener_coherencia_linea_equipo_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  // =================================================================
  // §4 / §30 — LA REGLA, EN AISLAMIENTO
  // =================================================================
  group('La regla central (función pura)', () {
    const empleadoA = DestinoTelefonia.empleado('emp-A');
    const empleadoB = DestinoTelefonia.empleado('emp-B');
    const servicioA = DestinoTelefonia.servicio('srv-A');
    const servicioB = DestinoTelefonia.servicio('srv-B');

    EstadoCoherenciaLineaEquipo estado({
      String? unidadId = 'uni-1',
      DestinoTelefonia? linea,
      DestinoTelefonia? equipo,
    }) {
      return evaluarCoherenciaLineaEquipo(
        unidadId: unidadId,
        destinoLinea: linea,
        destinoEquipo: equipo,
      ).estado;
    }

    test('§5 — línea sin equipo: no hay nada que comparar, esté o no asignada', () {
      expect(estado(unidadId: null), EstadoCoherenciaLineaEquipo.sinEquipo);
      expect(estado(unidadId: null, linea: empleadoA), EstadoCoherenciaLineaEquipo.sinEquipo);
      expect(estado(unidadId: null, linea: servicioA), EstadoCoherenciaLineaEquipo.sinEquipo);
      expect(
        evaluarCoherenciaLineaEquipo(unidadId: null, destinoLinea: empleadoA, destinoEquipo: null).esCoherente,
        isTrue,
        reason: 'una SIM suelta asignada es un estado válido',
      );
    });

    test('§6 — línea y equipo ambos sin destino: coherente', () {
      expect(estado(), EstadoCoherenciaLineaEquipo.coherente);
    });

    test('§7 — equipo con custodia y línea sin asignación', () {
      expect(estado(equipo: servicioA), EstadoCoherenciaLineaEquipo.lineaSinAsignacion);
      expect(estado(equipo: empleadoA), EstadoCoherenciaLineaEquipo.lineaSinAsignacion);
    });

    test('§8 — línea asignada y equipo sin custodia', () {
      expect(estado(linea: servicioA), EstadoCoherenciaLineaEquipo.equipoSinCustodia);
      expect(estado(linea: empleadoA), EstadoCoherenciaLineaEquipo.equipoSinCustodia);
    });

    test('§9 — mismo destino: coherente, tanto Servicio como Empleado', () {
      expect(estado(linea: servicioA, equipo: servicioA), EstadoCoherenciaLineaEquipo.coherente);
      expect(estado(linea: empleadoA, equipo: empleadoA), EstadoCoherenciaLineaEquipo.coherente);
    });

    test('§10 — destinos distintos', () {
      expect(estado(linea: servicioA, equipo: servicioB), EstadoCoherenciaLineaEquipo.destinosDistintos);
      expect(estado(linea: empleadoA, equipo: empleadoB), EstadoCoherenciaLineaEquipo.destinosDistintos);
    });

    test('§30.11 — Empleado vs Servicio es inconsistente AUNQUE el id coincida', () {
      const mismoId = 'colision-imposible-pero-probada';
      expect(
        estado(
          linea: const DestinoTelefonia.empleado(mismoId),
          equipo: const DestinoTelefonia.servicio(mismoId),
        ),
        EstadoCoherenciaLineaEquipo.destinosDistintos,
        reason: 'la comparación es tipo + FK, nunca sólo el id',
      );
      expect(const DestinoTelefonia.empleado(mismoId) == const DestinoTelefonia.servicio(mismoId), isFalse);
    });

    test('la comparación no usa el nombre mostrado: dos destinos distintos con el mismo nombre siguen siendo distintos', () {
      // El nombre ni siquiera entra en el dominio — `DestinoTelefonia`
      // no tiene campo para él. Esta prueba fija justamente eso.
      expect(estado(linea: servicioA, equipo: servicioB), EstadoCoherenciaLineaEquipo.destinosDistintos);
      expect(servicioA == const DestinoTelefonia.servicio('srv-A'), isTrue);
    });

    test('destinoDe descarta un destino ambiguo o vacío en lugar de inventarlo', () {
      expect(destinoDe(), isNull);
      expect(destinoDe(empleadoId: '', servicioId: ''), isNull);
      expect(destinoDe(empleadoId: 'x', servicioId: 'y'), isNull);
      expect(destinoDe(empleadoId: 'x'), const DestinoTelefonia.empleado('x'));
      expect(destinoDe(servicioId: 'y'), const DestinoTelefonia.servicio('y'));
    });

    test('esResolucionDeInconsistencia distingue corregir historia de operar a diario', () {
      final corrige = evaluarCambioAsignacionLinea(
        unidadId: 'uni-1',
        destinoLineaActual: null,
        destinoEquipo: servicioA,
        destinoPropuesto: servicioA,
      );
      expect(corrige.esResolucionDeInconsistencia, isTrue);
      expect(corrige.dejariaContradiccion, isFalse);

      final cotidiana = evaluarCambioAsignacionLinea(
        unidadId: null,
        destinoLineaActual: null,
        destinoEquipo: null,
        destinoPropuesto: servicioA,
      );
      expect(cotidiana.esResolucionDeInconsistencia, isFalse);

      final rompe = evaluarCambioAsignacionLinea(
        unidadId: 'uni-1',
        destinoLineaActual: servicioA,
        destinoEquipo: servicioA,
        destinoPropuesto: servicioB,
      );
      expect(rompe.dejariaContradiccion, isTrue);
    });
  });

  // =================================================================
  // Contra la base real
  // =================================================================
  group('Contra datos reales', () {
    late AppDatabase db;
    late AsignacionLineaTelefonicaRepositoryImpl asignacionLineaRepo;
    late AsignacionRepositoryImpl inventarioAsignacionRepo;
    late InventarioRepositoryImpl inventarioRepo;
    late LineaTelefonicaEquipoRepositoryImpl equipoRepo;
    late LineaTelefonicaRepositoryImpl lineaRepo;
    late ObtenerCoherenciaLineaEquipoUseCase coherencia;

    late CrearLineaTelefonicaUseCase crearLinea;
    late AsignarLineaTelefonicaUseCase asignarLinea;
    late CambiarAsignacionLineaTelefonicaUseCase cambiarAsignacion;
    late AsociarEquipoLineaTelefonicaUseCase asociarEquipo;
    late CambiarEquipoLineaTelefonicaUseCase cambiarEquipo;
    late RetirarEquipoLineaTelefonicaUseCase retirarEquipo;
    late CerrarAsignacionUseCase cerrarAsignacion;
    late RegistrarBajaUnidadUseCase registrarBajaUnidad;
    late CrearCategoriaArticuloUseCase crearCategoria;
    late CrearArticuloUseCase crearArticulo;
    late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
      inventarioAsignacionRepo = AsignacionRepositoryImpl(db);
      inventarioRepo = InventarioRepositoryImpl(db);
      final articuloRepo = ArticuloRepositoryImpl(db);
      equipoRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, inventarioAsignacionRepo);
      lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
      coherencia = ObtenerCoherenciaLineaEquipoUseCase(equipoRepo, asignacionLineaRepo);

      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);

      crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
      asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);
      cambiarAsignacion = CambiarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoRepo, lineaRepo);
      asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo, asignacionLineaRepo);
      cambiarEquipo = CambiarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo, asignacionLineaRepo);
      retirarEquipo = RetirarEquipoLineaTelefonicaUseCase(equipoRepo);
      cerrarAsignacion = CerrarAsignacionUseCase(inventarioAsignacionRepo);
      registrarBajaUnidad = RegistrarBajaUnidadUseCase(inventarioRepo, LineaTelefonicaDeUnidadCoordinador.desde(db));
      crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
      crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
      registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
    });

    tearDown(() => db.close());

    Future<LineaTelefonicaData> crearLineaDePrueba({String? numero}) async {
      final r = await crearLinea.ejecutar(numero: numero, operador: 'telcel', modalidadSim: 'fisica');
      return (r as CrearLineaTelefonicaExitoso).linea;
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

    Future<ServicioData> crearServicioDePrueba({String codigo = 'SER-000001', String nombre = 'MILOYILE'}) async {
      final tipoServicio = await db.into(db.tipoServicio).insertReturning(
          TipoServicioCompanion.insert(id: 'tipo-$codigo', codigo: 'VIG-$codigo', nombre: 'Vigilancia fija'));
      final cliente = await db
          .into(db.cliente)
          .insertReturning(ClienteCompanion.insert(codigo: 'CLI-$codigo', nombreComercial: nombre));
      return db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: codigo,
              clienteId: cliente.id,
              nombre: nombre,
              tipoServicioId: tipoServicio.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
    }

    Future<ArticuloData> crearArticuloTelefono() async {
      final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
      final r = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Smartphone', manejaSerie: true);
      return (r as CrearArticuloExitoso).articulo;
    }

    Future<ArticuloUnidadData> crearUnidad(String articuloId, {String numeroSerie = 'SN-TEL-0001'}) async {
      final r = await registrarEntradaUnidad.ejecutar(
        articuloId: articuloId,
        numeroSerie: numeroSerie,
        imei: '35$numeroSerie',
        fecha: DateTime(2026, 1, 1),
      );
      return (r as RegistrarEntradaUnidadExitoso).unidad;
    }

    /// Reproduce el estado exacto del caso real: unidad bajo custodia de
    /// un Servicio, línea asociada a esa unidad y SIN asignación. Se
    /// arma insertando la asociación directo, que es como quedó en la
    /// base — los flujos nuevos ya no permiten llegar ahí.
    Future<({LineaTelefonicaData linea, ArticuloUnidadData unidad, ServicioData servicio})> armarCasoLegacy() async {
      final linea = await crearLineaDePrueba(numero: '7291220187');
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);
      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2025, 11, 1),
      );
      await db.into(db.lineaTelefonicaEquipo).insert(
            LineaTelefonicaEquipoCompanion.insert(
              lineaTelefonicaId: linea.id,
              unidadId: unidad.id,
              fechaInicio: DateTime(2025, 11, 1),
            ),
          );
      return (linea: linea, unidad: unidad, servicio: servicio);
    }

    test('§32 — el caso real se detecta como inconsistente, con los dos destinos reales', () async {
      final caso = await armarCasoLegacy();

      final c = await coherencia.ejecutar(caso.linea.id);
      expect(c.estado, EstadoCoherenciaLineaEquipo.lineaSinAsignacion);
      expect(c.esInconsistencia, isTrue);
      expect(c.destinoLinea, isNull);
      expect(c.destinoEquipo, DestinoTelefonia.servicio(caso.servicio.id));
      expect(c.unidadId, caso.unidad.id);
    });

    test('§20 — detectarlo NO lo modifica: la historia se queda como está', () async {
      final caso = await armarCasoLegacy();
      final custodiaAntes = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(caso.unidad.id))!;

      await coherencia.ejecutar(caso.linea.id);
      await coherencia.ejecutar(caso.linea.id);

      expect(await asignacionLineaRepo.obtenerActivaPorLinea(caso.linea.id), isNull);
      expect((await inventarioAsignacionRepo.obtenerActivaPorUnidad(caso.unidad.id))!.id, custodiaAntes.id);
    });

    test('§22 — resolver sin motivo se rechaza y no persiste nada', () async {
      final caso = await armarCasoLegacy();

      final r = await asignarLinea.ejecutar(
        lineaTelefonicaId: caso.linea.id,
        servicioId: caso.servicio.id,
        fechaInicio: DateTime(2026, 9, 1),
      );

      expect(r, isA<AsignarLineaTelefonicaMotivoRequerido>());
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(caso.linea.id), isNull);
      expect(await lineaRepo.listarEventos(caso.linea.id), isEmpty);
    });

    test('§21/§22 — resolver con motivo alinea SÓLO la línea y deja asiento auditable', () async {
      final caso = await armarCasoLegacy();
      final custodiaAntes = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(caso.unidad.id))!;

      final r = await asignarLinea.ejecutar(
        lineaTelefonicaId: caso.linea.id,
        servicioId: caso.servicio.id,
        fechaInicio: DateTime(2026, 9, 1),
        motivo: 'Regularización: el equipo ya estaba entregado a MILOYILE.',
        actorUsuarioId: null,
      );

      expect(r, isA<AsignarLineaTelefonicaExitoso>(), reason: '$r');
      expect((await asignacionLineaRepo.obtenerActivaPorLinea(caso.linea.id))!.servicioId, caso.servicio.id);

      final custodiaDespues = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(caso.unidad.id))!;
      expect(custodiaDespues.id, custodiaAntes.id, reason: 'la MISMA fila: Inventario no se tocó');

      final eventos = await lineaRepo.listarEventos(caso.linea.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, TipoEventoLineaTelefonica.incoherenciaResuelta.name);
      expect(eventos.single.observacion, contains('Regularización'));
      expect(eventos.single.estadoAnterior, contains('lineaSinAsignacion'));
      expect(eventos.single.estadoNuevo, contains('coherente'));

      expect((await coherencia.ejecutar(caso.linea.id)).esCoherente, isTrue,
          reason: 'la advertencia desaparece después de resolver');
    });

    test('§23 — una asociación cotidiana coherente NO exige motivo ni genera evento de corrección', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);

      final r = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      expect(r, isA<AsociarEquipoLineaTelefonicaExitoso>(), reason: '$r');
      expect(await lineaRepo.listarEventos(linea.id), isEmpty);
      expect((await coherencia.ejecutar(linea.id)).estado, EstadoCoherenciaLineaEquipo.coherente);
    });

    test('§21 — resolver destinos distintos alinea la línea con la custodia, nunca al revés', () async {
      final linea = await crearLineaDePrueba();
      final servicioA = await crearServicioDePrueba(codigo: 'SER-A', nombre: 'Servicio A');
      final servicioB = await crearServicioDePrueba(codigo: 'SER-B', nombre: 'Servicio B');
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);

      // Estado contradictorio armado directo (los flujos ya no lo
      // permiten): custodia en B, línea en A.
      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicioB.id,
        fechaEntrega: DateTime(2026, 1, 1),
      );
      final vigente = await asignacionLineaRepo.crear(
        lineaTelefonicaId: linea.id,
        servicioId: servicioA.id,
        fechaInicio: DateTime(2026, 1, 1),
      );
      await db.into(db.lineaTelefonicaEquipo).insert(
            LineaTelefonicaEquipoCompanion.insert(
              lineaTelefonicaId: linea.id,
              unidadId: unidad.id,
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
      expect((await coherencia.ejecutar(linea.id)).estado, EstadoCoherenciaLineaEquipo.destinosDistintos);

      final r = await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: vigente.id,
        fecha: DateTime(2026, 9, 1),
        nuevoServicioId: servicioB.id,
        motivo: 'La línea apuntaba al servicio equivocado.',
      );

      expect(r, isA<CambiarAsignacionLineaTelefonicaExitoso>(), reason: '$r');
      expect((await coherencia.ejecutar(linea.id)).esCoherente, isTrue);
      expect((await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!.servicioId, servicioB.id,
          reason: 'Inventario intacto: la custodia no se movió para complacer a Telefonía');

      final historial = await asignacionLineaRepo.listarPorLinea(linea.id);
      expect(historial, hasLength(2), reason: '§24 — se cierra el periodo y se abre otro');
      expect(historial.firstWhere((a) => a.fechaTermino != null).servicioId, servicioA.id);
    });

    // ---------------------------------------------------------------
    // §31 — barrido de las operaciones de Inventario que mueven custodia
    // ---------------------------------------------------------------
    test('§31 — devolver el teléfono en Inventario cierra la asignación de la línea, con motivo propio', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);
      final asignacion = await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 1, 1),
      );
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 5, 1),
      );

      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull,
          reason: '§16 — ya no hay destino físico al que la línea acompañe');
      final cerrada = (await asignacionLineaRepo.listarPorLinea(linea.id)).single;
      expect(cerrada.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.custodiaEquipoTerminada.name);
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNotNull,
          reason: '§16 — la asociación Línea↔Equipo NO se borra por una devolución');
      expect((await coherencia.ejecutar(linea.id)).esCoherente, isTrue);
    });

    test('§31 — entregar en Inventario un teléfono que ya trae línea alinea la línea sola', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 2));
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);

      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 3, 1),
      );

      final vigente = await asignacionLineaRepo.obtenerActivaPorLinea(linea.id);
      expect(vigente!.empleadoId, empleado.id, reason: 'Inventario manda: la línea sigue al aparato');
      expect((await coherencia.ejecutar(linea.id)).esCoherente, isTrue);
    });

    test('§18 — dar de baja un teléfono que todavía trae línea se rechaza', () async {
      final linea = await crearLineaDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);
      await asociarEquipo.ejecutar(lineaTelefonicaId: linea.id, unidadId: unidad.id, fechaInicio: DateTime(2026, 1, 2));

      final r = await registrarBajaUnidad.ejecutar(unidadId: unidad.id, observaciones: 'Pantalla rota sin arreglo');

      expect(r, isA<RegistrarBajaUnidadTraeLineaTelefonica>());
      expect((await inventarioRepo.obtenerUnidadPorId(unidad.id))!.estatus, EstatusArticuloUnidad.disponible.name);

      // La salida: retirar el equipo de la línea. La línea sobrevive y
      // puede recibir otro aparato — ciclos de vida distintos (§18).
      await retirarEquipo.ejecutar(lineaTelefonicaId: linea.id, fechaFin: DateTime(2026, 4, 1));
      final segunda = await registrarBajaUnidad.ejecutar(unidadId: unidad.id, observaciones: 'Pantalla rota sin arreglo');
      expect(segunda, isA<RegistrarBajaUnidadExitoso>());

      final otraUnidad = await crearUnidad(articulo.id, numeroSerie: 'SN-TEL-0002');
      final reasociada = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: otraUnidad.id,
        fechaInicio: DateTime(2026, 4, 2),
      );
      expect(reasociada, isA<AsociarEquipoLineaTelefonicaExitoso>(), reason: '$reasociada');
      expect(await equipoRepo.listarPorLinea(linea.id), hasLength(2), reason: 'la historia del aparato de baja se conserva');
    });

    test('§17 — un estado físico intermedio no es custodia: no altera la coherencia', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);
      final asignacion = await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 1, 1),
      );
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      // Vuelve a RISEG pero al taller: la custodia terminó igual, y lo
      // que decide es la custodia, nunca el texto del estatus físico.
      await inventarioAsignacionRepo.cerrar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.defecto.name,
        fechaCierre: DateTime(2026, 5, 1),
        ubicacionUnidad: EstatusArticuloUnidad.enReparacion,
      );

      expect((await inventarioRepo.obtenerUnidadPorId(unidad.id))!.estatus, EstatusArticuloUnidad.enReparacion.name);
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);
      expect((await coherencia.ejecutar(linea.id)).esCoherente, isTrue);
    });

    test('§35 — la coherencia de N líneas se resuelve sin N+1', () async {
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefono();
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        final linea = await crearLineaDePrueba(numero: '722000000$i');
        final unidad = await crearUnidad(articulo.id, numeroSerie: 'SN-TEL-000$i');
        await inventarioAsignacionRepo.crear(
          articuloId: articulo.id,
          unidadId: unidad.id,
          cantidad: 1,
          servicioId: servicio.id,
          fechaEntrega: DateTime(2026, 1, 1),
        );
        await asociarEquipo.ejecutar(
          lineaTelefonicaId: linea.id,
          unidadId: unidad.id,
          fechaInicio: DateTime(2026, 1, 2),
          alinearLineaConCustodia: true,
        );
        ids.add(linea.id);
      }

      final mapa = await coherencia.ejecutarPorLineas(ids);

      expect(mapa, hasLength(5));
      expect(mapa.values.every((c) => c.esCoherente), isTrue);
      for (final id in ids) {
        expect(mapa[id]!.estado, (await coherencia.ejecutar(id)).estado,
            reason: 'el camino en lote y el individual no pueden discrepar');
      }
    });

    test('§25 — baja de empleado: la línea se cierra y el aparato queda PENDIENTE, estado visible y no silencioso', () async {
      final empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidad(articulo.id);
      final custodia = await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 1),
      );
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 1),
        motivo: 'renuncia',
      );

      // La baja cierra la línea (decisión cerrada de 5C/9B) pero el
      // aparato sigue en manos del ex-empleado, pendiente de
      // recuperación (v82). El par NO es una contradicción inventada:
      // es el estado real, y queda visible para resolverse, nunca
      // silencioso.
      expect(await asignacionLineaRepo.obtenerActivaPorLinea(linea.id), isNull);
      final durante = await coherencia.ejecutar(linea.id);
      expect(durante.estado, EstadoCoherenciaLineaEquipo.lineaSinAsignacion);
      final custodiaTrasBaja = (await inventarioAsignacionRepo.obtenerActivaPorUnidad(unidad.id))!;
      expect(custodiaTrasBaja.empleadoId, empleado.id,
          reason: 'v82 intacta: la baja NO finge devolución, el aparato sigue en sus manos');

      // Al recuperarlo (lo que hace la conciliación), todo cierra.
      await cerrarAsignacion.ejecutar(
        asignacionId: custodia.id,
        motivo: MotivoCierreAsignacion.bajaEmpleado,
        fechaCierre: DateTime(2026, 6, 15),
      );
      expect((await coherencia.ejecutar(linea.id)).esCoherente, isTrue);
      expect(await equipoRepo.obtenerActualPorLinea(linea.id), isNotNull,
          reason: 'la asociación Línea↔Equipo sobrevive a la baja');
    });

    test('cambiar de equipo por otro con la misma custodia mantiene la coherencia', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      final articulo = await crearArticuloTelefono();
      final vieja = await crearUnidad(articulo.id, numeroSerie: 'SN-A');
      final nueva = await crearUnidad(articulo.id, numeroSerie: 'SN-B');
      for (final u in [vieja, nueva]) {
        await inventarioAsignacionRepo.crear(
          articuloId: articulo.id,
          unidadId: u.id,
          cantidad: 1,
          servicioId: servicio.id,
          fechaEntrega: DateTime(2026, 1, 1),
        );
      }
      await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        unidadId: vieja.id,
        fechaInicio: DateTime(2026, 1, 2),
        alinearLineaConCustodia: true,
      );

      final r = await cambiarEquipo.ejecutar(
        lineaTelefonicaId: linea.id,
        nuevaUnidadId: nueva.id,
        fecha: DateTime(2026, 3, 1),
      );

      expect(r, isA<CambiarEquipoLineaTelefonicaExitoso>(), reason: '$r');
      expect((await coherencia.ejecutar(linea.id)).esCoherente, isTrue);
    });
  });
}
