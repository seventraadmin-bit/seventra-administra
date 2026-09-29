import 'package:drift/drift.dart' show Value;
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
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/activar_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/corregir_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/desactivar_usuario_usecase.dart';

void main() {
  late AppDatabase db;
  late UsuarioRepositoryImpl usuarioRepo;
  late PasswordHasher hasher;
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

    puestoRepo = PuestoRepositoryImpl(db);
    crearPuesto = CrearPuestoUseCase(
      puestoRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
    final empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    crearUsuario = CrearUsuarioUseCase(usuarioRepo, puestoRepo, hasher, empleadoRepo);
    corregirUsuario = CorregirUsuarioUseCase(usuarioRepo, puestoRepo);
    cambiarContrasena = CambiarContrasenaUsuarioUseCase(usuarioRepo, hasher);
    activarUsuario = ActivarUsuarioUseCase(usuarioRepo);
    desactivarUsuario = DesactivarUsuarioUseCase(usuarioRepo);
  });

  tearDown(() => db.close());

  /// IF-5 — el Maestro se siembra directo, sin pasar por el bootstrap local que
  /// se retiró. Lo que estas pruebas necesitan es la FILA, no el camino por el
  /// que nacía: el alta del primer Maestro es hoy del aprovisionamiento SaaS.
  Future<UsuarioData> maestroFixture({required String nombre, required String nombreUsuario}) async {
    final id = 'maestro-';
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: Value(id),
            nombre: nombre,
            nombreUsuario: nombreUsuario,
            passwordHash: 'sin-contrasena-en-pruebas',
            esMaestro: const Value(true),
          ),
        );
    return (await usuarioRepo.obtenerPorId(id))!;
  }

  Future<PuestoData> crearPuestoFixture({String nombre = 'Recursos Humanos'}) async {
    final resultado = await crearPuesto.ejecutar(
      PuestoBorrador(nombre: nombre, areaId: SeedIds.areaOperaciones, tipo: TipoPuesto.administrativo, nivelJerarquico: 1),
    );
    return (resultado as GuardarPuestoExitoso).puesto;
  }

  // IF-5 — los grupos «CrearPrimerMaestroUseCase — bootstrap» y «LoginUseCase»
  // se retiraron con la autenticación local: el primer Maestro lo da de alta el
  // aprovisionamiento de plataforma y el inicio de sesión lo resuelve el backend
  // SaaS. Lo que sigue aquí —alta, baja, invariante de Maestro activo y
  // auditoría de la propia cuenta— es administración de cuentas y SOBREVIVE.

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

  group('DesactivarUsuarioUseCase — motivo obligatorio', () {
    test('rechaza motivo vacío sin tocar el Usuario', () async {
      final maestro = await maestroFixture(nombre: 'Ana', nombreUsuario: 'ana');
      final puesto = await crearPuestoFixture();
      final creado = await crearUsuario.ejecutar(
        nombre: 'Bruno', nombreUsuario: 'bruno', password: 'ClaveSegura1', puestoId: puesto.id,
        actorUsuarioId: maestro.id,
      );
      final usuario = (creado as CrearUsuarioExitoso).usuario;

      final resultado = await desactivarUsuario.ejecutar(usuarioId: usuario.id, motivo: '   ');
      expect(resultado, isA<DesactivarUsuarioMotivoRequerido>());

      final actual = await usuarioRepo.obtenerPorId(usuario.id);
      expect(actual!.cicloVidaRegistro, 'activo');
    });
  });

  group('Invariante: al menos un Maestro activo', () {
    test('no se puede desactivar al último Maestro activo', () async {
      final maestro = await maestroFixture(nombre: 'Ana', nombreUsuario: 'ana');
      final usuario = maestro;

      final resultado = await desactivarUsuario.ejecutar(usuarioId: usuario.id, motivo: 'Prueba');
      expect(resultado, isA<DesactivarUsuarioBloqueadaPorUltimoMaestro>());

      final actual = await usuarioRepo.obtenerPorId(usuario.id);
      expect(actual!.cicloVidaRegistro, 'activo');
    });

    test('sí se puede desactivar a un Maestro si hay otro Maestro activo', () async {
      final primero = await maestroFixture(nombre: 'Ana', nombreUsuario: 'ana');
      final usuario1 = primero;
      final puesto = await crearPuestoFixture();
      final segundoResultado = await crearUsuario.ejecutar(
        nombre: 'Beto', nombreUsuario: 'beto', password: 'ClaveSegura1', puestoId: puesto.id, esMaestro: true,
      );
      final usuario2 = (segundoResultado as CrearUsuarioExitoso).usuario;

      final resultado =
          await desactivarUsuario.ejecutar(usuarioId: usuario1.id, actorUsuarioId: usuario2.id, motivo: 'Prueba');
      expect(resultado, isA<DesactivarUsuarioExitoso>());
    });

    test('no se puede quitar esMaestro al último Maestro activo vía corrección', () async {
      final maestro = await maestroFixture(nombre: 'Ana', nombreUsuario: 'ana');
      final usuario = maestro;

      final resultado = await corregirUsuario.ejecutar(usuarioId: usuario.id, esMaestro: false);
      expect(resultado, isA<CorregirUsuarioBloqueadaPorUltimoMaestro>());

      final actual = await usuarioRepo.obtenerPorId(usuario.id);
      expect(actual!.esMaestro, isTrue);
    });

    test('activar un Maestro inactivo no está bloqueado por la invariante (solo desactivar/quitar lo está)', () async {
      final primero = await maestroFixture(nombre: 'Ana', nombreUsuario: 'ana');
      final usuario1 = primero;
      final puesto = await crearPuestoFixture();
      final segundoResultado = await crearUsuario.ejecutar(
        nombre: 'Beto', nombreUsuario: 'beto', password: 'ClaveSegura1', puestoId: puesto.id, esMaestro: true,
      );
      final usuario2 = (segundoResultado as CrearUsuarioExitoso).usuario;
      await desactivarUsuario.ejecutar(usuarioId: usuario2.id, actorUsuarioId: usuario1.id, motivo: 'Prueba');

      final resultado = await activarUsuario.ejecutar(usuarioId: usuario2.id, actorUsuarioId: usuario1.id);
      expect(resultado, isA<ActivarUsuarioExitoso>());
    });
  });

  group('Auditoría del propio Usuario', () {
    test('cada acción administrativa queda registrada con el actor correcto en UsuarioEvento', () async {
      final maestro = await maestroFixture(nombre: 'Ana', nombreUsuario: 'ana');
      final actorId = maestro.id;
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
