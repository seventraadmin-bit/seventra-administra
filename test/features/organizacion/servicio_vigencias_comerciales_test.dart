import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/utils/clock.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_anotaciones_vigencia_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_linea_comercial_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/shared/horario_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

/// Reloj fijo para pruebas deterministas — demuestra el punto de
/// extensión pedido explícitamente (Etapa 4G.2): nada aquí depende del
/// reloj real de la máquina.
class _RelojFijo implements Clock {
  _RelojFijo(this._fecha);
  final DateTime _fecha;

  @override
  DateTime now() => _fecha;
}

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late PuestoRepositoryImpl puestoRepo;
  late CatalogoRepositoryImpl catalogoRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;

  // Reloj fijo compartido: "hoy" = 15 de agosto de 2026 — permite que
  // los casos reales (incremento de precio programado en agosto para
  // el 1 de enero siguiente, etc.) sean deterministas sin depender de
  // cuándo se ejecute la prueba.
  final hoy = DateTime(2026, 8, 15);
  late Clock clock;
  late CambiarVigenciaLineaComercialUseCase cambiarVigencia;
  late CerrarLineaComercialUseCase cerrarLinea;
  late CancelarVigenciaProgramadaUseCase cancelarProgramada;
  late ActualizarAnotacionesVigenciaUseCase actualizarAnotaciones;
  late ObtenerHistorialLineaComercialUseCase obtenerHistorial;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    puestoRepo = PuestoRepositoryImpl(db);
    catalogoRepo = CatalogoRepositoryImpl(db);
    clock = _RelojFijo(hoy);
    comercialRepo = ServicioComercialRepositoryImpl(db, clock: clock);
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator =
        LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, ConfiguracionCobroRepositoryImpl(db));

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    cambiarVigencia = CambiarVigenciaLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    cerrarLinea = CerrarLineaComercialUseCase(comercialRepo, clock);
    cancelarProgramada = CancelarVigenciaProgramadaUseCase(comercialRepo, clock);
    actualizarAnotaciones = ActualizarAnotacionesVigenciaUseCase(comercialRepo, clock);
    obtenerHistorial = ObtenerHistorialLineaComercialUseCase(comercialRepo, puestoRepo, catalogoRepo, clock);
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({String codigo = 'CLI-000001', String nombre = 'Sportium'}) {
    return clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
  }

  Future<ServicioData> crearServicioDePrueba(String clienteId) async {
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<PuestoData> crearPuestoDePrueba({String codigo = 'PUE-0001', String nombre = 'Guardia'}) {
    return puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: codigo,
        nombre: nombre,
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
  }

  Future<({ServicioData servicio, String lineaId, PuestoData puesto})> crearServicioConLineaDePrueba() async {
    final cliente = await crearClienteDePrueba();
    final servicio = await crearServicioDePrueba(cliente.id);
    final guardia = await crearPuestoDePrueba();

    final creada = await crearLineaComercial.ejecutar(
      servicioId: servicio.id,
      borrador: LineaComercialBorrador(
        puestoId: guardia.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 2,
        precioUnitario: 1500000,
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    ) as CrearLineaComercialExitoso;

    return (servicio: servicio, lineaId: creada.linea.id, puesto: guardia);
  }

  group('Casos reales obligatorios — nueva vigencia', () {
    test('incremento anual de precio programado desde agosto para iniciar el 1 de enero', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1650000, // incremento
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );
      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      final linea = lineas.single;
      // Hoy (15 de agosto de 2026) la condición original sigue vigente.
      expect(linea.vigenciaActual?.precioUnitario, 1500000);
      expect(linea.vigenciasProgramadas, hasLength(1));
      expect(linea.vigenciasProgramadas.single.precioUnitario, 1650000);
      expect(linea.vigenciasProgramadas.single.fechaInicioVigencia, DateTime(2027, 1, 1));

      // La original quedó truncada exactamente el día previo.
      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      final original = historial.firstWhere((v) => v.precioUnitario == 1500000);
      expect(original.fechaFinVigencia, DateTime(2026, 12, 31));
    });

    test('cambio de cantidad reemplaza la vigente de inmediato', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 4,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: hoy,
        ),
      );
      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.vigenciaActual?.cantidadElementos, 4);
      expect(lineas.single.vigenciasProgramadas, isEmpty);
    });

    test('cambio de puesto reemplaza la vigente de inmediato', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final jefeDeTurno = await crearPuestoDePrueba(codigo: 'PUE-0002', nombre: 'Jefe de turno');

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: jefeDeTurno.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: hoy,
        ),
      );
      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.vigenciaActual?.puestoId, jefeDeTurno.id);
      expect(lineas.single.puestoNombre, 'Jefe de turno');
    });

    test('cambio de modalidad de turno reemplaza la vigente de inmediato', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno12x12,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: hoy,
        ),
      );
      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.vigenciaActual?.modalidadTurnoId, SeedIds.modalidadTurno12x12);
    });

    test('cambio de tratamiento de IVA reemplaza la vigente de inmediato', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: hoy,
        ),
      );
      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.vigenciaActual?.tratamientoIva, 'noAplica');
    });

    test('varias vigencias futuras no solapadas', () async {
      final ctx = await crearServicioConLineaDePrueba();

      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1600000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 10, 1),
        ),
      );
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1700000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      final linea = lineas.single;
      expect(linea.vigenciaActual?.precioUnitario, 1500000, reason: 'la original sigue vigente hoy');
      expect(linea.vigenciasProgramadas, hasLength(2));
      expect(linea.vigenciasProgramadas[0].fechaInicioVigencia, DateTime(2026, 10, 1));
      expect(linea.vigenciasProgramadas[0].fechaFinVigencia, DateTime(2026, 12, 31), reason: 'no debe solapar a la siguiente');
      expect(linea.vigenciasProgramadas[1].fechaInicioVigencia, DateTime(2027, 1, 1));
      expect(linea.vigenciasProgramadas[1].fechaFinVigencia, isNull);
    });

    test('intento de solapamiento con una programada ya registrada es rechazado', () async {
      final ctx = await crearServicioConLineaDePrueba();

      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1700000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1600000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 10, 1),
          fechaFinVigencia: DateTime(2027, 2, 1), // se solapa con la de 2027-01-01
        ),
      );

      expect(resultado, isA<CambiarVigenciaLineaComercialErroresValidacion>());
      final errores = (resultado as CambiarVigenciaLineaComercialErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorLineaComercial.solapamiento), isTrue);
    });

    test('rechaza dos vigencias con la misma fecha de inicio', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 3,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1), // misma fecha que la ya existente
        ),
      );

      expect(resultado, isA<CambiarVigenciaLineaComercialErroresValidacion>());
      final errores = (resultado as CambiarVigenciaLineaComercialErroresValidacion).errores;
      expect(errores.any((e) => e.codigo == CodigoErrorLineaComercial.fechaDuplicada), isTrue);
    });

    test('permite una vigencia retroactiva (Resolución H — sin bloqueo desde el dominio)', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 5,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 6, 1), // en el pasado respecto al reloj fijo (15 ago 2026)
        ),
      );

      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());
    });

    test('Servicio terminado no permite registrar una nueva vigencia', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarEstatusServicio.ejecutar(
        servicioId: ctx.servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 1),
        motivo: 'Motivo de prueba',
      );

      final resultado = await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: hoy,
        ),
      );

      expect(resultado, isA<CambiarVigenciaLineaComercialServicioNoDisponible>());
    });
  });

  group('Cierre sin reemplazo', () {
    test('cierra la vigente actual y la línea queda sin condición vigente', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await cerrarLinea.ejecutar(lineaComercialId: ctx.lineaId, fechaEfectiva: hoy, motivo: 'Motivo de prueba');
      expect(resultado, isA<CerrarLineaComercialExitoso>());

      // `fechaFinVigencia` es inclusiva (mismo criterio que el truncado de
      // predecesoras al registrar una nueva vigencia): el día efectivo de
      // cierre todavía cuenta como vigente; solo al día siguiente la
      // línea pasa a "sin condición vigente".
      final lineasHoy = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineasHoy.single.vigenciaActual?.fechaFinVigencia, hoy);

      final repoManana = ServicioComercialRepositoryImpl(db, clock: _RelojFijo(hoy.add(const Duration(days: 1))));
      final lineasManana = await repoManana.listarLineas(ctx.servicio.id);
      expect(lineasManana.single.vigenciaActual, isNull);
      expect(lineasManana.single.vigenciasProgramadas, isEmpty);
    });

    test('rechaza cerrar si ya existe una vigencia programada', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1600000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final resultado = await cerrarLinea.ejecutar(lineaComercialId: ctx.lineaId, fechaEfectiva: hoy, motivo: 'Motivo de prueba');
      expect(resultado, isA<CerrarLineaComercialTieneVigenciaProgramada>());
    });

    test('rechaza cerrar si no hay condición vigente', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cerrarLinea.ejecutar(lineaComercialId: ctx.lineaId, fechaEfectiva: hoy, motivo: 'Motivo de prueba');

      // Un segundo intento el MISMO día es, en la práctica, un
      // re-cierre válido (la vigencia sigue siendo "la vigente" hasta el
      // final de su propio día de cierre) — el caso realmente sin
      // condición vigente se da al día siguiente.
      final clockManana = _RelojFijo(hoy.add(const Duration(days: 1)));
      final cerrarLineaManana = CerrarLineaComercialUseCase(
        ServicioComercialRepositoryImpl(db, clock: clockManana),
        clockManana,
      );
      final resultado = await cerrarLineaManana.ejecutar(lineaComercialId: ctx.lineaId, fechaEfectiva: hoy, motivo: 'Motivo de prueba');
      expect(resultado, isA<CerrarLineaComercialSinCondicionVigente>());
    });

    test('Servicio terminado SÍ permite cerrar (acción de orden, no alta nueva)', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarEstatusServicio.ejecutar(
        servicioId: ctx.servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 1),
        motivo: 'Motivo de prueba',
      );

      final resultado = await cerrarLinea.ejecutar(lineaComercialId: ctx.lineaId, fechaEfectiva: hoy, motivo: 'Motivo de prueba');
      expect(resultado, isA<CerrarLineaComercialExitoso>());
    });
  });

  group('Cancelar vigencia programada (Resolución F)', () {
    test('cancela y repara la predecesora cuando no hay sucesora', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1600000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );
      final programada = (await comercialRepo.listarLineas(ctx.servicio.id)).single.vigenciasProgramadas.single;

      final resultado = await cancelarProgramada.ejecutar(vigenciaId: programada.id, motivo: 'Motivo de prueba');
      expect(resultado, isA<CancelarVigenciaProgramadaExitoso>());

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.vigenciasProgramadas, isEmpty);
      expect(lineas.single.vigenciaActual?.fechaFinVigencia, isNull, reason: 'la predecesora vuelve a quedar abierta');

      final historial = await obtenerHistorial.ejecutar(ctx.lineaId);
      final cancelada = historial.firstWhere((v) => v.vigencia.id == programada.id);
      expect(cancelada.estado, EstadoVigencia.cancelada, reason: 'sigue visible en el historial, nunca oculta');
    });

    test('cancela y repara la predecesora cuando SÍ hay sucesora (reingreso general)', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1600000, // programada #1: la que se cancelará
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 10, 1),
        ),
      );
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1700000, // programada #2: la sucesora
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final programadas = (await comercialRepo.listarLineas(ctx.servicio.id)).single.vigenciasProgramadas;
      final aCancelar = programadas.firstWhere((v) => v.precioUnitario == 1600000);

      await cancelarProgramada.ejecutar(vigenciaId: aCancelar.id, motivo: 'Motivo de prueba');

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      final linea = lineas.single;
      expect(linea.vigenciasProgramadas, hasLength(1));
      expect(linea.vigenciasProgramadas.single.precioUnitario, 1700000);
      expect(
        linea.vigenciaActual?.fechaFinVigencia,
        DateTime(2026, 12, 31),
        reason: 'la actual ahora cubre hasta justo antes de la sucesora restante',
      );
    });

    test('rechaza cancelar una vigencia que ya no está programada', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      final vigenteActual = lineas.single.vigenciaActual!;

      final resultado = await cancelarProgramada.ejecutar(vigenciaId: vigenteActual.id, motivo: 'Motivo de prueba');
      expect(resultado, isA<CancelarVigenciaProgramadaNoEsProgramada>());
    });
  });

  group('Editar anotaciones', () {
    test('edita descripción y observaciones sobre la vigente actual, sin abrir una nueva vigencia', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final vigenteActual = (await comercialRepo.listarLineas(ctx.servicio.id)).single.vigenciaActual!;

      final resultado = await actualizarAnotaciones.ejecutar(
        vigenciaId: vigenteActual.id,
        descripcion: 'Turno principal',
        observaciones: 'Confirmado con el cliente',
      );

      expect(resultado, isA<ActualizarAnotacionesVigenciaExitoso>());
      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      expect(historial, hasLength(1), reason: 'nunca crea una vigencia nueva');
      expect(historial.single.descripcion, 'Turno principal');
    });

    test('rechaza editar anotaciones de una vigencia histórica', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 3,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: hoy,
        ),
      );
      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      final historica = historial.firstWhere((v) => v.cantidadElementos == 2);

      final resultado = await actualizarAnotaciones.ejecutar(vigenciaId: historica.id, descripcion: 'no debería aplicar');
      expect(resultado, isA<ActualizarAnotacionesVigenciaNoEditable>());
    });
  });

  group('Historial cronológico', () {
    test('muestra las 4 clasificaciones correctamente ordenadas', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 4,
          precioUnitario: 1550000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: hoy,
        ),
      );
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 4,
          precioUnitario: 1700000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );
      final programada = (await comercialRepo.listarLineas(ctx.servicio.id)).single.vigenciasProgramadas.single;
      await cancelarProgramada.ejecutar(vigenciaId: programada.id, motivo: 'Motivo de prueba');

      final historial = await obtenerHistorial.ejecutar(ctx.lineaId);
      expect(historial, hasLength(3));
      expect(historial[0].estado, EstadoVigencia.historica);
      expect(historial[0].vigencia.precioUnitario, 1500000);
      expect(historial[1].estado, EstadoVigencia.vigente);
      expect(historial[1].vigencia.precioUnitario, 1550000);
      expect(historial[2].estado, EstadoVigencia.cancelada);
      expect(historial[2].vigencia.precioUnitario, 1700000);
      // Orden cronológico por fecha de inicio, no por cuándo se registró.
      for (var i = 1; i < historial.length; i++) {
        expect(
          historial[i].vigencia.fechaInicioVigencia.isAfter(historial[i - 1].vigencia.fechaInicioVigencia),
          isTrue,
        );
      }
    });
  });

  group('Corregir línea comercial (Etapa 15 — sin historia)', () {
    late CorregirLineaComercialUseCase corregirLinea;

    setUp(() {
      corregirLinea = CorregirLineaComercialUseCase(
        comercialRepo,
        LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, ConfiguracionCobroRepositoryImpl(db)),
      );
    });

    test('corrige in-place una línea recién creada, sin generar una nueva vigencia', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final vigenciaOriginalId = (await comercialRepo.listarHistorial(ctx.lineaId)).single.id;

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 3,
          precioUnitario: 1800000, // corrige un error de captura, no un incremento real
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirLineaComercialExitoso>());
      final vigenciaCorregida = (resultado as CorregirLineaComercialExitoso).vigencia;
      expect(vigenciaCorregida.id, vigenciaOriginalId, reason: 'muta el mismo registro, no crea uno nuevo');

      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      expect(historial, hasLength(1), reason: 'corregir nunca cierra+inserta, solo muta la única vigencia');
      expect(historial.single.cantidadElementos, 3);
      expect(historial.single.precioUnitario, 1800000);

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      final linea = lineas.single;
      expect(linea.vigenciaActual?.precioUnitario, 1800000);
      expect(linea.subtotal, 3 * 1800000, reason: 'el subtotal se recalcula sobre la condición corregida');
      expect(linea.esCorregible, isTrue, reason: 'sigue sin historia real tras corregirse a sí misma');
    });

    test('no reescribe una línea que ya pasó por "Nueva vigencia" — exige usar ese camino', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 4,
          precioUnitario: 1650000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 9,
          precioUnitario: 999,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirLineaComercialTieneHistoria>());
      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      expect(historial.firstWhere((v) => v.precioUnitario == 1500000), isNotNull, reason: 'la original no se tocó');

      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.esCorregible, isFalse);
    });

    test('no reescribe una vigencia que ya generó un DocumentoPorEmitirLinea', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final vigenciaId = (await comercialRepo.listarHistorial(ctx.lineaId)).single.id;
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-0001',
              clienteId: ctx.servicio.clienteId,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'GK-0001',
              importeBaseEsperado: 3000000,
              importeFinalEsperado: 3000000,
            ),
          );
      await db.into(db.documentoPorEmitirLinea).insert(
            DocumentoPorEmitirLineaCompanion.insert(
              documentoPorEmitirId: documento.id,
              servicioId: ctx.servicio.id,
              lineaComercialVigenciaId: vigenciaId,
              puestoNombre: ctx.puesto.nombre,
              modalidadTurnoNombre: 'Turno 24x24',
              cantidadElementos: 2,
              precioUnitario: 1500000,
              tratamientoIva: 'masIva',
              diasAplicables: 31,
              subtotalProporcional: 3000000,
            ),
          );

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 9,
          precioUnitario: 999,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirLineaComercialTieneHistoria>());
      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas.single.esCorregible, isFalse);
    });

    test('reporta errores de validación específicos en vez de mutar la vigencia', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: null,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<CorregirLineaComercialErroresValidacion>());
      final errores = (resultado as CorregirLineaComercialErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoLineaComercial.cantidadElementos), isTrue);

      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      expect(historial.single.cantidadElementos, 2, reason: 'no se mutó nada ante un borrador inválido');
    });

    test('línea inexistente', () async {
      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: 'no-existe',
        borrador: LineaComercialBorrador(
          puestoId: 'x',
          modalidadTurnoId: 'x',
          cantidadElementos: 1,
          precioUnitario: 1,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );
      expect(resultado, isA<CorregirLineaComercialNoExiste>());
    });
  });

  group('Eliminar línea comercial físicamente (Etapa 15 — sin historia)', () {
    late EliminarLineaComercialFisicamenteUseCase eliminarLinea;

    setUp(() {
      eliminarLinea = EliminarLineaComercialFisicamenteUseCase(comercialRepo);
    });

    test('elimina una línea recién creada, sin historia', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final resultado = await eliminarLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        motivo: 'Captura duplicada por error',
      );

      expect(resultado, isA<EliminarLineaComercialFisicamenteExitoso>());
      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas, isEmpty);
    });

    test('bloqueada si la línea ya tiene más de una vigencia', () async {
      final ctx = await crearServicioConLineaDePrueba();
      await cambiarVigencia.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 4,
          precioUnitario: 1650000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2027, 1, 1),
        ),
      );

      final resultado = await eliminarLinea.ejecutar(lineaComercialId: ctx.lineaId, motivo: 'Intento incorrecto');

      expect(resultado, isA<EliminarLineaComercialFisicamenteTieneDependencias>());
      final lineas = await comercialRepo.listarLineas(ctx.servicio.id);
      expect(lineas, hasLength(1), reason: 'no debe borrarse nada');
    });

    test('motivo obligatorio', () async {
      final ctx = await crearServicioConLineaDePrueba();
      final resultado = await eliminarLinea.ejecutar(lineaComercialId: ctx.lineaId, motivo: '   ');
      expect(resultado, isA<EliminarLineaComercialFisicamenteMotivoRequerido>());
    });

    test('línea inexistente', () async {
      final resultado = await eliminarLinea.ejecutar(lineaComercialId: 'no-existe', motivo: 'x');
      expect(resultado, isA<EliminarLineaComercialFisicamenteNoExiste>());
    });
  });

  group('Horario personalizado (Etapa 15, "Modalidad de turno: Personalizado")', () {
    /// 7 días — por defecto lunes a viernes trabajando 20:00→07:00
    /// (turno nocturno real) y sábado/domingo de descanso, salvo que
    /// [dias] los sobrescriba explícitamente.
    HorarioSemanalBorrador horarioDePrueba({Map<int, HorarioDiaBorrador> dias = const {}}) {
      return HorarioSemanalBorrador(
        dias: [
          for (var i = 0; i < 7; i++)
            dias[i] ??
                (i < 5
                    ? const HorarioDiaBorrador(abierto: true, horaInicioMinutos: 1200, horaFinMinutos: 420)
                    : const HorarioDiaBorrador(abierto: false)),
        ],
      );
    }

    test('días de descanso no requieren horas — sábado y domingo quedan sin capturar', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final puesto = await crearPuestoDePrueba(codigo: 'PUE-JEFE', nombre: 'Jefe de Turno');

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurnoPersonalizado,
          cantidadElementos: 1,
          precioUnitario: 2200000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          horario: horarioDePrueba(),
        ),
      );
      expect(resultado, isA<CrearLineaComercialExitoso>(), reason: 'los días de descanso (sin horas) no deben bloquear la captura');

      final vigenciaId = (resultado as CrearLineaComercialExitoso).vigencia.id;
      final horario = await comercialRepo.obtenerHorario(vigenciaId);
      expect(horario, hasLength(7), reason: 'los 7 días se guardan, incluidos los de descanso');

      final sabado = horario.firstWhere((h) => h.diaSemana == 5);
      final domingo = horario.firstWhere((h) => h.diaSemana == 6);
      expect(sabado.activo, isFalse);
      expect(domingo.activo, isFalse);

      final lunes = horario.firstWhere((h) => h.diaSemana == 0);
      expect(lunes.activo, isTrue);
      expect(lunes.horaInicio, 1200);
      expect(lunes.horaFin, 420);
    });

    test('turno nocturno 20:00→07:00 es válido y se marca cruzaMedianoche', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final puesto = await crearPuestoDePrueba(codigo: 'PUE-NOCTURNO', nombre: 'Elemento Nocturno');

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurnoPersonalizado,
          cantidadElementos: 1,
          precioUnitario: 1800000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          horario: horarioDePrueba(),
        ),
      );
      expect(resultado, isA<CrearLineaComercialExitoso>());

      final vigenciaId = (resultado as CrearLineaComercialExitoso).vigencia.id;
      final horario = await comercialRepo.obtenerHorario(vigenciaId);
      final lunes = horario.firstWhere((h) => h.diaSemana == 0);
      expect(lunes.horaInicio, 1200, reason: '20:00 = 1200 minutos desde medianoche');
      expect(lunes.horaFin, 420, reason: '07:00 = 420 minutos desde medianoche');
      expect(lunes.cruzaMedianoche, isTrue, reason: 'salida (420) < entrada (1200) — se infiere automáticamente, nunca es una decisión de la UI');
    });

    test('rechaza un día "trabaja" sin hora de entrada ni de salida', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final puesto = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurnoPersonalizado,
          cantidadElementos: 1,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          horario: horarioDePrueba(dias: {0: const HorarioDiaBorrador(abierto: true)}),
        ),
      );

      expect(resultado, isA<CrearLineaComercialErroresValidacion>());
      final errores = (resultado as CrearLineaComercialErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoLineaComercial.horario && e.diaSemana == 0), isTrue);
    });

    test('corregirVigencia reemplaza por completo el horario anterior de la misma vigencia', () async {
      final ctx = await crearServicioConLineaDePrueba();

      final validador = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, ConfiguracionCobroRepositoryImpl(db));
      final corregir = CorregirLineaComercialUseCase(comercialRepo, validador);

      final resultado = await corregir.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurnoPersonalizado,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          horario: horarioDePrueba(),
        ),
        motivo: 'Motivo de prueba',
      );
      expect(resultado, isA<CorregirLineaComercialExitoso>());

      final vigenciaId = (resultado as CorregirLineaComercialExitoso).vigencia.id;
      final horario = await comercialRepo.obtenerHorario(vigenciaId);
      expect(horario, hasLength(7));
      expect(horario.firstWhere((h) => h.diaSemana == 0).activo, isTrue);

      // Corregir de nuevo, ahora con TODOS los días de descanso — el
      // horario anterior debe reemplazarse por completo, no acumularse.
      final segundo = await corregir.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: LineaComercialBorrador(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
        motivo: 'Motivo de prueba',
      );
      expect(segundo, isA<CorregirLineaComercialExitoso>());
      final horarioTrasSegundo = await comercialRepo.obtenerHorario(vigenciaId);
      expect(
        horarioTrasSegundo,
        isEmpty,
        reason: 'al corregir a una modalidad que no es Personalizado, el horario de esa vigencia se limpia por completo',
      );
    });
  });
}
