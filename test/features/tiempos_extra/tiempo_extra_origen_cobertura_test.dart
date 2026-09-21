// Tiempo Extra — origen de la cobertura: Ausencia / Vacante / Otro.
//
// Hueco que cierra: hasta schemaVersion 84 el dominio asumía que TODO
// Tiempo Extra existía porque faltó un titular (`empleadoAusenteId` era
// `NOT NULL`). En operación real también se cubre una plaza VACANTE —no
// falta nadie, no hay nadie— o una necesidad puntual distinta.
//
// Lo que estas pruebas protegen:
//   1. el origen es un DISCRIMINADOR explícito, nunca se infiere por
//      nulos;
//   2. cada origen tiene una forma exacta: exige lo suyo y prohíbe lo
//      ajeno, así que cambiar de origen no puede dejar residuos;
//   3. la Vacante se referencia por FK REAL, del mismo Servicio y
//      abierta — nunca un nombre ficticio ni un empleado placeholder;
//   4. registrar o cancelar un Tiempo Extra por vacante NO toca el
//      estado de la vacante: fue una cobertura temporal de un turno,
//      no una contratación;
//   5. el tratamiento financiero es idéntico en los tres orígenes.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/vacante_operativa_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/vacante_operativa_table.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/cancelar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/corregir_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/tiempo_extra_validator.dart';

void main() {
  late AppDatabase db;
  late TiempoExtraRepositoryImpl tiempoExtraRepo;
  late VacanteOperativaRepositoryImpl vacanteRepo;
  late VacanteCoberturaReader vacantes;
  late RegistrarTiempoExtraUseCase registrar;
  late CorregirTiempoExtraUseCase corregir;
  late CancelarTiempoExtraUseCase cancelar;
  late EgresoRepositoryImpl egresoRepo;
  late DeudaRepositoryImpl deudaRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late RegistrarDeudaUseCase registrarDeuda;

  late String servicioId;
  late String otroServicioId;
  late String empleadoAusenteId;
  late String empleadoCubreId;
  late String turnoId;
  late String vacanteId;
  late String vacanteDeOtroServicioId;

  var consecutivo = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    vacanteRepo = VacanteOperativaRepositoryImpl(db);
    vacantes = VacanteCoberturaReader(db);
    egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(codigoSecuencia));

    tiempoExtraRepo =
        TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    registrar = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, vacantes);
    corregir = CorregirTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, vacantes);
    cancelar = CancelarTiempoExtraUseCase(tiempoExtraRepo);

    final cliente =
        await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final crearServicio = CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(codigoSecuencia),
      ServicioValidator(clienteRepo, catalogoRepo),
    );

    Future<String> nuevoServicio(String nombre) async {
      final creado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(
          nombre: nombre,
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      return (creado as GuardarServicioExitoso).servicio.id;
    }

    servicioId = await nuevoServicio('Vigilancia Satélite');
    otroServicioId = await nuevoServicio('Vigilancia Toluca');

    Future<String> crearEmpleado(String nombre) async {
      final n = (++consecutivo).toString().padLeft(2, '0');
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: consecutivo,
              nombres: nombre,
              apellidoPaterno: 'Apellido$n',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX$n',
              rfc: 'PEXJ900101$n',
              nss: '100000000$n',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      return empleado.id;
    }

    empleadoAusenteId = await crearEmpleado('Monica');
    empleadoCubreId = await crearEmpleado('Juan');
    turnoId = SeedIds.modalidadTurno24x24;

    // Una vacante REAL, por el camino real: línea comercial que pide 2
    // elementos y sólo 1 cubierto → 1 plaza abierta.
    Future<String> vacanteAbiertaDe(String servicio, String codigoPuesto) async {
      final puesto = await puestoRepo.crear(
        PuestoCompanion.insert(
          codigo: codigoPuesto,
          nombre: 'Guardia',
          areaId: SeedIds.areaOperaciones,
          tipo: 'operativo',
          nivelJerarquico: 5,
        ),
      );
      final linea = await comercialRepo.crearLinea(
        servicioId: servicio,
        datos: LineaComercialValidada(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 100000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          sueldoMensualReferenciaPersonal: 1500000,
          bonoMensualReferenciaPersonal: 0,
        ),
      );
      await vacanteRepo.sincronizarLinea(
        servicioId: servicio,
        lineaComercialId: linea.linea.id,
        requerido: 2,
        cubierto: 1,
        fecha: DateTime(2026, 9, 1),
        motivoApertura: 'bajaEmpleado',
      );
      final abiertas = await vacanteRepo.listarAbiertasPorServicio(servicio);
      return abiertas.single.id;
    }

    vacanteId = await vacanteAbiertaDe(servicioId, 'PUE-0001');
    vacanteDeOtroServicioId = await vacanteAbiertaDe(otroServicioId, 'PUE-0002');
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------
  // Andamiaje
  // ---------------------------------------------------------------

  Future<RegistrarTiempoExtraResultado> registrarCon({
    required OrigenCoberturaTiempoExtra origen,
    String? empleadoAusente,
    String? motivoAusencia,
    String? vacante,
    String? descripcionOrigen,
    String? servicio,
    String? empleadoCubre,
    String? formaPago,
    String? deudaIdTarjeta,
    String? cuentaFinancieraId,
    int monto = 150000,
  }) {
    return registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicio ?? servicioId,
      origenCobertura: origen.name,
      empleadoAusenteId: empleadoAusente,
      motivoAusencia: motivoAusencia,
      vacanteOperativaId: vacante,
      descripcionOrigen: descripcionOrigen,
      empleadoCubreId: empleadoCubre ?? empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: monto,
      formaPago: formaPago ?? FormaPago.efectivo.name,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
    );
  }

  Future<TiempoExtraData> registrarPorAusencia() async {
    final r = await registrarCon(
      origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado,
      empleadoAusente: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
    );
    return (r as RegistrarTiempoExtraExitoso).tiempoExtra;
  }

  Future<TiempoExtraData> registrarPorVacante() async {
    final r = await registrarCon(origen: OrigenCoberturaTiempoExtra.vacante, vacante: vacanteId);
    expect(r, isA<RegistrarTiempoExtraExitoso>(), reason: '$r');
    return (r as RegistrarTiempoExtraExitoso).tiempoExtra;
  }

  Future<TiempoExtraData> registrarPorOtro() async {
    final r = await registrarCon(
      origen: OrigenCoberturaTiempoExtra.otro,
      descripcionOrigen: 'Reforzamiento por evento masivo',
    );
    expect(r, isA<RegistrarTiempoExtraExitoso>(), reason: '$r');
    return (r as RegistrarTiempoExtraExitoso).tiempoExtra;
  }

  Future<TiempoExtraData> recargar(String id) =>
      (db.select(db.tiempoExtra)..where((t) => t.id.equals(id))).getSingle();

  Future<VacanteOperativaData> recargarVacante(String id) =>
      (db.select(db.vacanteOperativa)..where((t) => t.id.equals(id))).getSingle();

  // ===============================================================
  // §26 — AUSENCIA DE EMPLEADO
  // ===============================================================
  group('Ausencia de empleado', () {
    test('A. Servicio + empleado faltante + motivo + empleado que cubre → registra', () async {
      final tex = await registrarPorAusencia();

      expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.ausenciaEmpleado.name);
      expect(tex.empleadoAusenteId, empleadoAusenteId);
      expect(tex.motivoAusencia, MotivoAusenciaTiempoExtra.faltaInjustificada.name);
      expect(tex.empleadoCubreId, empleadoCubreId);
      expect(tex.vacanteOperativaId, isNull, reason: 'una ausencia no referencia ninguna vacante');
      expect(tex.descripcionOrigen, isNull);
    });

    test('B. el mismo empleado no puede faltar y cubrir a la vez → rechazo', () async {
      final resultado = await registrarCon(
        origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado,
        empleadoAusente: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubre: empleadoAusenteId,
      );

      expect(resultado, isA<RegistrarTiempoExtraAusenteYCubreSonElMismo>());
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });

    test('C. ausencia SIN empleado faltante → rechazo', () async {
      final resultado = await registrarCon(
        origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      );

      expect(resultado, isA<RegistrarTiempoExtraOrigenInvalido>());
      expect(
        (resultado as RegistrarTiempoExtraOrigenInvalido).validacion,
        TiempoExtraOrigenValidacion.faltaEmpleadoAusente,
      );
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });

    test('D. ausencia SIN motivo → rechazo', () async {
      final resultado = await registrarCon(
        origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado,
        empleadoAusente: empleadoAusenteId,
      );

      expect(resultado, isA<RegistrarTiempoExtraOrigenInvalido>());
      expect(
        (resultado as RegistrarTiempoExtraOrigenInvalido).validacion,
        TiempoExtraOrigenValidacion.faltaMotivoAusencia,
      );
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });
  });

  // ===============================================================
  // §26 — VACANTE
  // ===============================================================
  group('Vacante', () {
    test('E. Servicio + vacante válida + empleado que cubre → registra con FK real', () async {
      final tex = await registrarPorVacante();

      expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.vacante.name);
      expect(tex.vacanteOperativaId, vacanteId, reason: 'FK real, nunca un nombre ni una bandera');
      expect(tex.empleadoCubreId, empleadoCubreId);
      expect(tex.descripcionOrigen, isNull);

      // La FK resuelve de verdad contra la tabla.
      final vacante = await recargarVacante(tex.vacanteOperativaId!);
      expect(vacante.servicioId, servicioId);
    });

    test('F. vacante de OTRO Servicio → rechazo', () async {
      final resultado = await registrarCon(
        origen: OrigenCoberturaTiempoExtra.vacante,
        vacante: vacanteDeOtroServicioId,
      );

      expect(resultado, isA<RegistrarTiempoExtraVacanteDeOtroServicio>());
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });

    test('G. vacante ya cubierta (no elegible) → rechazo al registrar', () async {
      // La vacante se cierra por su propio flujo: la plaza se llenó.
      final vacante = await recargarVacante(vacanteId);
      await vacanteRepo.sincronizarLinea(
        servicioId: servicioId,
        lineaComercialId: vacante.lineaComercialId,
        requerido: 2,
        cubierto: 2,
        fecha: DateTime(2026, 9, 10),
        motivoApertura: 'bajaEmpleado',
      );
      expect((await recargarVacante(vacanteId)).estatus, EstatusVacanteOperativa.cubierta.name);

      final resultado = await registrarCon(origen: OrigenCoberturaTiempoExtra.vacante, vacante: vacanteId);
      expect(resultado, isA<RegistrarTiempoExtraVacanteNoElegible>());
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });

    test('E2. vacante SIN vacanteOperativaId → rechazo', () async {
      final resultado = await registrarCon(origen: OrigenCoberturaTiempoExtra.vacante);

      expect(resultado, isA<RegistrarTiempoExtraOrigenInvalido>());
      expect(
        (resultado as RegistrarTiempoExtraOrigenInvalido).validacion,
        TiempoExtraOrigenValidacion.faltaVacante,
        reason: 'sin FK real no hay plaza que cubrir: no se infiere por nulos',
      );
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });

    test('E3. corregir hacia vacante SIN vacante → rechazo, y el TEX no cambia', () async {
      final tex = await registrarPorAusencia();

      final resultado = await corregir.ejecutar(
        tiempoExtraId: tex.id,
        fecha: tex.fecha,
        servicioId: tex.servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.vacante.name,
        empleadoCubreId: tex.empleadoCubreId,
        turnoId: tex.turnoId,
        montoTiempoExtra: tex.montoTiempoExtra,
        formaPago: tex.formaPago,
        motivo: 'Reclasificación',
      );

      expect(resultado, isA<CorregirTiempoExtraOrigenInvalido>());
      expect(
        (resultado as CorregirTiempoExtraOrigenInvalido).validacion,
        TiempoExtraOrigenValidacion.faltaVacante,
      );
      final despues = await recargar(tex.id);
      expect(despues.origenCobertura, OrigenCoberturaTiempoExtra.ausenciaEmpleado.name);
      expect(despues.empleadoAusenteId, empleadoAusenteId, reason: 'el TEX queda exactamente como estaba');
    });

    test('G2. vacante inexistente → rechazo', () async {
      final resultado =
          await registrarCon(origen: OrigenCoberturaTiempoExtra.vacante, vacante: 'vacante-que-no-existe');
      expect(resultado, isA<RegistrarTiempoExtraVacanteNoExiste>());
    });

    test('H. vacante SIN empleado faltante → válido (no falta nadie: no hay nadie)', () async {
      final tex = await registrarPorVacante();
      expect(tex.empleadoAusenteId, isNull);
      expect(tex.motivoAusencia, isNull);
    });

    test('H2. vacante CON empleado faltante → rechazo: sería inventar un titular', () async {
      final resultado = await registrarCon(
        origen: OrigenCoberturaTiempoExtra.vacante,
        vacante: vacanteId,
        empleadoAusente: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      );

      expect(resultado, isA<RegistrarTiempoExtraOrigenInvalido>());
      expect(
        (resultado as RegistrarTiempoExtraOrigenInvalido).validacion,
        TiempoExtraOrigenValidacion.camposIncompatibles,
      );
    });

    test('I. registrar un TEX por vacante NO cierra la vacante', () async {
      final antes = await recargarVacante(vacanteId);
      await registrarPorVacante();
      final despues = await recargarVacante(vacanteId);

      expect(despues.estatus, EstatusVacanteOperativa.abierta.name, reason: 'fue una cobertura temporal de un turno');
      expect(despues.estatus, antes.estatus);
      expect(despues.fechaCobertura, isNull);
      expect(despues.asignacionCoberturaId, isNull);
      expect(despues.fechaApertura, antes.fechaApertura);

      // Y sigue apareciendo como vacante abierta del Servicio.
      final abiertas = await vacanteRepo.listarAbiertasPorServicio(servicioId);
      expect(abiertas.map((v) => v.id), contains(vacanteId));
    });

    test('I2. registrar por vacante no crea ninguna asignación de empleado', () async {
      await registrarPorVacante();
      expect(await db.select(db.asignacionServicio).get(), isEmpty);
    });

    test('J. cancelar un TEX por vacante NO cambia la vacante', () async {
      final tex = await registrarPorVacante();
      final antes = await recargarVacante(vacanteId);

      final resultado = await cancelar.ejecutar(tiempoExtraId: tex.id, motivo: 'Se capturó por error');
      expect(resultado, isA<CancelarTiempoExtraExitoso>());

      final despues = await recargarVacante(vacanteId);
      expect(despues.estatus, antes.estatus);
      expect(despues.fechaCobertura, antes.fechaCobertura);
      expect(despues.asignacionCoberturaId, antes.asignacionCoberturaId);

      // El TEX sigue resolviendo qué vacante cubrió: cancelarlo no
      // borra su historia.
      expect((await recargar(tex.id)).vacanteOperativaId, vacanteId);
    });

    test('§24. un TEX histórico resuelve su vacante aunque después se cubra', () async {
      final tex = await registrarPorVacante();
      final vacante = await recargarVacante(vacanteId);
      await vacanteRepo.sincronizarLinea(
        servicioId: servicioId,
        lineaComercialId: vacante.lineaComercialId,
        requerido: 2,
        cubierto: 2,
        fecha: DateTime(2026, 10, 1),
        motivoApertura: 'bajaEmpleado',
      );

      // Catálogo para RESOLVER históricos: la encuentra igual.
      final resuelta = await vacantes.porId((await recargar(tex.id)).vacanteOperativaId!);
      expect(resuelta, isNotNull);
      expect(resuelta!.estaAbierta, isFalse);
      expect(resuelta.etiqueta, 'Guardia — 24×24', reason: 'contexto legible, nunca un id');

      // Catálogo para ELEGIR en un alta nueva: ya no la ofrece.
      final elegibles = await vacantes.elegiblesPorServicio(servicioId);
      expect(elegibles.map((v) => v.id), isNot(contains(vacanteId)));
    });
  });

  // ===============================================================
  // §26 — OTRO
  // ===============================================================
  group('Otro', () {
    test('K. descripción válida → registra', () async {
      final tex = await registrarPorOtro();

      expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.otro.name);
      expect(tex.descripcionOrigen, 'Reforzamiento por evento masivo');
      expect(tex.empleadoCubreId, empleadoCubreId);
    });

    test('L. descripción vacía → rechazo', () async {
      final resultado =
          await registrarCon(origen: OrigenCoberturaTiempoExtra.otro, descripcionOrigen: '   ');

      expect(resultado, isA<RegistrarTiempoExtraOrigenInvalido>());
      expect(
        (resultado as RegistrarTiempoExtraOrigenInvalido).validacion,
        TiempoExtraOrigenValidacion.faltaDescripcionOrigen,
      );
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    });

    test('L2. descripción desmedida → rechazo (es una nota breve, no observaciones)', () async {
      final resultado = await registrarCon(
        origen: OrigenCoberturaTiempoExtra.otro,
        descripcionOrigen: 'x' * (TiempoExtraValidator.maximoDescripcionOrigen + 1),
      );
      expect(resultado, isA<RegistrarTiempoExtraDescripcionOrigenMuyLarga>());
    });

    test('M. no requiere empleado faltante ni vacante', () async {
      final tex = await registrarPorOtro();
      expect(tex.empleadoAusenteId, isNull);
      expect(tex.motivoAusencia, isNull);
      expect(tex.vacanteOperativaId, isNull);
    });
  });

  // ===============================================================
  // §27 — CORRECCIÓN: TRANSICIONES ENTRE ORÍGENES
  // ===============================================================
  group('Corrección de origen', () {
    Future<CorregirTiempoExtraResultado> corregirA(
      TiempoExtraData tex, {
      required OrigenCoberturaTiempoExtra origen,
      String? empleadoAusente,
      String? motivoAusencia,
      String? vacante,
      String? descripcionOrigen,
      int monto = 150000,
    }) {
      return corregir.ejecutar(
        tiempoExtraId: tex.id,
        fecha: tex.fecha,
        servicioId: tex.servicioId,
        origenCobertura: origen.name,
        empleadoAusenteId: empleadoAusente,
        motivoAusencia: motivoAusencia,
        vacanteOperativaId: vacante,
        descripcionOrigen: descripcionOrigen,
        empleadoCubreId: tex.empleadoCubreId,
        nombreExternoCubre: tex.nombreExternoCubre,
        turnoId: tex.turnoId,
        montoTiempoExtra: monto,
        formaPago: tex.formaPago,
        observaciones: tex.observaciones,
        motivo: 'Se clasificó mal al capturar',
      );
    }

    test('Ausencia → Vacante: limpia empleado y motivo, y guarda la FK', () async {
      final tex = await registrarPorAusencia();

      final resultado = await corregirA(
        tex,
        origen: OrigenCoberturaTiempoExtra.vacante,
        // La pantalla arrastra el empleado del origen anterior: el
        // dominio lo limpia en vez de fallar.
        empleadoAusente: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        vacante: vacanteId,
      );
      expect(resultado, isA<CorregirTiempoExtraExitoso>(), reason: '$resultado');

      final despues = await recargar(tex.id);
      expect(despues.origenCobertura, OrigenCoberturaTiempoExtra.vacante.name);
      expect(despues.vacanteOperativaId, vacanteId);
      expect(despues.empleadoAusenteId, isNull, reason: 'sin residuos del origen anterior');
      expect(despues.motivoAusencia, isNull);
      expect(despues.descripcionOrigen, isNull);
    });

    test('Vacante → Otro: limpia la FK de la vacante', () async {
      final tex = await registrarPorVacante();

      final resultado = await corregirA(
        tex,
        origen: OrigenCoberturaTiempoExtra.otro,
        vacante: vacanteId,
        descripcionOrigen: 'Apoyo extraordinario solicitado por el cliente',
      );
      expect(resultado, isA<CorregirTiempoExtraExitoso>(), reason: '$resultado');

      final despues = await recargar(tex.id);
      expect(despues.origenCobertura, OrigenCoberturaTiempoExtra.otro.name);
      expect(despues.descripcionOrigen, 'Apoyo extraordinario solicitado por el cliente');
      expect(despues.vacanteOperativaId, isNull, reason: 'la FK incompatible se limpia');
      expect(despues.empleadoAusenteId, isNull);

      // Y la vacante que dejó de referenciarse sigue intacta.
      expect((await recargarVacante(vacanteId)).estatus, EstatusVacanteOperativa.abierta.name);
    });

    test('Otro → Ausencia: exige empleado y motivo, y limpia la descripción', () async {
      final tex = await registrarPorOtro();

      // Sin los datos que el nuevo origen exige, no pasa.
      expect(
        await corregirA(tex, origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado),
        isA<CorregirTiempoExtraOrigenInvalido>(),
      );
      expect((await recargar(tex.id)).origenCobertura, OrigenCoberturaTiempoExtra.otro.name);

      final resultado = await corregirA(
        tex,
        origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado,
        empleadoAusente: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.problemasMedicos.name,
        descripcionOrigen: 'Reforzamiento por evento masivo',
      );
      expect(resultado, isA<CorregirTiempoExtraExitoso>(), reason: '$resultado');

      final despues = await recargar(tex.id);
      expect(despues.origenCobertura, OrigenCoberturaTiempoExtra.ausenciaEmpleado.name);
      expect(despues.empleadoAusenteId, empleadoAusenteId);
      expect(despues.motivoAusencia, MotivoAusenciaTiempoExtra.problemasMedicos.name);
      expect(despues.descripcionOrigen, isNull, reason: 'sin residuos del origen anterior');
    });

    test('el diff registra el cambio de origen en texto legible, nunca un UUID', () async {
      final tex = await registrarPorAusencia();
      await corregirA(
        tex,
        origen: OrigenCoberturaTiempoExtra.vacante,
        vacante: vacanteId,
      );

      final evento = (await (db.select(db.tiempoExtraEvento)
                ..where((t) => t.tiempoExtraId.equals(tex.id) & t.tipoEvento.equals('corregido')))
              .get())
          .single;
      expect(evento.observacion, 'Se clasificó mal al capturar');

      final antes = evento.estadoAnterior!;
      final despues = evento.estadoNuevo!;
      expect(antes, contains('ausenciaEmpleado'));
      expect(despues, contains('vacante'));
      // Nombres, no ids.
      expect(antes, contains('Monica'));
      expect(despues, contains('Guardia — 24×24'));
      expect(despues, isNot(contains(vacanteId)));
      expect(antes, isNot(contains(empleadoAusenteId)));
    });

    test('corregir sólo el monto conserva el origen y su vacante', () async {
      final tex = await registrarPorVacante();

      final resultado =
          await corregirA(tex, origen: OrigenCoberturaTiempoExtra.vacante, vacante: vacanteId, monto: 180000);
      expect(resultado, isA<CorregirTiempoExtraExitoso>(), reason: '$resultado');

      final despues = await recargar(tex.id);
      expect(despues.montoTiempoExtra, 180000);
      expect(despues.vacanteOperativaId, vacanteId);
    });

    test('corregir un TEX cuya vacante ya se cubrió sigue siendo posible', () async {
      final tex = await registrarPorVacante();
      final vacante = await recargarVacante(vacanteId);
      await vacanteRepo.sincronizarLinea(
        servicioId: servicioId,
        lineaComercialId: vacante.lineaComercialId,
        requerido: 2,
        cubierto: 2,
        fecha: DateTime(2026, 10, 1),
        motivoApertura: 'bajaEmpleado',
      );

      // Conservar la MISMA vacante no re-exige que siga abierta:
      // corregir el monto de una cobertura de septiembre no puede
      // bloquearse porque la plaza se llenó en octubre.
      final resultado =
          await corregirA(tex, origen: OrigenCoberturaTiempoExtra.vacante, vacante: vacanteId, monto: 200000);
      expect(resultado, isA<CorregirTiempoExtraExitoso>(), reason: '$resultado');
      expect((await recargar(tex.id)).montoTiempoExtra, 200000);
    });
  });

  // ===============================================================
  // §28 — FINANZAS: MISMO TRATAMIENTO EN LOS TRES ORÍGENES
  // ===============================================================
  group('Efectos financieros por origen', () {
    Future<String> crearCuenta() async {
      final cuenta = await cuentaFinancieraRepo.crear(
        codigo: 'CTA-0001',
        nombre: 'Banco Principal',
        tipo: TipoCuentaFinanciera.banco.name,
        saldoInicial: 10000000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );
      return cuenta.id;
    }

    Future<String> crearTarjeta() async {
      final resultado = await registrarDeuda.ejecutar(
        nombre: 'TDC Empresarial',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 0,
        tarjetaLimiteCredito: 5000000,
      );
      return (resultado as RegistrarDeudaExitoso).deuda.id;
    }

    for (final caso in [
      (nombre: 'ausencia', origen: OrigenCoberturaTiempoExtra.ausenciaEmpleado),
      (nombre: 'vacante', origen: OrigenCoberturaTiempoExtra.vacante),
      (nombre: 'otro', origen: OrigenCoberturaTiempoExtra.otro),
    ]) {
      Future<TiempoExtraData> registrarDelCaso({
        required String formaPago,
        String? cuentaFinancieraId,
        String? deudaIdTarjeta,
      }) async {
        final r = await registrarCon(
          origen: caso.origen,
          empleadoAusente:
              caso.origen == OrigenCoberturaTiempoExtra.ausenciaEmpleado ? empleadoAusenteId : null,
          motivoAusencia: caso.origen == OrigenCoberturaTiempoExtra.ausenciaEmpleado
              ? MotivoAusenciaTiempoExtra.faltaInjustificada.name
              : null,
          vacante: caso.origen == OrigenCoberturaTiempoExtra.vacante ? vacanteId : null,
          descripcionOrigen: caso.origen == OrigenCoberturaTiempoExtra.otro ? 'Apoyo extraordinario' : null,
          formaPago: formaPago,
          cuentaFinancieraId: cuentaFinancieraId,
          deudaIdTarjeta: deudaIdTarjeta,
        );
        expect(r, isA<RegistrarTiempoExtraExitoso>(), reason: '$r');
        return (r as RegistrarTiempoExtraExitoso).tiempoExtra;
      }

      test('${caso.nombre} + Cuenta financiera → exactamente UN Egreso, y cancelar lo revierte una vez',
          () async {
        final cuentaId = await crearCuenta();
        final tex = await registrarDelCaso(
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaId,
        );

        expect(tex.egresoId, isNotNull, reason: 'Cuenta → Egreso');
        expect(tex.deudaId, isNull, reason: 'nunca ambos orígenes');
        final egresos = await db.select(db.egreso).get();
        expect(egresos, hasLength(1), reason: 'un solo Egreso: el origen no duplica el efecto');
        expect(egresos.single.monto, 150000);
        expect(egresos.single.estatus, 'registrado');

        // Ningún MovimientoDeuda: no hubo tarjeta.
        expect(await db.select(db.movimientoDeuda).get(), isEmpty);

        await cancelar.ejecutar(tiempoExtraId: tex.id, motivo: 'Se capturó por error');
        final egresosDespues = await db.select(db.egreso).get();
        expect(egresosDespues, hasLength(1), reason: 'cancelar no crea un Egreso nuevo');
        expect(egresosDespues.single.estatus, 'cancelado');
      });

      test('${caso.nombre} + TDC → exactamente UN MovimientoDeuda, sin Egreso, y cancelar lo revierte una vez',
          () async {
        final deudaId = await crearTarjeta();
        final tex = await registrarDelCaso(
          formaPago: FormaPago.tarjeta.name,
          deudaIdTarjeta: deudaId,
        );

        expect(tex.deudaId, deudaId, reason: 'TDC → MovimientoDeuda');
        expect(tex.egresoId, isNull, reason: 'una compra a crédito nunca genera Egreso');
        expect(await db.select(db.egreso).get(), isEmpty);

        final cargos = await (db.select(db.movimientoDeuda)
              ..where((t) => t.tiempoExtraId.equals(tex.id)))
            .get();
        expect(cargos, hasLength(1), reason: 'un solo cargo: el origen no duplica el efecto');
        expect(cargos.single.importe, 150000);

        final saldoAntes = (await deudaRepo.obtenerPorId(deudaId))!.saldoActual;
        expect(saldoAntes, 150000);

        await cancelar.ejecutar(tiempoExtraId: tex.id, motivo: 'Se capturó por error');
        final saldoDespues = (await deudaRepo.obtenerPorId(deudaId))!.saldoActual;
        expect(saldoDespues, 0, reason: 'la reversión es exactamente una');
      });
    }
  });
}
