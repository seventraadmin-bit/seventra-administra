// Etapa 3B — la baja laboral cierra el acceso.
//
// Este es el P1 operativo que encontró la auditoría 3A: **nada** en el
// proyecto conectaba dar de baja a una persona con retirarle la cuenta.
// Quien se iba conservaba acceso a RISEG ONE hasta que alguien se
// acordara de desactivarlo a mano. Con dos cuentas eso se gestiona de
// memoria; con veinte, no.
//
// Lo que se fija aquí: la desactivación ocurre, ocurre ATÓMICAMENTE con
// la baja, conserva al Usuario y su vínculo, conserva al actor humano, y
// no puede dejar al sistema sin Maestro.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_reingreso_usecase.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/activar_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';

void main() {
  late AppDatabase db;
  late UsuarioRepositoryImpl usuarioRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late CrearUsuarioUseCase crearUsuario;
  late RegistrarBajaLaboralUseCase registrarBaja;
  late RegistrarReingresoUseCase registrarReingreso;
  late ActivarUsuarioUseCase activarUsuario;
  const hasher = PasswordHasher(iteraciones: 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    usuarioRepo = UsuarioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    crearUsuario = CrearUsuarioUseCase(usuarioRepo, PuestoRepositoryImpl(db), hasher, empleadoRepo);
    registrarBaja = RegistrarBajaLaboralUseCase(
      empleadoRepo,
      const EmpleadoValidator(),
      AsignacionRepositoryImpl(db),
      AsignacionVehiculoRepositoryImpl(db),
      usuarioRepository: usuarioRepo,
    );
    registrarReingreso = RegistrarReingresoUseCase(empleadoRepo, const EmpleadoValidator());
    activarUsuario = ActivarUsuarioUseCase(usuarioRepo);
  });

  tearDown(() => db.close());

  Future<String> empleadoFixture({int numero = 1, String nombres = 'JUAN'}) async {
    final fila = await db
        .into(db.empleado)
        .insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: nombres,
            apellidoPaterno: 'PEREZ',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXX$numero',
            rfc: 'PEXJ900101A$numero',
            nss: '123456789$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    return fila.id;
  }

  Future<String> cuentaDe(String empleadoId, {String usuario = 'jperez', bool esMaestro = false}) async {
    final r = await crearUsuario.ejecutar(
      nombre: 'IGNORADO',
      nombreUsuario: usuario,
      password: 'contrasena1',
      empleadoId: empleadoId,
      esMaestro: esMaestro,
    );
    return (r as CrearUsuarioExitoso).usuario.id;
  }

  Future<RegistrarBajaLaboralResultado> darDeBaja(String empleadoId, {String? actor}) {
    return registrarBaja.ejecutar(
      empleadoId: empleadoId,
      fechaBaja: DateTime(2026, 6, 30),
      motivo: MotivoBajaEmpleado.renuncia,
      actorUsuarioId: actor,
    );
  }

  group('La baja laboral cierra el acceso', () {
    test('22. dar de baja a un empleado vinculado desactiva su cuenta', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId);

      final r = await darDeBaja(empleadoId);

      expect(r, isA<RegistrarBajaLaboralExitoso>());
      final cuenta = await usuarioRepo.obtenerPorId(usuarioId);
      expect(cuenta!.cicloVidaRegistro, 'inactivo');
    });

    test('23 y 24. la cuenta NO se elimina y conserva su vínculo', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId);

      await darDeBaja(empleadoId);

      final cuenta = await usuarioRepo.obtenerPorId(usuarioId);
      expect(cuenta, isNotNull, reason: 'la identidad histórica de la auditoría cuelga de esta fila');
      expect(cuenta!.empleadoId, empleadoId, reason: 'el vínculo se conserva: la cuenta sigue siendo de esa persona');
      // Y el historial de la cuenta conserva ambos hechos.
      final eventos = await usuarioRepo.listarEventos(usuarioId);
      expect(eventos.map((e) => e.tipoEvento), contains('desactivado'));
    });

    test('25. la sesión persistente de esa cuenta queda invalidada', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId);
      await usuarioRepo.crearSesionPersistente(usuarioId: usuarioId, tokenHash: 'hash-de-prueba');
      expect(await db.select(db.sesionPersistente).get(), hasLength(1));

      await darDeBaja(empleadoId);

      expect(
        await db.select(db.sesionPersistente).get(),
        isEmpty,
        reason: '"Recuérdame" no puede sobrevivir a la baja de quien lo activó',
      );
    });

    test('27. la desactivación conserva al actor HUMANO que confirmó la baja', () async {
      final maestroEmpleado = await empleadoFixture(numero: 9, nombres: 'MARLON');
      final maestroId = await cuentaDe(maestroEmpleado, usuario: 'marlon', esMaestro: true);
      final empleadoId = await empleadoFixture(numero: 2, nombres: 'JAVIER');
      final usuarioId = await cuentaDe(empleadoId, usuario: 'javier');

      await darDeBaja(empleadoId, actor: maestroId);

      final desactivado = (await usuarioRepo.listarEventos(usuarioId)).lastWhere((e) => e.tipoEvento == 'desactivado');
      expect(
        desactivado.actorUsuarioId,
        maestroId,
        reason: 'la desactivación es consecuencia de una decisión humana, no de un "Sistema" inventado',
      );
    });

    test('29. dar de baja a alguien SIN cuenta no toca nada de Usuarios', () async {
      final otroEmpleado = await empleadoFixture(numero: 5, nombres: 'ANA');
      final conCuenta = await cuentaDe(otroEmpleado, usuario: 'ana');
      final sinCuenta = await empleadoFixture(numero: 6, nombres: 'LUIS');

      await darDeBaja(sinCuenta);

      final cuenta = await usuarioRepo.obtenerPorId(conCuenta);
      expect(cuenta!.cicloVidaRegistro, 'activo', reason: 'la baja de otra persona no puede rozar esta cuenta');
    });

    test('38 y 39. tras la baja la cuenta queda DESACTIVADA', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId, usuario: 'jperez');

      await darDeBaja(empleadoId);

      // IF-5 — antes esto se comprobaba intentando un login local, que ya no
      // existe. El HECHO que importa es el mismo y sigue siendo local: la baja
      // laboral desactiva la cuenta en la misma transacción. Quién puede entrar
      // lo decide ahora el backend, y esta prueba no puede ni debe afirmarlo.
      final cuenta = await usuarioRepo.obtenerPorId(usuarioId);
      expect(cuenta!.cicloVidaRegistro, isNot('activo'));
    });
  });

  group('Atomicidad', () {
    test('si la baja se rechaza, la cuenta NO queda desactivada', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId);
      // Fecha de baja anterior al ingreso: el dominio la rechaza.
      final r = await registrarBaja.ejecutar(
        empleadoId: empleadoId,
        fechaBaja: DateTime(2020, 1, 1),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(r, isA<RegistrarBajaLaboralFechaInvalida>());
      final cuenta = await usuarioRepo.obtenerPorId(usuarioId);
      expect(
        cuenta!.cicloVidaRegistro,
        'activo',
        reason: 'no puede existir "cuenta cerrada sin baja" igual que no puede existir "baja con cuenta abierta"',
      );
    });
  });

  group('El último Maestro no puede quedar fuera por una baja', () {
    test('28. la baja se bloquea ENTERA si esa cuenta es el único Maestro activo', () async {
      final empleadoId = await empleadoFixture(nombres: 'MARLON');
      final usuarioId = await cuentaDe(empleadoId, usuario: 'marlon', esMaestro: true);

      final r = await darDeBaja(empleadoId);

      expect(r, isA<RegistrarBajaLaboralBloqueadaPorUltimoMaestro>());
      expect((r as RegistrarBajaLaboralBloqueadaPorUltimoMaestro).nombreUsuario, 'marlon');

      // Ni la baja ni la desactivación se escribieron.
      final empleado = await empleadoRepo.obtenerPorId(empleadoId);
      expect(empleado!.estatus, 'activo', reason: 'la baja no se ejecuta a medias');
      final cuenta = await usuarioRepo.obtenerPorId(usuarioId);
      expect(cuenta!.cicloVidaRegistro, 'activo');
    });

    test('con OTRO Maestro activo, la misma baja procede', () async {
      final otroEmpleado = await empleadoFixture(numero: 3, nombres: 'SEGUNDO');
      await cuentaDe(otroEmpleado, usuario: 'segundo', esMaestro: true);
      final empleadoId = await empleadoFixture(nombres: 'MARLON');
      final usuarioId = await cuentaDe(empleadoId, usuario: 'marlon', esMaestro: true);

      final r = await darDeBaja(empleadoId);

      expect(r, isA<RegistrarBajaLaboralExitoso>());
      expect((await usuarioRepo.obtenerPorId(usuarioId))!.cicloVidaRegistro, 'inactivo');
      expect(await usuarioRepo.contarMaestrosActivos(), 1, reason: 'el sistema nunca se quedó sin Maestro');
    });
  });

  group('Reingreso: la misma persona, la misma cuenta', () {
    test('30. el reingreso reutiliza el mismo Empleado, no crea otro', () async {
      final empleadoId = await empleadoFixture();
      await cuentaDe(empleadoId);
      await darDeBaja(empleadoId);

      await registrarReingreso.ejecutar(empleadoId: empleadoId, fechaIngreso: DateTime(2026, 9, 1));

      expect(await db.select(db.empleado).get(), hasLength(1));
      expect((await empleadoRepo.obtenerPorId(empleadoId))!.estatus, 'activo');
    });

    test('32. mientras el empleado siga de baja, la cuenta NO puede reactivarse', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId);
      await darDeBaja(empleadoId);

      final r = await activarUsuario.ejecutar(usuarioId: usuarioId);

      expect(r, isA<ActivarUsuarioEmpleadoDeBaja>());
      expect((await usuarioRepo.obtenerPorId(usuarioId))!.cicloVidaRegistro, 'inactivo');
    });

    test('31. tras el reingreso, la MISMA cuenta se reactiva — nunca se crea una segunda', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaDe(empleadoId);
      await darDeBaja(empleadoId);
      await registrarReingreso.ejecutar(empleadoId: empleadoId, fechaIngreso: DateTime(2026, 9, 1));

      final r = await activarUsuario.ejecutar(usuarioId: usuarioId);

      expect(r, isA<ActivarUsuarioExitoso>());
      expect(await db.select(db.usuario).get(), hasLength(1), reason: 'la identidad histórica vive en ESTA cuenta');
      final cuenta = await usuarioRepo.obtenerPorId(usuarioId);
      expect(cuenta!.empleadoId, empleadoId);
      // Y el historial completo del ciclo sigue ahí.
      final tipos = (await usuarioRepo.listarEventos(usuarioId)).map((e) => e.tipoEvento).toList();
      expect(tipos, containsAllInOrder(['creado', 'desactivado', 'activado']));
    });

    test('una cuenta INDEPENDIENTE se reactiva sin depender de ningún estado laboral', () async {
      final r0 = await crearUsuario.ejecutar(
        nombre: 'ADMINISTRADOR',
        nombreUsuario: 'admin',
        password: 'contrasena1',
        puestoId: null,
        empleadoId: null,
      );
      // Sin puesto válido el alta se rechaza: se crea con uno real.
      expect(r0, isA<CrearUsuarioPuestoInvalido>());

      final usuario = await db
          .into(db.usuario)
          .insertReturning(
            UsuarioCompanion.insert(
              nombre: 'ADMINISTRADOR',
              nombreUsuario: 'admin',
              passwordHash: hasher.hash('contrasena1'),
              cicloVidaRegistro: const Value('inactivo'),
            ),
          );

      final r = await activarUsuario.ejecutar(usuarioId: usuario.id);
      expect(r, isA<ActivarUsuarioExitoso>());
    });
  });
}
