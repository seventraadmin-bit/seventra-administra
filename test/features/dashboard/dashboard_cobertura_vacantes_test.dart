// Etapa 15 (rediseño gerencial del Dashboard) — Parte U (invariantes) y
// Parte V (12 escenarios funcionales obligatorios), escenarios 1-6:
// Cobertura operativa y Vacantes operativas. Usa la cadena real
// Cliente → Servicio → Línea comercial → Empleado → AsignacionServicio
// (mismo patrón que `asignacion_servicio_test.dart`) para ejercitar
// `ObtenerCoberturaOperativaUseCase`/`VacanteOperativaRepositoryImpl`
// tal cual los usa el Dashboard — nunca un mock de la lógica que se
// quiere probar.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
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
import 'package:riseg_one/features/personal/data/tables/vacante_operativa_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_servicio_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/retirar_empleado_servicio_usecase.dart';

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
  late RegistrarBajaLaboralUseCase registrarBajaLaboral;
  late AsignarEmpleadoServicioUseCase asignarEmpleadoServicio;
  late RetirarEmpleadoServicioUseCase retirarEmpleadoServicio;
  late ObtenerCoberturaOperativaUseCase obtenerCobertura;

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
    const asignacionValidator = AsignacionServicioValidator();
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, empleadoValidator, servicioRepo, comercialRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, empleadoValidator, AsignacionRepositoryImpl(db), AsignacionVehiculoRepositoryImpl(db));
    asignarEmpleadoServicio =
        AsignarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, servicioRepo, comercialRepo, asignacionValidator);
    retirarEmpleadoServicio = RetirarEmpleadoServicioUseCase(empleadoRepo, asignacionRepo, asignacionValidator);
    obtenerCobertura = ObtenerCoberturaOperativaUseCase(servicioRepo, comercialRepo, vacanteRepo);
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
      fechaIngreso: DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  var puestoContador = 0;

  /// Crea un Servicio activo con UNA línea comercial vigente cuyo
  /// requerimiento (`cantidadElementos`) es configurable — a diferencia
  /// del helper de `asignacion_servicio_test.dart` (fijo en 10), aquí
  /// el requerimiento exacto es el dato bajo prueba en cada escenario.
  Future<({ServicioData servicio, String lineaId})> crearServicioConLinea({
    required int cantidadElementos,
    String puestoNombre = 'Guardia',
  }) async {
    final cliente = await crearClienteDePrueba();
    final r1 = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Servicio de prueba', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    var servicio = (r1 as GuardarServicioExitoso).servicio;

    puestoContador++;
    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-${puestoContador.toString().padLeft(6, '0')}',
        nombre: puestoNombre,
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final linea = await comercialRepo.crearLinea(
      servicioId: servicio.id,
      datos: LineaComercialValidada(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: cantidadElementos,
        precioUnitario: 100000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: 0,
      ),
    );

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

    return (servicio: servicio, lineaId: linea.linea.id);
  }

  group('ObtenerCoberturaOperativaUseCase — escenarios obligatorios (Parte V)', () {
    test('Escenario 1 — cobertura completa: 1 requerido, 1 vigente asignado → 1/1 · 100% · completo', () async {
      final s = await crearServicioConLinea(cantidadElementos: 1);
      final empleado = await crearEmpleadoDePrueba();
      await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: s.servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        lineaComercialId: s.lineaId,
      );

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 1));
      final fila = resumen.servicios.single;
      expect(fila.requerido, 1);
      expect(fila.cubierto, 1);
      expect(fila.porcentaje, 100);
      expect(fila.completo, isTrue);
      expect(fila.vacantes, 0);
    });

    test('Escenario 2 — vacante por baja: 1 requerido, empleado asignado da de baja → 0/1 · 0% · vacante abierta', () async {
      final s = await crearServicioConLinea(cantidadElementos: 1);
      final empleado = await crearEmpleadoDePrueba();
      await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: s.servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        lineaComercialId: s.lineaId,
      );

      await registrarBajaLaboral.ejecutar(empleadoId: empleado.id, fechaBaja: DateTime(2026, 2, 10), motivo: MotivoBajaEmpleado.renuncia);

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 10));
      final fila = resumen.servicios.single;
      expect(fila.requerido, 1);
      expect(fila.cubierto, 0);
      expect(fila.porcentaje, 0);
      expect(fila.completo, isFalse);
      expect(fila.vacantes, 1);

      final abiertas = await vacanteRepo.listarAbiertas();
      expect(abiertas, hasLength(1));
      expect(abiertas.single.motivoApertura, MotivoTerminoAsignacion.bajaEmpleado.name);
      expect(abiertas.single.estatus, EstatusVacanteOperativa.abierta.name);
    });

    test('Escenario 3 — antigüedad de vacante: 4 días desde la apertura hasta "hoy" (fecha inyectada, no reloj real)', () async {
      final s = await crearServicioConLinea(cantidadElementos: 1);
      final empleado = await crearEmpleadoDePrueba();
      await asignarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        servicioId: s.servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        lineaComercialId: s.lineaId,
      );
      await retirarEmpleadoServicio.ejecutar(
        empleadoId: empleado.id,
        fechaTermino: DateTime(2026, 2, 5),
        motivo: MotivoTerminoAsignacion.solicitudCliente,
      );

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 9));
      expect(resumen.servicios.single.vacanteMasAntigua?.inDays, 4);
      expect(resumen.vacanteMasAntigua?.inDays, 4);
    });

    test('Escenario 4 — cobertura después de reemplazo: nueva asignación cierra la vacante, la duración queda en el historial', () async {
      final s = await crearServicioConLinea(cantidadElementos: 1);
      final saliente = await crearEmpleadoDePrueba();
      await asignarEmpleadoServicio.ejecutar(
        empleadoId: saliente.id,
        servicioId: s.servicio.id,
        fechaInicio: DateTime(2026, 2, 1),
        lineaComercialId: s.lineaId,
      );
      await retirarEmpleadoServicio.ejecutar(
        empleadoId: saliente.id,
        fechaTermino: DateTime(2026, 2, 5),
        motivo: MotivoTerminoAsignacion.solicitudCliente,
      );

      final entrante = await crearEmpleadoDePrueba();
      await asignarEmpleadoServicio.ejecutar(
        empleadoId: entrante.id,
        servicioId: s.servicio.id,
        fechaInicio: DateTime(2026, 2, 9),
        lineaComercialId: s.lineaId,
      );

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 9));
      final fila = resumen.servicios.single;
      expect(fila.requerido, 1);
      expect(fila.cubierto, 1);
      expect(fila.completo, isTrue);
      expect(fila.vacanteMasAntigua, isNull, reason: 'ya no hay ninguna vacante ABIERTA');

      final historial = await vacanteRepo.listarPorLinea(s.lineaId);
      expect(historial, hasLength(1));
      expect(historial.single.estatus, EstatusVacanteOperativa.cubierta.name);
      expect(historial.single.fechaCobertura, DateTime(2026, 2, 9));
      expect(historial.single.fechaCobertura!.difference(historial.single.fechaApertura).inDays, 4, reason: 'la duración real queda conservada en el historial');
    });

    test('Escenario 5 — múltiples posiciones: 3 requeridas, 2 asignadas → 2/3 · nunca 100%', () async {
      final s = await crearServicioConLinea(cantidadElementos: 3);
      for (var i = 0; i < 2; i++) {
        final empleado = await crearEmpleadoDePrueba();
        await asignarEmpleadoServicio.ejecutar(
          empleadoId: empleado.id,
          servicioId: s.servicio.id,
          fechaInicio: DateTime(2026, 2, 1),
          lineaComercialId: s.lineaId,
        );
      }

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 1));
      final fila = resumen.servicios.single;
      expect(fila.requerido, 3);
      expect(fila.cubierto, 2);
      expect(fila.porcentaje, closeTo(66.67, 0.01));
      expect(fila.completo, isFalse);
      expect(fila.vacantes, 1);
    });

    test(
        'Escenario 6 — perfiles distintos: Guardia 2 requeridos + Jefe 1 requerido, 3 guardias asignados y 0 jefes → '
        'Guardia 2/2 (tope), Jefe 0/1, Global 2/3 — NUNCA 3/3', () async {
      final cliente = await crearClienteDePrueba();
      final r1 = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(nombre: 'Servicio multiperfil', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
      var servicio = (r1 as GuardarServicioExitoso).servicio;

      Future<String> crearLinea(String nombrePuesto, int cantidad) async {
        puestoContador++;
        final puesto = await puestoRepo.crear(
          PuestoCompanion.insert(
            codigo: 'PUE-${puestoContador.toString().padLeft(6, '0')}',
            nombre: nombrePuesto,
            areaId: SeedIds.areaOperaciones,
            tipo: 'operativo',
            nivelJerarquico: 5,
          ),
        );
        final linea = await comercialRepo.crearLinea(
          servicioId: servicio.id,
          datos: LineaComercialValidada(
            puestoId: puesto.id,
            modalidadTurnoId: SeedIds.modalidadTurno24x24,
            cantidadElementos: cantidad,
            precioUnitario: 100000,
            tratamientoIva: TratamientoIva.noAplica,
            fechaInicioVigencia: DateTime(2026, 1, 1),
            sueldoMensualReferenciaPersonal: 1500000,
            bonoMensualReferenciaPersonal: 0,
          ),
        );
        return linea.linea.id;
      }

      final lineaGuardia = await crearLinea('Guardia', 2);
      final lineaJefe = await crearLinea('Jefe de turno', 1);

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

      for (var i = 0; i < 3; i++) {
        final empleado = await crearEmpleadoDePrueba();
        await asignarEmpleadoServicio.ejecutar(
          empleadoId: empleado.id,
          servicioId: servicio.id,
          fechaInicio: DateTime(2026, 2, 1),
          lineaComercialId: lineaGuardia,
        );
      }

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 1));
      final fila = resumen.servicios.single;
      final guardia = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaGuardia);
      final jefe = fila.lineas.singleWhere((l) => l.lineaComercialId == lineaJefe);

      expect(guardia.requerido, 2);
      expect(guardia.cubierto, 2, reason: '3 asignados pero el tope es 2 — nunca 3/2');
      expect(jefe.requerido, 1);
      expect(jefe.cubierto, 0);

      expect(fila.requerido, 3);
      expect(fila.cubierto, 2, reason: 'Global = suma capada por línea, NUNCA 3/3');
      expect(fila.porcentaje, closeTo(66.67, 0.01));
    });
  });

  group('Invariantes (Parte U)', () {
    test('cobertura nunca excede 100% aunque haya más asignados que requeridos en una línea', () async {
      final s = await crearServicioConLinea(cantidadElementos: 1);
      for (var i = 0; i < 3; i++) {
        final empleado = await crearEmpleadoDePrueba();
        if (i > 0) {
          // Solo el primero puede quedar vigente en esa línea con
          // capacidad 1 — los siguientes se asignan a una segunda
          // línea del MISMO servicio para no chocar con la unicidad de
          // "un Empleado, una asignación vigente"; lo relevante aquí es
          // que `asignadosVigentes` de la primera línea no puede pasar
          // de 1 en los datos, así que se fuerza el escenario límite
          // insertando una segunda AsignacionServicio directo contra el
          // repositorio (escritura cruda, sin pasar por el use case) —
          // el propio caso de uso de Cobertura es quien debe capar el
          // resultado, no la captura.
          await asignacionRepo.asignar(
            empleadoId: empleado.id,
            servicioId: s.servicio.id,
            fechaInicio: DateTime(2026, 2, 1),
            sueldoMensual: 1500000,
            bonoMensual: 0,
            lineaComercialId: s.lineaId,
          );
        } else {
          await asignarEmpleadoServicio.ejecutar(
            empleadoId: empleado.id,
            servicioId: s.servicio.id,
            fechaInicio: DateTime(2026, 2, 1),
            lineaComercialId: s.lineaId,
          );
        }
      }

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 1));
      final fila = resumen.servicios.single;
      expect(fila.cubierto, lessThanOrEqualTo(fila.requerido));
      expect(fila.porcentaje, lessThanOrEqualTo(100));
      expect(fila.vacantes, 0, reason: 'requerido - cubierto nunca es negativo');
    });

    test('un Servicio suspendido/terminado deja de contar en Cobertura operativa (solo activo participa)', () async {
      final s = await crearServicioConLinea(cantidadElementos: 1);
      await cambiarEstatusServicio.ejecutar(servicioId: s.servicio.id, nuevo: EstatusServicio.suspendido, motivo: 'Motivo de prueba');

      final resumen = await obtenerCobertura.ejecutar(hoy: DateTime(2026, 2, 1));
      expect(resumen.serviciosActivos, 0);
      expect(resumen.servicios, isEmpty);
    });
  });
}
