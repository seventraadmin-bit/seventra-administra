// BUG REAL reportado por Marlon — "Dashboard ignora asignaciones
// históricas con lineaComercialId = NULL". Caso real confirmado:
// Empleado JUAN MANUEL ZINTZUN LOPEZ, Activo, asignación vigente al
// Servicio MILOYILE desde 20/11/2025 (dato previo a Etapa 15, cuando
// `AsignacionServicio.lineaComercialId` todavía no se exigía), Personal
// lo mostraba correctamente asignado, pero el Dashboard reportaba
// "MILOYILE — 0% · 0/1 cubiertos" porque `listarLineasEnFecha` contaba
// cobertura con `WHERE lineaComercialId.equals(linea.id)` — una
// comparación que en SQL NUNCA hace match contra NULL.
//
// Corrección aplicada en `ServicioComercialRepositoryImpl.listarLineasEnFecha`
// (ver `atribuirAsignacionesHistoricas`): una asignación histórica sin
// línea se atribuye de forma SOLO DE LECTURA (nunca se escribe nada en
// la fila) cuando es inequívoca — una única línea vigente del Servicio,
// o el `turnoId` coincide con exactamente una de varias — y se deja sin
// atribuir (ambigua) en cualquier otro caso, exponiendo
// "Regularizar perfil de asignación" (Maestro-only) para resolverla
// manualmente sin tocar fecha/sueldo/bono/historial.
//
// Esta prueba ejercita la cadena real completa (Cliente → Servicio →
// Línea comercial → Empleado → AsignacionServicio →
// ObtenerCoberturaOperativaUseCase / VacanteOperativaRepository), mismo
// patrón que `dashboard_cobertura_vacantes_test.dart` — nunca un mock
// de la lógica bajo prueba.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/vacante_operativa_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/asignacion_servicio_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/regularizar_perfil_asignacion_usecase.dart';

import 'package:riseg_one/features/dashboard/domain/usecases/obtener_cobertura_operativa_usecase.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late ServicioRepositoryImpl servicioRepo;
  late AsignacionServicioRepositoryImpl asignacionRepo;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late PuestoRepositoryImpl puestoRepo;
  late VacanteOperativaRepositoryImpl vacanteRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late CrearServicioUseCase crearServicio;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late ObtenerCoberturaOperativaUseCase obtenerCobertura;
  late RegularizarPerfilAsignacionServicioUseCase regularizarPerfil;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    clienteRepo = ClienteRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    vacanteRepo = VacanteOperativaRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);
    final generarNumero = GenerarNumeroUseCase(codigoSecuencia);
    const empleadoValidator = EmpleadoValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo, comercialRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    obtenerCobertura = ObtenerCoberturaOperativaUseCase(servicioRepo, comercialRepo, vacanteRepo);
    regularizarPerfil = RegularizarPerfilAsignacionServicioUseCase(asignacionRepo, comercialRepo);
  });

  tearDown(() => db.close());

  var clienteContador = 0;
  Future<ClienteData> crearClienteDePrueba() {
    clienteContador++;
    return clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${clienteContador.toString().padLeft(6, '0')}', nombreComercial: 'Cliente de prueba'),
    );
  }

  var empleadoContador = 0;
  Future<EmpleadoData> crearEmpleadoDePrueba() async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(3, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Empleado',
      apellidoPaterno: 'Prueba$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ9001019D${n}HDF',
      rfc: 'PEX9001${n}9AB',
      nss: '1234567$n' '0',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  var puestoContador = 0;
  Future<String> crearPuesto(String nombre) async {
    puestoContador++;
    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-${puestoContador.toString().padLeft(6, '0')}',
        nombre: nombre,
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    return puesto.id;
  }

  /// Crea un Servicio activo, listo para agregarle líneas comerciales.
  Future<ServicioData> crearServicioActivo() async {
    final cliente = await crearClienteDePrueba();
    final r1 = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'MILOYILE', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2025, 11, 1)),
    );
    var servicio = (r1 as GuardarServicioExitoso).servicio;

    await db.into(db.direccion).insert(
          DireccionCompanion.insert(
            servicioId: Value(servicio.id),
            tipoDireccion: TipoDireccion.operativa.name,
            calle: 'Av. Prueba',
            numeroExterior: '1',
            colonia: 'Centro',
            municipioAlcaldia: 'Toluca',
            estado: 'Estado de México',
            codigoPostal: '50000',
          ),
        );
    servicio = ((await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo, motivo: 'Motivo de prueba')) as CambiarEstatusServicioExitoso).servicio;
    return servicio;
  }

  Future<String> agregarLinea(
    String servicioId, {
    required String puestoNombre,
    required String modalidadTurnoId,
    required int cantidad,
  }) async {
    final puestoId = await crearPuesto(puestoNombre);
    final linea = await comercialRepo.crearLinea(
      servicioId: servicioId,
      datos: LineaComercialValidada(
        puestoId: puestoId,
        modalidadTurnoId: modalidadTurnoId,
        cantidadElementos: cantidad,
        precioUnitario: 100000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2025, 11, 1),
        sueldoMensualReferenciaPersonal: 1700000,
        bonoMensualReferenciaPersonal: 250000,
      ),
    );
    return linea.linea.id;
  }

  /// Simula una `AsignacionServicio` PREVIA a Etapa 15: escribe
  /// directamente contra el repositorio con `lineaComercialId: null`
  /// (el caso de uso real de asignación, `AsignarEmpleadoServicioUseCase`,
  /// ya lo exige desde Etapa 15 — solo una fila histórica puede quedar
  /// así hoy).
  Future<AsignacionServicioData> crearAsignacionHistorica({
    required String empleadoId,
    required String servicioId,
    String? turnoId,
    DateTime? fechaInicio,
  }) {
    return asignacionRepo.asignar(
      empleadoId: empleadoId,
      servicioId: servicioId,
      fechaInicio: fechaInicio ?? DateTime(2025, 11, 20),
      sueldoMensual: 1700000,
      bonoMensual: 250000,
      turnoId: turnoId,
      lineaComercialId: null,
    );
  }

  test('MILOYILE — reproduce y corrige el bug real: 1 línea vigente + 1 histórico lineaComercialId=NULL → 1/1 · 100% · completo', () async {
    final servicio = await crearServicioActivo();
    final lineaId = await agregarLinea(servicio.id, puestoNombre: 'Elemento Operativo', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final juan = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: juan.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno12x12);

    final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    final fila = resumen.servicios.single;
    expect(fila.requerido, 1);
    expect(fila.cubierto, 1, reason: 'antes de la corrección esto era 0 — el bug real reportado');
    expect(fila.porcentaje, 100);
    expect(fila.completo, isTrue);

    final linea = fila.lineas.single;
    expect(linea.lineaComercialId, lineaId);
    expect(linea.cubierto, 1);
  });

  test('1 línea (cantidad=1) + 2 históricos NULL → cobertura queda capada en 1/1, NUNCA 2/1', () async {
    final servicio = await crearServicioActivo();
    await agregarLinea(servicio.id, puestoNombre: 'Elemento Operativo', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final e1 = await crearEmpleadoDePrueba();
    final e2 = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: e1.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno12x12);
    await crearAsignacionHistorica(empleadoId: e2.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno12x12);

    final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    final fila = resumen.servicios.single;
    expect(fila.requerido, 1);
    expect(fila.cubierto, 1);
    expect(fila.porcentaje, 100);
    expect(fila.cubierto, lessThanOrEqualTo(fila.requerido));
  });

  test('2 líneas distintas + histórico resoluble por turno (coincide con exactamente una) → se atribuye a la línea correcta', () async {
    final servicio = await crearServicioActivo();
    final lineaGuardia = await agregarLinea(servicio.id, puestoNombre: 'Guardia', modalidadTurnoId: SeedIds.modalidadTurno24x24, cantidad: 2);
    final lineaJefe = await agregarLinea(servicio.id, puestoNombre: 'Jefe de Turno', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno12x12);

    final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    final fila = resumen.servicios.single;
    final guardia = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaGuardia);
    final jefe = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaJefe);

    expect(jefe.cubierto, 1, reason: 'único turno compatible es 12x12 — la línea de Jefe de Turno');
    expect(guardia.cubierto, 0, reason: 'el histórico nunca infla la línea de Guardia, que no coincide en turno');
  });

  test('2 líneas + histórico ambiguo (sin turnoId) → NUNCA se atribuye arbitrariamente a ninguna línea', () async {
    final servicio = await crearServicioActivo();
    final lineaGuardia = await agregarLinea(servicio.id, puestoNombre: 'Guardia', modalidadTurnoId: SeedIds.modalidadTurno24x24, cantidad: 2);
    final lineaJefe = await agregarLinea(servicio.id, puestoNombre: 'Jefe de Turno', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: null);

    final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    final fila = resumen.servicios.single;
    final guardia = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaGuardia);
    final jefe = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaJefe);

    expect(guardia.cubierto, 0);
    expect(jefe.cubierto, 0);
    expect(fila.cubierto, 0, reason: 'la asignación existe (Personal la ve) pero no infla ninguna línea hasta regularizarse');
  });

  test('Regularización manual (Maestro) de un histórico ambiguo → el Dashboard cambia a la línea elegida', () async {
    final servicio = await crearServicioActivo();
    final lineaGuardia = await agregarLinea(servicio.id, puestoNombre: 'Guardia', modalidadTurnoId: SeedIds.modalidadTurno24x24, cantidad: 2);
    await agregarLinea(servicio.id, puestoNombre: 'Jefe de Turno', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    final asignacion = await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: null);

    final antes = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    expect(antes.servicios.single.lineas.singleWhere((l) => l.lineaComercialId == lineaGuardia).cubierto, 0);

    final resultado = await regularizarPerfil.ejecutar(asignacionServicioId: asignacion.id, lineaComercialId: lineaGuardia);
    expect(resultado, isA<RegularizarPerfilAsignacionExitoso>());

    final despues = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    final guardia = despues.servicios.single.lineas.singleWhere((l) => l.lineaComercialId == lineaGuardia);
    expect(guardia.cubierto, 1, reason: 'el Dashboard refleja la línea elegida sin reiniciar ni cambiar de pestaña');
  });

  test('nuevas asignaciones con lineaComercialId ya establecido siguen funcionando sin cambios', () async {
    final servicio = await crearServicioActivo();
    final lineaId = await agregarLinea(servicio.id, puestoNombre: 'Elemento Operativo', modalidadTurnoId: SeedIds.modalidadTurno24x24, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    await asignacionRepo.asignar(
      empleadoId: empleado.id,
      servicioId: servicio.id,
      fechaInicio: DateTime(2026, 1, 1),
      sueldoMensual: 1700000,
      bonoMensual: 250000,
      lineaComercialId: lineaId,
    );

    final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 1, 1));
    final fila = resumen.servicios.single;
    expect(fila.cubierto, 1);
    expect(fila.lineas.single.cubierto, 1);
  });

  test('baja/retiro de un histórico NO ambiguo (1 línea) abre la vacante correspondiente', () async {
    final servicio = await crearServicioActivo();
    final lineaId = await agregarLinea(servicio.id, puestoNombre: 'Elemento Operativo', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno12x12);

    // Confirma que sí estaba cubriendo antes del retiro.
    final antes = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 12, 1));
    expect(antes.servicios.single.cubierto, 1);

    await asignacionRepo.retirar(empleadoId: empleado.id, fechaTermino: DateTime(2025, 12, 1), motivo: MotivoTerminoAsignacion.solicitudCliente.name);

    final despues = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 12, 1));
    expect(despues.servicios.single.cubierto, 0);

    final abiertas = await vacanteRepo.listarAbiertas();
    expect(abiertas, hasLength(1), reason: 'la atribución era inequívoca (única línea vigente) — retirar debe abrir su vacante');
    expect(abiertas.single.lineaComercialId, lineaId);
  });

  test('baja/retiro de un histórico AMBIGUO (2 líneas) no abre ninguna vacante arbitrariamente', () async {
    final servicio = await crearServicioActivo();
    await agregarLinea(servicio.id, puestoNombre: 'Guardia', modalidadTurnoId: SeedIds.modalidadTurno24x24, cantidad: 2);
    await agregarLinea(servicio.id, puestoNombre: 'Jefe de Turno', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: null);

    await asignacionRepo.retirar(empleadoId: empleado.id, fechaTermino: DateTime(2025, 12, 1), motivo: MotivoTerminoAsignacion.solicitudCliente.name);

    final abiertas = await vacanteRepo.listarAbiertas();
    expect(abiertas, isEmpty, reason: 'nunca se abre una vacante sobre una atribución que nunca fue inequívoca');
  });

  test('regularizar el perfil de una asignación histórica NO cambia sueldo, bono, fecha de inicio ni historial', () async {
    final servicio = await crearServicioActivo();
    final lineaId = await agregarLinea(servicio.id, puestoNombre: 'Elemento Operativo', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);
    final empleado = await crearEmpleadoDePrueba();
    final fechaOriginal = DateTime(2025, 11, 20);
    final asignacion = await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno12x12, fechaInicio: fechaOriginal);

    final vigenciasSueldoAntes = await asignacionRepo.listarVigenciasSueldoActivas(asignacion.id);

    final resultado = await regularizarPerfil.ejecutar(asignacionServicioId: asignacion.id, lineaComercialId: lineaId);
    expect(resultado, isA<RegularizarPerfilAsignacionExitoso>());

    final actualizada = await asignacionRepo.obtenerPorId(asignacion.id);
    expect(actualizada!.fechaInicio, fechaOriginal);
    expect(actualizada.lineaComercialId, lineaId);

    final vigenciasSueldoDespues = await asignacionRepo.listarVigenciasSueldoActivas(asignacion.id);
    expect(vigenciasSueldoDespues, hasLength(vigenciasSueldoAntes.length));
    expect(vigenciasSueldoDespues.single.sueldoMensual, vigenciasSueldoAntes.single.sueldoMensual);
    expect(vigenciasSueldoDespues.single.bonoMensual, vigenciasSueldoAntes.single.bonoMensual);
    expect(vigenciasSueldoDespues.single.fechaInicioVigencia, vigenciasSueldoAntes.single.fechaInicioVigencia);
  });

  test('cubiertos <= requeridos siempre, incluso mezclando históricos resueltos y ambiguos en el mismo Servicio', () async {
    final servicio = await crearServicioActivo();
    final lineaGuardia = await agregarLinea(servicio.id, puestoNombre: 'Guardia', modalidadTurnoId: SeedIds.modalidadTurno24x24, cantidad: 1);
    await agregarLinea(servicio.id, puestoNombre: 'Jefe de Turno', modalidadTurnoId: SeedIds.modalidadTurno12x12, cantidad: 1);

    // 3 históricos apuntando (por turno) a la línea de Guardia, que solo
    // requiere 1 — nunca debe superar 1/1 aunque haya 3 candidatos.
    for (var i = 0; i < 3; i++) {
      final empleado = await crearEmpleadoDePrueba();
      await crearAsignacionHistorica(empleadoId: empleado.id, servicioId: servicio.id, turnoId: SeedIds.modalidadTurno24x24);
    }
    // Un histórico ambiguo adicional, no debe sumar a ninguna línea.
    final ambiguo = await crearEmpleadoDePrueba();
    await crearAsignacionHistorica(empleadoId: ambiguo.id, servicioId: servicio.id, turnoId: null);

    final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2025, 11, 20));
    final fila = resumen.servicios.single;
    final guardia = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaGuardia);

    expect(guardia.cubierto, lessThanOrEqualTo(guardia.requerido));
    expect(fila.cubierto, lessThanOrEqualTo(fila.requerido));
    expect(fila.porcentaje, lessThanOrEqualTo(100));
  });
}
