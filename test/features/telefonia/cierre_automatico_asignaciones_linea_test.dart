// Mini-etapa "Cierre automático de asignaciones de Telefonía".
//
// LA REGLA: una línea telefónica no puede conservar una asignación
// vigente cuando la línea está dada de baja o cuando el empleado
// asignado deja de tener relación laboral activa. El historial NUNCA se
// borra: la asignación se CIERRA.
//
// Estado previo auditado: la baja de LÍNEA ya cerraba su asignación
// (`cerrarPorBajaLinea`, Etapa 9B). La baja de EMPLEADO no: cerraba su
// AsignacionServicio pero dejaba la línea telefónica vigente, con lo
// que quedaba "Empleado = Baja, Línea = Todavía asignada".

import 'package:drift/drift.dart' hide isNull;
import 'package:riseg_one/features/telefonia/domain/repositories/asignacion_linea_telefonica_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/asignacion_linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_equipo_repository.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';

/// El aparato físico pertenece a Inventario y no participa de esta
/// mini-etapa (§4): se aísla para que el fallo, si lo hubiera, sea de lo
/// que se está probando.
class _EquipoRepoVacio implements LineaTelefonicaEquipoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Igual que el anterior, pero con `cerrarPorBajaLinea` funcional: es el
/// único método que la baja de línea sí invoca.
class _EquipoRepoNoOp implements LineaTelefonicaEquipoRepository {
  @override
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late AsignacionLineaTelefonicaRepositoryImpl asignacionRepo;
  late LineaTelefonicaRepositoryImpl lineaRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late String actorId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionRepo, _EquipoRepoNoOp());
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));

    final actor = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    actorId = actor.id;
  });

  tearDown(() => db.close());

  var consecutivo = 0;

  Future<EmpleadoData> crearEmpleado({String nombre = 'Ana'}) async {
    final n = (++consecutivo).toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: consecutivo,
            nombres: nombre,
            apellidoPaterno: 'Ruiz',
            sexo: 'femenino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'RUSA900101MDFXXX$n',
            rfc: 'RUSA900101A$n',
            nss: '123456789$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<LineaTelefonicaData> crearLinea(String codigo) {
    return lineaRepo.crear(
      codigo: codigo,
      operador: OperadorTelefonico.telcel.name,
      modalidadSim: ModalidadSim.fisica.name,
    );
  }

  Future<AsignacionLineaTelefonicaData> asignar(String lineaId, String empleadoId) {
    return asignacionRepo.crear(
      lineaTelefonicaId: lineaId,
      empleadoId: empleadoId,
      fechaInicio: DateTime(2026, 1, 1),
      actorUsuarioId: actorId,
    );
  }

  Future<List<AsignacionLineaTelefonicaData>> vigentesDe(String empleadoId) async {
    return (db.select(db.asignacionLineaTelefonica)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
        .get();
  }

  // ---------------------------------------------------------------
  // CASO A — baja de línea
  // ---------------------------------------------------------------

  group('Caso A — baja de LÍNEA con asignación vigente', () {
    test('la línea queda de baja, sin asignación vigente, y el historial se conserva', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      final asignacion = await asignar(linea.id, empleado.id);

      await lineaRepo.darDeBaja(
        lineaTelefonicaId: linea.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivoBaja: MotivoBajaLineaTelefonica.cancelacion.name,
        actorUsuarioId: actorId,
      );

      expect((await lineaRepo.obtenerPorId(linea.id))!.estatus, 'baja');
      expect(await asignacionRepo.obtenerActivaPorLinea(linea.id), isNull);

      // El historial NO se borra: misma fila, ahora cerrada.
      final historial = await asignacionRepo.listarPorLinea(linea.id);
      expect(historial, hasLength(1));
      expect(historial.single.id, asignacion.id);
      expect(historial.single.empleadoId, empleado.id, reason: 'se conserva a quién estuvo asignada');
      expect(historial.single.fechaTermino, DateTime(2026, 6, 30));
      expect(historial.single.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.bajaLinea.name);
    });

    test('el empleado NO se da de baja por dar de baja su línea', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, empleado.id);

      await lineaRepo.darDeBaja(
        lineaTelefonicaId: linea.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivoBaja: MotivoBajaLineaTelefonica.cancelacion.name,
      );

      expect((await empleadoRepo.obtenerPorId(empleado.id))!.estatus, EstatusEmpleado.activo.name);
    });
  });

  // ---------------------------------------------------------------
  // CASO B y D — baja de empleado
  // ---------------------------------------------------------------

  group('Caso B — baja de EMPLEADO con línea vigente', () {
    test('la asignación se cierra, la línea NO se da de baja y queda reasignable', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      final asignacion = await asignar(linea.id, empleado.id);

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
        actorUsuarioId: actorId,
      );

      expect((await empleadoRepo.obtenerPorId(empleado.id))!.estatus, EstatusEmpleado.baja.name);
      expect(await vigentesDe(empleado.id), isEmpty, reason: 'nunca "Empleado = Baja, Línea = Todavía asignada"');

      final lineaTrasBaja = await lineaRepo.obtenerPorId(linea.id);
      expect(lineaTrasBaja!.estatus, 'activa', reason: 'quien se fue es la persona, no la línea');
      expect(lineaTrasBaja.fechaBaja, isNull);
      expect(await asignacionRepo.obtenerActivaPorLinea(linea.id), isNull, reason: 'disponible para reasignarse');

      // Historial íntegro, con el motivo correcto y el actor real.
      final cerrada = await asignacionRepo.obtenerPorId(asignacion.id);
      expect(cerrada!.fechaTermino, DateTime(2026, 6, 30), reason: 'misma fecha efectiva que la baja laboral');
      expect(cerrada.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.bajaEmpleado.name);
      expect(cerrada.empleadoId, empleado.id);
      expect(cerrada.actorUsuarioId, actorId, reason: 'el cierre derivado conserva quién originó la baja');
    });

    test('la línea liberada SÍ se puede reasignar a otra persona', () async {
      final ana = await crearEmpleado(nombre: 'Ana');
      final beto = await crearEmpleado(nombre: 'Beto');
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, ana.id);

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: ana.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
      );

      // El índice único parcial sólo permite una vigente por línea: si
      // el cierre no hubiera ocurrido, esto reventaría.
      final nueva = await asignar(linea.id, beto.id);
      expect((await asignacionRepo.obtenerActivaPorLinea(linea.id))!.id, nueva.id);
      expect(await asignacionRepo.listarPorLinea(linea.id), hasLength(2));
    });

    test('una baja sin líneas asignadas no rompe nada (no-op)', () async {
      final empleado = await crearEmpleado();

      final r = await empleadoRepo.registrarBajaLaboral(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
      );

      expect(r.estatus, EstatusEmpleado.baja.name);
    });
  });

  group('Caso D — dos líneas vigentes de la misma persona', () {
    test('ambas se cierran en la misma operación', () async {
      final empleado = await crearEmpleado();
      final linea1 = await crearLinea('LIN-000001');
      final linea2 = await crearLinea('LIN-000002');
      await asignar(linea1.id, empleado.id);
      await asignar(linea2.id, empleado.id);

      expect(await vigentesDe(empleado.id), hasLength(2), reason: 'la unicidad es por LÍNEA, no por empleado');

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
        actorUsuarioId: actorId,
      );

      expect(await vigentesDe(empleado.id), isEmpty);
      for (final lineaId in [linea1.id, linea2.id]) {
        final cerrada = (await asignacionRepo.listarPorLinea(lineaId)).single;
        expect(cerrada.fechaTermino, DateTime(2026, 6, 30));
        expect(cerrada.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.bajaEmpleado.name);
        expect((await lineaRepo.obtenerPorId(lineaId))!.estatus, 'activa');
      }
    });
  });

  // ---------------------------------------------------------------
  // CASO E — atomicidad
  // ---------------------------------------------------------------

  group('Caso E — atomicidad: todo o nada', () {
    test('si falla el cierre de las líneas, la baja laboral tampoco ocurre', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, empleado.id);

      // Un repositorio de líneas que revienta justo en el cierre: es la
      // ÚNICA forma de comprobar que ambas escrituras comparten
      // transacción y no quedan a medias.
      final empleadoRepoQueFalla = EmpleadoRepositoryImpl(
        db,
        AsignacionServicioRepositoryImpl(db),
        asignacionLineaTelefonicaRepository: _AsignacionLineaQueFalla(),
      );

      await expectLater(
        empleadoRepoQueFalla.registrarBajaLaboral(
          empleadoId: empleado.id,
          fechaBaja: DateTime(2026, 6, 30),
          motivo: MotivoBajaEmpleado.renuncia.name,
        ),
        throwsA(anything),
      );

      // Rollback COMPLETO: ni el empleado quedó de baja, ni la
      // asignación quedó cerrada a medias.
      expect((await empleadoRepo.obtenerPorId(empleado.id))!.estatus, EstatusEmpleado.activo.name);
      expect(await vigentesDe(empleado.id), hasLength(1));
      expect((await asignacionRepo.obtenerActivaPorLinea(linea.id))!.fechaTermino, isNull);
      // Y tampoco quedó el evento de baja del empleado.
      final eventos = await (db.select(db.empleadoEvento)..where((t) => t.empleadoId.equals(empleado.id))).get();
      expect(eventos.where((e) => e.tipoEvento == 'bajaLaboral'), isEmpty);
    });

    test('si falla la baja de la línea, la asignación tampoco se cierra', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, empleado.id);

      // El repositorio de equipo revienta: `darDeBaja` lo invoca ANTES
      // de cerrar la asignación y de marcar la línea.
      final lineaRepoQueFalla = LineaTelefonicaRepositoryImpl(db, asignacionRepo, _EquipoRepoVacio());

      await expectLater(
        lineaRepoQueFalla.darDeBaja(
          lineaTelefonicaId: linea.id,
          fechaBaja: DateTime(2026, 6, 30),
          motivoBaja: MotivoBajaLineaTelefonica.cancelacion.name,
        ),
        throwsA(anything),
      );

      expect((await lineaRepo.obtenerPorId(linea.id))!.estatus, 'activa');
      expect((await asignacionRepo.obtenerActivaPorLinea(linea.id))!.fechaTermino, isNull);
    });
  });

  // ---------------------------------------------------------------
  // CASO C — reingreso
  // ---------------------------------------------------------------

  group('Caso C — el reingreso NO revive asignaciones anteriores', () {
    test('Ana reingresa meses después y su línea sigue cerrada', () async {
      final ana = await crearEmpleado(nombre: 'Ana');
      final linea = await crearLinea('LIN-000001');
      final asignacion = await asignar(linea.id, ana.id);

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: ana.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
      );
      await empleadoRepo.registrarReingreso(empleadoId: ana.id, fechaIngreso: DateTime(2026, 11, 1));

      expect((await empleadoRepo.obtenerPorId(ana.id))!.estatus, EstatusEmpleado.activo.name);
      expect(
        await vigentesDe(ana.id),
        isEmpty,
        reason: 'la asignación anterior pertenece al periodo laboral que terminó',
      );
      final historica = await asignacionRepo.obtenerPorId(asignacion.id);
      expect(historica!.fechaTermino, DateTime(2026, 6, 30), reason: 'sigue cerrada, con su fecha original');
      expect(historica.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.bajaEmpleado.name);
      expect(await asignacionRepo.obtenerActivaPorLinea(linea.id), isNull);
    });

    test('si la necesita otra vez, hace falta una asignación NUEVA y explícita', () async {
      final ana = await crearEmpleado(nombre: 'Ana');
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, ana.id);
      await empleadoRepo.registrarBajaLaboral(
        empleadoId: ana.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
      );
      await empleadoRepo.registrarReingreso(empleadoId: ana.id, fechaIngreso: DateTime(2026, 11, 1));

      await asignar(linea.id, ana.id);

      expect(await vigentesDe(ana.id), hasLength(1));
      expect(
        await asignacionRepo.listarPorLinea(linea.id),
        hasLength(2),
        reason: 'dos filas: la histórica cerrada y la nueva — nunca se reabre la anterior',
      );
    });
  });

  // ---------------------------------------------------------------
  // §9 — INVARIANTES
  // ---------------------------------------------------------------

  group('§9 — invariantes', () {
    test('línea de baja ⇒ CERO asignaciones vigentes', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, empleado.id);
      await lineaRepo.darDeBaja(
        lineaTelefonicaId: linea.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivoBaja: MotivoBajaLineaTelefonica.cancelacion.name,
      );

      final vigentes = await (db.select(db.asignacionLineaTelefonica)
            ..where((t) => t.lineaTelefonicaId.equals(linea.id) & t.fechaTermino.isNull()))
          .get();
      expect(vigentes, isEmpty);
    });

    test('empleado sin periodo laboral activo ⇒ CERO asignaciones de línea vigentes', () async {
      final empleado = await crearEmpleado();
      for (final codigo in ['LIN-000001', 'LIN-000002', 'LIN-000003']) {
        final linea = await crearLinea(codigo);
        await asignar(linea.id, empleado.id);
      }

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
      );

      expect(await vigentesDe(empleado.id), isEmpty);
      expect(await asignacionRepo.obtenerActivaPorEmpleado(empleado.id), isNull);
    });

    test('máximo UNA asignación vigente por línea — la regla ya existente sigue en pie', () async {
      final ana = await crearEmpleado(nombre: 'Ana');
      final beto = await crearEmpleado(nombre: 'Beto');
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, ana.id);

      await expectLater(asignar(linea.id, beto.id), throwsA(anything));
    });
  });

  // ---------------------------------------------------------------
  // §7 — Auditoría distinguible
  // ---------------------------------------------------------------

  group('§7 — los tres hechos se distinguen en Auditoría central', () {
    test('baja de línea vs. cierre por baja de línea vs. cierre por baja de empleado', () async {
      final buscar = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));

      // Hecho 1 y 2: baja de una línea (evento propio) que además cierra
      // su asignación (la fila lo expresa).
      final ana = await crearEmpleado(nombre: 'Ana');
      final linea1 = await crearLinea('LIN-000001');
      await asignar(linea1.id, ana.id);
      await lineaRepo.darDeBaja(
        lineaTelefonicaId: linea1.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivoBaja: MotivoBajaLineaTelefonica.cancelacion.name,
        actorUsuarioId: actorId,
      );

      // Hecho 3: baja de un empleado, que cierra SU línea.
      final beto = await crearEmpleado(nombre: 'Beto');
      final linea2 = await crearLinea('LIN-000002');
      await asignar(linea2.id, beto.id);
      await empleadoRepo.registrarBajaLaboral(
        empleadoId: beto.id,
        fechaBaja: DateTime(2026, 7, 31),
        motivo: MotivoBajaEmpleado.renuncia.name,
        actorUsuarioId: actorId,
      );

      final acciones =
          (await buscar.ejecutar(const FiltroAuditoria(modulo: 'telefonia'))).map((e) => e.accion).toSet();

      expect(acciones, contains('dadaDeBaja'), reason: 'la línea murió: evento propio de LineaTelefonicaEvento');
      expect(acciones, contains('asignacionCerrada:bajaLinea'));
      expect(acciones, contains('asignacionCerrada:bajaEmpleado'));
      expect(
        acciones.where((a) => a.startsWith('asignacionCerrada:')),
        hasLength(2),
        reason: 'dos cierres, dos causas distintas — nunca la misma etiqueta genérica',
      );
    });

    test('el cierre automático NO emite un evento duplicado: lo expresa la propia fila', () async {
      final empleado = await crearEmpleado();
      final linea = await crearLinea('LIN-000001');
      await asignar(linea.id, empleado.id);

      await empleadoRepo.registrarBajaLaboral(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 30),
        motivo: MotivoBajaEmpleado.renuncia.name,
        actorUsuarioId: actorId,
      );

      // Cerrar una asignación no crea ningún LineaTelefonicaEvento: la
      // fila ya dice cuándo, por qué y quién.
      expect(await lineaRepo.listarEventos(linea.id), isEmpty);
    });
  });
}

/// Repositorio de asignaciones que falla exactamente en el cierre —
/// única forma de comprobar el rollback de la transacción compartida.
class _AsignacionLineaQueFalla implements AsignacionLineaTelefonicaRepository {
  @override
  Future<void> cerrarPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  }) async {
    throw StateError('fallo simulado al cerrar las líneas del empleado');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
