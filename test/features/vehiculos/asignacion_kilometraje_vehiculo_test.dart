import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_kilometraje_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/asignar_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_asignacion_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/retirar_asignacion_vehiculo_usecase.dart';

/// Cubre Asignaciones y kilometraje de Vehículos (Etapa 8B) — destino
/// Empleado/Servicio con FK reales, una sola vigente, estatus
/// `asignado` automático (nunca manual), cambio/retiro, baja cierra la
/// asignación y bloquea nuevas, y el ledger de kilometraje (incremental,
/// rechazo de decremento, corrección explícita, lecturas de entrega/
/// devolución).
void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late AsignacionVehiculoRepositoryImpl asignacionRepo;
  late VehiculoKilometrajeRepositoryImpl kilometrajeRepo;
  late CrearVehiculoUseCase crearVehiculo;
  late AsignarVehiculoUseCase asignarVehiculo;
  late CambiarAsignacionVehiculoUseCase cambiarAsignacion;
  late RetirarAsignacionVehiculoUseCase retirarAsignacion;
  late RegistrarKilometrajeVehiculoUseCase registrarKilometraje;
  late DarDeBajaVehiculoUseCase darDeBaja;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
    vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
    kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearVehiculo = CrearVehiculoUseCase(vehiculoRepo, generarCodigo);
    asignarVehiculo = AsignarVehiculoUseCase(vehiculoRepo, asignacionRepo, kilometrajeRepo);
    cambiarAsignacion = CambiarAsignacionVehiculoUseCase(asignacionRepo);
    retirarAsignacion = RetirarAsignacionVehiculoUseCase(asignacionRepo, kilometrajeRepo);
    registrarKilometraje = RegistrarKilometrajeVehiculoUseCase(kilometrajeRepo, vehiculoRepo);
    darDeBaja = DarDeBajaVehiculoUseCase(vehiculoRepo);
  });

  tearDown(() => db.close());

  Future<VehiculoData> crearVehiculoDePrueba() async {
    final resultado = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
    return (resultado as CrearVehiculoExitoso).vehiculo;
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
    final cliente = await db
        .into(db.cliente)
        .insertReturning(ClienteCompanion.insert(codigo: 'CLI-$codigo', nombreComercial: 'Sportium'));
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

  group('AsignarVehiculoUseCase', () {
    test('asigna a un Empleado y el estatus pasa a asignado automáticamente', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      expect(resultado, isA<AsignarVehiculoExitoso>());
      final asignacion = (resultado as AsignarVehiculoExitoso).asignacion;
      expect(asignacion.empleadoId, empleado.id);
      expect(asignacion.servicioId, isNull);

      final actualizado = await vehiculoRepo.obtenerPorId(vehiculo.id);
      expect(actualizado!.estatus, 'asignado', reason: 'nunca se marca a mano — lo hace la transacción de asignar');
    });

    test('asigna a un Servicio', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final servicio = await crearServicioDePrueba();

      final resultado = await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 1, 5),
      );

      expect(resultado, isA<AsignarVehiculoExitoso>());
      final asignacion = (resultado as AsignarVehiculoExitoso).asignacion;
      expect(asignacion.servicioId, servicio.id);
      expect(asignacion.empleadoId, isNull);
    });

    test('rechaza ni empleado ni servicio, o ambos', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final ninguno = await asignarVehiculo.ejecutar(vehiculoId: vehiculo.id, fechaInicio: DateTime(2026, 1, 5));
      expect(ninguno, isA<AsignarVehiculoDestinoInvalido>());

      final ambos = await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 1, 5),
      );
      expect(ambos, isA<AsignarVehiculoDestinoInvalido>());
    });

    test('rechaza asignar un Vehículo que ya está asignado (solo una asignación vigente)', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      await asignarVehiculo.ejecutar(vehiculoId: vehiculo.id, empleadoId: empleado1.id, fechaInicio: DateTime(2026, 1, 5));
      final segundoIntento = await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado2.id,
        fechaInicio: DateTime(2026, 1, 6),
      );

      expect(segundoIntento, isA<AsignarVehiculoNoDisponible>());
      expect((segundoIntento as AsignarVehiculoNoDisponible).estatusActual, 'asignado');
    });

    test('índice único parcial rechaza a nivel de BD una segunda asignación vigente para el mismo Vehículo', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      await asignacionRepo.crear(vehiculoId: vehiculo.id, empleadoId: empleado1.id, fechaInicio: DateTime(2026, 1, 5));

      await expectLater(
        asignacionRepo.crear(vehiculoId: vehiculo.id, empleadoId: empleado2.id, fechaInicio: DateTime(2026, 1, 6)),
        throwsA(anything),
        reason: 'idx_asignacion_vehiculo_vigente protege incluso saltándose el caso de uso',
      );
    });

    test('rechaza asignar un Vehículo dado de baja', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final resultado = await asignarVehiculo.ejecutar(vehiculoId: vehiculo.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));

      expect(resultado, isA<AsignarVehiculoNoDisponible>());
      expect((resultado as AsignarVehiculoNoDisponible).estatusActual, 'baja');
    });

    test('captura kilometraje de entrega opcional — queda en el ledger con origen entrega', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();

      await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
        kilometrajeEntrega: 10000,
      );

      final actual = await kilometrajeRepo.obtenerActual(vehiculo.id);
      expect(actual, isNotNull);
      expect(actual!.kilometraje, 10000);
      expect(actual.origen, OrigenKilometrajeVehiculo.entrega.name);
    });

    test('kilometraje de entrega no puede ser menor al último conocido', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        kilometraje: 20000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      final resultado = await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
        kilometrajeEntrega: 15000,
      );

      expect(resultado, isA<AsignarVehiculoKilometrajeMenorAlActual>());
      expect((resultado as AsignarVehiculoKilometrajeMenorAlActual).actual, 20000);
    });
  });

  group('CambiarAsignacionVehiculoUseCase', () {
    test('cambio Empleado→Servicio: cierra la anterior y crea la nueva, el estatus se mantiene asignado', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final asignacionEmpleado = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;

      final resultado = await cambiarAsignacion.ejecutar(
        asignacionVehiculoActualId: asignacionEmpleado.id,
        fecha: DateTime(2026, 3, 1),
        nuevoServicioId: servicio.id,
      );

      expect(resultado, isA<CambiarAsignacionVehiculoExitoso>());
      final nueva = (resultado as CambiarAsignacionVehiculoExitoso).nuevaAsignacion;
      expect(nueva.servicioId, servicio.id);
      expect(nueva.vehiculoId, vehiculo.id);

      final anteriorCerrada = await asignacionRepo.obtenerPorId(asignacionEmpleado.id);
      expect(anteriorCerrada!.fechaTermino, DateTime(2026, 3, 1));
      expect(anteriorCerrada.motivoTermino, 'cambioResponsable');

      final vehiculoActualizado = await vehiculoRepo.obtenerPorId(vehiculo.id);
      expect(vehiculoActualizado!.estatus, 'asignado', reason: 'nunca pasa visiblemente por disponible');
    });

    test('cambio Servicio→Empleado', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final servicio = await crearServicioDePrueba();
      final empleado = await crearEmpleadoDePrueba();

      final asignacionServicio = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        servicioId: servicio.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;

      final resultado = await cambiarAsignacion.ejecutar(
        asignacionVehiculoActualId: asignacionServicio.id,
        fecha: DateTime(2026, 3, 1),
        nuevoEmpleadoId: empleado.id,
      );

      expect(resultado, isA<CambiarAsignacionVehiculoExitoso>());
      expect((resultado as CambiarAsignacionVehiculoExitoso).nuevaAsignacion.empleadoId, empleado.id);
    });

    test('el historial conserva ambas filas intactas tras el cambio', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final primera = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;
      await cambiarAsignacion.ejecutar(
        asignacionVehiculoActualId: primera.id,
        fecha: DateTime(2026, 3, 1),
        nuevoServicioId: servicio.id,
      );

      final historial = await asignacionRepo.listarPorVehiculo(vehiculo.id);
      expect(historial, hasLength(2));
      expect(historial.map((a) => a.empleadoId), contains(empleado.id));
      expect(historial.map((a) => a.servicioId), contains(servicio.id));
    });
  });

  group('RetirarAsignacionVehiculoUseCase', () {
    test('retira y el Vehículo vuelve a disponible', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;

      final resultado = await retirarAsignacion.ejecutar(asignacionVehiculoId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      expect(resultado, isA<RetirarAsignacionVehiculoExitoso>());
      final actualizado = await vehiculoRepo.obtenerPorId(vehiculo.id);
      expect(actualizado!.estatus, 'disponible');
    });

    test('no vuelve a disponible si mientras tanto se marcó fuera de servicio', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;

      // Cambio manual directo (saltando el caso de uso 8A, que hoy no
      // bloquea esta transición mientras asignado) — simula el
      // escenario real que el punto 2 de Marlon describe.
      await vehiculoRepo.cambiarEstatus(vehiculoId: vehiculo.id, estatus: 'fueraDeServicio');

      await retirarAsignacion.ejecutar(asignacionVehiculoId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      final actualizado = await vehiculoRepo.obtenerPorId(vehiculo.id);
      expect(actualizado!.estatus, 'fueraDeServicio', reason: '"vuelve a disponible salvo que esté en mantenimiento/fuera de servicio/baja"');
    });

    test('captura kilometraje de devolución opcional — origen devolucion', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
        kilometrajeEntrega: 10000,
      )) as AsignarVehiculoExitoso)
          .asignacion;

      await retirarAsignacion.ejecutar(
        asignacionVehiculoId: asignacion.id,
        fechaTermino: DateTime(2026, 2, 1),
        kilometrajeDevolucion: 12000,
      );

      final actual = await kilometrajeRepo.obtenerActual(vehiculo.id);
      expect(actual!.kilometraje, 12000);
      expect(actual.origen, OrigenKilometrajeVehiculo.devolucion.name);
    });

    test('rechaza retirar una asignación ya cerrada', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;
      await retirarAsignacion.ejecutar(asignacionVehiculoId: asignacion.id, fechaTermino: DateTime(2026, 2, 1));

      final segundoIntento = await retirarAsignacion.ejecutar(asignacionVehiculoId: asignacion.id, fechaTermino: DateTime(2026, 2, 2));
      expect(segundoIntento, isA<RetirarAsignacionVehiculoYaCerrada>());
    });
  });

  group('Baja de Vehículo y asignaciones (punto 11)', () {
    test('la baja cierra la asignación vigente automáticamente', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
      )) as AsignarVehiculoExitoso)
          .asignacion;

      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final cerrada = await asignacionRepo.obtenerPorId(asignacion.id);
      expect(cerrada!.fechaTermino, DateTime(2026, 3, 1));
      expect(cerrada.motivoTermino, 'bajaVehiculo');
    });

    test('la baja bloquea nuevas asignaciones', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final resultado = await asignarVehiculo.ejecutar(vehiculoId: vehiculo.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));
      expect(resultado, isA<AsignarVehiculoNoDisponible>());
    });

    test('baja sin asignación vigente no falla (no-op)', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaVehiculo.venta);
      expect(resultado, isA<DarDeBajaVehiculoExitoso>());
    });

    test('historial de asignaciones y kilometraje se conservan intactos tras la baja', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await asignarVehiculo.ejecutar(
        vehiculoId: vehiculo.id,
        empleadoId: empleado.id,
        fechaInicio: DateTime(2026, 1, 5),
        kilometrajeEntrega: 5000,
      );
      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final historialAsignaciones = await asignacionRepo.listarPorVehiculo(vehiculo.id);
      expect(historialAsignaciones, hasLength(1));

      final historialKm = await kilometrajeRepo.listarPorVehiculo(vehiculo.id);
      expect(historialKm, hasLength(1));
      expect(historialKm.single.kilometraje, 5000);
    });
  });

  group('RegistrarKilometrajeVehiculoUseCase', () {
    test('lectura incremental normal', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        kilometraje: 1000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );
      final resultado = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 2, 1),
        kilometraje: 2000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      expect(resultado, isA<RegistrarKilometrajeVehiculoExitoso>());
      final actual = await kilometrajeRepo.obtenerActual(vehiculo.id);
      expect(actual!.kilometraje, 2000);
    });

    test('rechaza kilometraje menor al actual sin corrección', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        kilometraje: 5000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      final resultado = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 2, 1),
        kilometraje: 4000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      expect(resultado, isA<RegistrarKilometrajeVehiculoMenorAlActual>());
      expect((resultado as RegistrarKilometrajeVehiculoMenorAlActual).actual, 5000);
    });

    test('corrección explícita permite bajar el valor, pero exige observaciones', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        kilometraje: 5000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      final sinObservaciones = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 2, 1),
        kilometraje: 3000,
        origen: OrigenKilometrajeVehiculo.correccion.name,
      );
      expect(sinObservaciones, isA<RegistrarKilometrajeVehiculoObservacionesRequeridas>());

      final conObservaciones = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 2, 1),
        kilometraje: 3000,
        origen: OrigenKilometrajeVehiculo.correccion.name,
        observaciones: 'Odómetro reemplazado, lectura anterior errónea',
      );
      expect(conObservaciones, isA<RegistrarKilometrajeVehiculoExitoso>());

      final actual = await kilometrajeRepo.obtenerActual(vehiculo.id);
      expect(actual!.kilometraje, 3000, reason: 'la trazabilidad queda en el historial, nunca se pierde la lectura anterior');

      final historial = await kilometrajeRepo.listarPorVehiculo(vehiculo.id);
      expect(historial, hasLength(2), reason: 'ambas lecturas quedan — la corrección nunca sobrescribe la anterior');
    });

    test('rechaza kilometraje negativo', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        kilometraje: -1,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );
      expect(resultado, isA<RegistrarKilometrajeVehiculoInvalido>());
    });
  });
}
