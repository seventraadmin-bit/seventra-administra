import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/activar_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/corregir_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_primer_maestro_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/desactivar_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/login_usecase.dart';

void main() {
  late AppDatabase db;
  late UsuarioRepositoryImpl usuarioRepo;
  late PasswordHasher hasher;
  late CrearPrimerMaestroUseCase crearPrimerMaestro;
  late LoginUseCase login;
  late CrearUsuarioUseCase crearUsuario;
  late CorregirUsuarioUseCase corregirUsuario;
  late CambiarContrasenaUsuarioUseCase cambiarContrasena;
  late ActivarUsuarioUseCase activarUsuario;
  late DesactivarUsuarioUseCase desactivarUsuario;
  late PuestoRepositoryImpl puestoRepo;
  late CrearPuestoUseCase crearPuesto;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    usuarioRepo = UsuarioRepositoryImpl(db);
    // Iteraciones bajas — la seguridad real (100000) ya está cubierta
    // por `password_hasher_test.dart`, aquí solo importa el flujo.
    hasher = const PasswordHasher(iteraciones: 1000);
    crearPrimerMaestro = CrearPrimerMaestroUseCase(usuarioRepo, hasher);
    login = LoginUseCase(usuarioRepo, hasher);

    puestoRepo = PuestoRepositoryImpl(db);
    crearPuesto = CrearPuestoUseCase(
      puestoRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
    crearUsuario = CrearUsuarioUseCase(usuarioRepo, puestoRepo, hasher);
    corregirUsuario = CorregirUsuarioUseCase(usuarioRepo, puestoRepo);
    cambiarContrasena = CambiarContrasenaUsuarioUseCase(usuarioRepo, hasher);
    activarUsuario = ActivarUsuarioUseCase(usuarioRepo);
    desactivarUsuario = DesactivarUsuarioUseCase(usuarioRepo);
  });

  tearDown(() => db.close());

  Future<PuestoData> crearPuestoFixture({String nombre = 'Recursos Humanos'}) async {
    final resultado = await crearPuesto.ejecutar(
      PuestoBorrador(nombre: nombre, areaId: SeedIds.areaOperaciones, tipo: TipoPuesto.administrativo, nivelJerarquico: 1),
    );
    return (resultado as GuardarPuestoExitoso).puesto;
  }

  group('CrearPrimerMaestroUseCase — bootstrap', () {
    test('crea el primer Maestro cuando la base no tiene usuarios', () async {
      final resultado = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana Torres',
        nombreUsuario: 'ana.torres',
        password: 'Sup3rSecreta!',
        confirmarPassword: 'Sup3rSecreta!',
      );

      expect(resultado, isA<CrearPrimerMaestroExitoso>());
      final usuario = (resultado as CrearPrimerMaestroExitoso).usuario;
      expect(usuario.esMaestro, isTrue);
      expect(usuario.cicloVidaRegistro, 'activo');
      expect(usuario.puestoId, isNull);

      final eventos = await usuarioRepo.listarEventos(usuario.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'creado');
      expect(eventos.single.actorUsuarioId, isNull);
    });

    test('rechaza crear un segundo Maestro por bootstrap si ya existe un usuario', () async {
      await crearPrimerMaestro.ejecutar(
        nombre: 'Ana Torres',
        nombreUsuario: 'ana.torres',
        password: 'Sup3rSecreta!',
        confirmarPassword: 'Sup3rSecreta!',
      );

      final segundo = await crearPrimerMaestro.ejecutar(
        nombre: 'Otro',
        nombreUsuario: 'otro',
        password: 'Sup3rSecreta!',
        confirmarPassword: 'Sup3rSecreta!',
      );

      expect(segundo, isA<CrearPrimerMaestroYaExisteUnUsuario>());
      expect(await usuarioRepo.contarUsuarios(), 1);
    });

    test('rechaza contraseñas que no coinciden y contraseña demasiado corta', () async {
      final noCoinciden = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'abcdefgh', confirmarPassword: 'distinta1',
      );
      expect(noCoinciden, isA<CrearPrimerMaestroContrasenasNoCoinciden>());

      final corta = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'abc', confirmarPassword: 'abc',
      );
      expect(corta, isA<CrearPrimerMaestroContrasenaInvalida>());

      expect(await usuarioRepo.contarUsuarios(), 0);
    });
  });

  group('LoginUseCase', () {
    test('login correcto actualiza último acceso y arma la sesión', () async {
      await crearPrimerMaestro.ejecutar(
        nombre: 'Ana Torres', nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );

      final resultado = await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!');

      expect(resultado, isA<LoginExitoso>());
      final sesion = (resultado as LoginExitoso).sesion;
      expect(sesion.nombreUsuario, 'ana.torres');
      expect(sesion.esMaestro, isTrue);

      final usuario = await usuarioRepo.obtenerPorNombreUsuario('ana.torres');
      expect(usuario!.ultimoAccesoAt, isNotNull);
    });

    test('rechaza contraseña incorrecta', () async {
      await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final resultado = await login.ejecutar(nombreUsuario: 'ana', password: 'incorrecta');
      expect(resultado, isA<LoginCredencialesInvalidas>());
    });

    test('rechaza un usuario que no existe con el mismo mensaje genérico que una contraseña incorrecta', () async {
      final resultado = await login.ejecutar(nombreUsuario: 'no-existe', password: 'lo-que-sea');
      expect(resultado, isA<LoginCredencialesInvalidas>());
    });

    test('bloquea a un usuario inactivo (solo tras contraseña correcta)', () async {
      final maestro = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final puesto = await crearPuestoFixture();
      final creado = await crearUsuario.ejecutar(
        nombre: 'Bruno', nombreUsuario: 'bruno', password: 'OtraSecreta1', puestoId: puesto.id,
        actorUsuarioId: (maestro as CrearPrimerMaestroExitoso).usuario.id,
      );
      final usuario = (creado as CrearUsuarioExitoso).usuario;
      await desactivarUsuario.ejecutar(usuarioId: usuario.id, actorUsuarioId: maestro.usuario.id);

      final resultado = await login.ejecutar(nombreUsuario: 'bruno', password: 'OtraSecreta1');
      expect(resultado, isA<LoginUsuarioInactivo>());
    });

    test('reingreso tras cambiar la contraseña exige la nueva contraseña', () async {
      await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final usuario = await usuarioRepo.obtenerPorNombreUsuario('ana');
      await cambiarContrasena.ejecutar(usuarioId: usuario!.id, password: 'NuevaClave1');

      final conVieja = await login.ejecutar(nombreUsuario: 'ana', password: 'Sup3rSecreta!');
      expect(conVieja, isA<LoginCredencialesInvalidas>());

      final conNueva = await login.ejecutar(nombreUsuario: 'ana', password: 'NuevaClave1');
      expect(conNueva, isA<LoginExitoso>());
    });
  });

  group('CrearUsuarioUseCase', () {
    test('hash de la contraseña nunca queda en texto plano en la fila', () async {
      final puesto = await crearPuestoFixture();
      final resultado = await crearUsuario.ejecutar(
        nombre: 'Bruno', nombreUsuario: 'bruno', password: 'ClaveSegura1', puestoId: puesto.id,
      );
      final usuario = (resultado as CrearUsuarioExitoso).usuario;
      expect(usuario.passwordHash.contains('ClaveSegura1'), isFalse);
      expect(usuario.passwordHash.startsWith('pbkdf2\$'), isTrue);
    });

    test('rechaza nombre de usuario duplicado', () async {
      final puesto = await crearPuestoFixture();
      await crearUsuario.ejecutar(nombre: 'Bruno', nombreUsuario: 'bruno', password: 'ClaveSegura1', puestoId: puesto.id);

      final segundo = await crearUsuario.ejecutar(
        nombre: 'Bruno Otro', nombreUsuario: 'bruno', password: 'OtraClave1', puestoId: puesto.id,
      );
      expect(segundo, isA<CrearUsuarioNombreUsuarioDuplicado>());
      expect(await usuarioRepo.contarUsuarios(), 1);
    });

    test('rechaza Puesto inexistente', () async {
      final resultado = await crearUsuario.ejecutar(
        nombre: 'Bruno', nombreUsuario: 'bruno', password: 'ClaveSegura1', puestoId: 'no-existe',
      );
      expect(resultado, isA<CrearUsuarioPuestoInvalido>());
    });

    test('rechaza contraseña demasiado corta', () async {
      final puesto = await crearPuestoFixture();
      final resultado = await crearUsuario.ejecutar(
        nombre: 'Bruno', nombreUsuario: 'bruno', password: '123', puestoId: puesto.id,
      );
      expect(resultado, isA<CrearUsuarioContrasenaInvalida>());
    });

    test('un segundo Usuario con el mismo Puesto puede tener esMaestro distinto (Puesto nunca determina permisos)', () async {
      final puesto = await crearPuestoFixture();
      final r1 = await crearUsuario.ejecutar(
        nombre: 'María López', nombreUsuario: 'maria', password: 'ClaveSegura1', puestoId: puesto.id, esMaestro: false,
      );
      final r2 = await crearUsuario.ejecutar(
        nombre: 'Otro con mismo puesto', nombreUsuario: 'otro', password: 'ClaveSegura1', puestoId: puesto.id, esMaestro: true,
      );
      expect((r1 as CrearUsuarioExitoso).usuario.esMaestro, isFalse);
      expect((r2 as CrearUsuarioExitoso).usuario.esMaestro, isTrue);
    });
  });

  group('Invariante: al menos un Maestro activo', () {
    test('no se puede desactivar al último Maestro activo', () async {
      final maestro = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final usuario = (maestro as CrearPrimerMaestroExitoso).usuario;

      final resultado = await desactivarUsuario.ejecutar(usuarioId: usuario.id);
      expect(resultado, isA<DesactivarUsuarioBloqueadaPorUltimoMaestro>());

      final actual = await usuarioRepo.obtenerPorId(usuario.id);
      expect(actual!.cicloVidaRegistro, 'activo');
    });

    test('sí se puede desactivar a un Maestro si hay otro Maestro activo', () async {
      final primero = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final usuario1 = (primero as CrearPrimerMaestroExitoso).usuario;
      final puesto = await crearPuestoFixture();
      final segundoResultado = await crearUsuario.ejecutar(
        nombre: 'Beto', nombreUsuario: 'beto', password: 'ClaveSegura1', puestoId: puesto.id, esMaestro: true,
      );
      final usuario2 = (segundoResultado as CrearUsuarioExitoso).usuario;

      final resultado = await desactivarUsuario.ejecutar(usuarioId: usuario1.id, actorUsuarioId: usuario2.id);
      expect(resultado, isA<DesactivarUsuarioExitoso>());
    });

    test('no se puede quitar esMaestro al último Maestro activo vía corrección', () async {
      final maestro = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final usuario = (maestro as CrearPrimerMaestroExitoso).usuario;

      final resultado = await corregirUsuario.ejecutar(usuarioId: usuario.id, esMaestro: false);
      expect(resultado, isA<CorregirUsuarioBloqueadaPorUltimoMaestro>());

      final actual = await usuarioRepo.obtenerPorId(usuario.id);
      expect(actual!.esMaestro, isTrue);
    });

    test('activar un Maestro inactivo no está bloqueado por la invariante (solo desactivar/quitar lo está)', () async {
      final primero = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final usuario1 = (primero as CrearPrimerMaestroExitoso).usuario;
      final puesto = await crearPuestoFixture();
      final segundoResultado = await crearUsuario.ejecutar(
        nombre: 'Beto', nombreUsuario: 'beto', password: 'ClaveSegura1', puestoId: puesto.id, esMaestro: true,
      );
      final usuario2 = (segundoResultado as CrearUsuarioExitoso).usuario;
      await desactivarUsuario.ejecutar(usuarioId: usuario2.id, actorUsuarioId: usuario1.id);

      final resultado = await activarUsuario.ejecutar(usuarioId: usuario2.id, actorUsuarioId: usuario1.id);
      expect(resultado, isA<ActivarUsuarioExitoso>());
    });
  });

  group('Auditoría del propio Usuario', () {
    test('cada acción administrativa queda registrada con el actor correcto en UsuarioEvento', () async {
      final maestro = await crearPrimerMaestro.ejecutar(
        nombre: 'Ana', nombreUsuario: 'ana', password: 'Sup3rSecreta!', confirmarPassword: 'Sup3rSecreta!',
      );
      final actorId = (maestro as CrearPrimerMaestroExitoso).usuario.id;
      final puesto = await crearPuestoFixture();

      final creado = await crearUsuario.ejecutar(
        nombre: 'Bruno', nombreUsuario: 'bruno', password: 'ClaveSegura1', puestoId: puesto.id, actorUsuarioId: actorId,
      );
      final usuario = (creado as CrearUsuarioExitoso).usuario;
      await corregirUsuario.ejecutar(usuarioId: usuario.id, nombre: 'Bruno Actualizado', actorUsuarioId: actorId);
      await cambiarContrasena.ejecutar(usuarioId: usuario.id, password: 'OtraClaveNueva1', actorUsuarioId: actorId);
      await desactivarUsuario.ejecutar(usuarioId: usuario.id, actorUsuarioId: actorId, motivo: 'Prueba');
      await activarUsuario.ejecutar(usuarioId: usuario.id, actorUsuarioId: actorId);

      final eventos = await usuarioRepo.listarEventos(usuario.id);
      expect(eventos.map((e) => e.tipoEvento).toList(), [
        'creado',
        'datosCorregidos',
        'contrasenaCambiada',
        'desactivado',
        'activado',
      ]);
      expect(eventos.every((e) => e.actorUsuarioId == actorId), isTrue);
      expect(eventos.firstWhere((e) => e.tipoEvento == 'desactivado').observacion, 'Prueba');
    });
  });
}
