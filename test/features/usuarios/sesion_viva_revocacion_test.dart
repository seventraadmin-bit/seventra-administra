// Etapa 3B — cuándo deja de estar autorizada una sesión YA abierta.
//
// La auditoría 3A encontró que desactivar una cuenta borraba su
// "Recuérdame" e impedía volver a entrar, pero no tocaba la sesión que
// ya estaba abierta: esa seguía operando con los permisos del momento
// del login. Con una baja laboral eso significaba que la persona a la
// que acababan de dar de baja conservaba acceso mientras no cerrara la
// aplicación.
//
// El mecanismo es `SesionController.revalidar()`, y se dispara en cada
// navegación (desde el `redirect` del router, que ya corría y ya era
// asíncrono) y justo después de cualquier mutación de cuentas. Sin
// temporizadores, sin polling y sin que ningún widget consulte la base.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

class _SesionInicial extends SesionController {
  _SesionInicial(this._inicial);
  final SesionUsuario? _inicial;

  @override
  SesionUsuario? build() => _inicial;
}

void main() {
  late AppDatabase db;
  const hasher = PasswordHasher(iteraciones: 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<UsuarioData> cuenta({
    String usuario = 'javier',
    bool esMaestro = false,
    Set<String> permisos = const {},
  }) async {
    final fila = await db
        .into(db.usuario)
        .insertReturning(
          UsuarioCompanion.insert(
            nombre: 'JAVIER',
            nombreUsuario: usuario,
            passwordHash: hasher.hash('contrasena1'),
            esMaestro: Value(esMaestro),
          ),
        );
    for (final codigo in permisos) {
      await db.into(db.permisoUsuario).insert(PermisoUsuarioCompanion.insert(usuarioId: fila.id, codigo: codigo));
    }
    return fila;
  }

  ProviderContainer contenedorCon(SesionUsuario? sesion) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionInicial(sesion)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  SesionUsuario sesionDe(UsuarioData u, {Set<String> permisos = const {}}) => SesionUsuario(
    usuarioId: u.id,
    nombre: u.nombre,
    nombreUsuario: u.nombreUsuario,
    esMaestro: u.esMaestro,
    permisos: permisos,
  );

  group('26. Una cuenta desactivada deja de autorizar', () {
    test('revalidar mata la sesión viva de una cuenta desactivada', () async {
      final u = await cuenta(permisos: {'personal.ver'});
      final container = contenedorCon(sesionDe(u, permisos: {'personal.ver'}));
      expect(container.read(permissionServiceProvider).hasCode('personal.ver'), isTrue);

      await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
          .write(const UsuarioCompanion(cicloVidaRegistro: Value('inactivo')));
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(sesionControllerProvider), isNull, reason: 'sin sesión el redirect manda a /login');
      expect(
        container.read(permissionServiceProvider).hasCode('personal.ver'),
        isFalse,
        reason: 'deny-by-default: sin sesión no se autoriza absolutamente nada',
      );
    });

    test('un Maestro desactivado tampoco conserva su acceso total', () async {
      final u = await cuenta(usuario: 'marlon', esMaestro: true);
      final container = contenedorCon(sesionDe(u, permisos: todosLosCodigosDePermiso()));
      expect(container.read(permissionServiceProvider).esMaestroActivo, isTrue);

      await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
          .write(const UsuarioCompanion(cicloVidaRegistro: Value('inactivo')));
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(permissionServiceProvider).esMaestroActivo, isFalse);
    });

    test('una cuenta que sigue activa conserva su sesión intacta', () async {
      final u = await cuenta(permisos: {'personal.ver'});
      final container = contenedorCon(sesionDe(u, permisos: {'personal.ver'}));
      final antes = container.read(sesionControllerProvider);

      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(sesionControllerProvider), same(antes), reason: 'sin cambios no se reemplaza el estado');
    });

    test('41. sin sesión, revalidar no hace nada y todo sigue denegado', () async {
      final container = contenedorCon(null);

      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(sesionControllerProvider), isNull);
      expect(container.read(permissionServiceProvider).hasCode('personal.ver'), isFalse);
    });
  });

  group('Permisos en vivo — se conceden y se revocan sin cerrar sesión', () {
    test('un permiso CONCEDIDO llega a la sesión abierta', () async {
      final u = await cuenta(permisos: {'personal.ver'});
      final container = contenedorCon(sesionDe(u, permisos: {'personal.ver'}));
      expect(container.read(permissionServiceProvider).hasCode('nomina.ver'), isFalse);

      await db.into(db.permisoUsuario).insert(
        PermisoUsuarioCompanion.insert(usuarioId: u.id, codigo: 'nomina.ver'),
      );
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(
        container.read(permissionServiceProvider).hasCode('nomina.ver'),
        isTrue,
        reason: 'ya no hace falta cerrar sesión y volver a entrar',
      );
    });

    test('un permiso REVOCADO desaparece de la sesión abierta', () async {
      final u = await cuenta(permisos: {'personal.ver', 'nomina.ver'});
      final container = contenedorCon(sesionDe(u, permisos: {'personal.ver', 'nomina.ver'}));

      await (db.delete(db.permisoUsuario)..where((t) => t.codigo.equals('nomina.ver'))).go();
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(permissionServiceProvider).hasCode('nomina.ver'), isFalse);
      expect(container.read(permissionServiceProvider).hasCode('personal.ver'), isTrue, reason: 'sólo se quitó uno');
    });

    test('degradar un Maestro le retira el acceso total en la sesión abierta', () async {
      final u = await cuenta(usuario: 'marlon', esMaestro: true);
      final container = contenedorCon(sesionDe(u, permisos: todosLosCodigosDePermiso()));

      await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
          .write(const UsuarioCompanion(esMaestro: Value(false)));
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(permissionServiceProvider).esMaestroActivo, isFalse);
      expect(
        container.read(permissionServiceProvider).hasCode('respaldo.ver'),
        isFalse,
        reason: 'sin filas de permiso propias, degradar deja la cuenta sin nada',
      );
    });
  });

  group('17. Contraseña: quién la cambió decide qué pasa con la sesión', () {
    test('un reseteo administrativo deja la sesión existente sin poder operar', () async {
      final u = await cuenta();
      final container = contenedorCon(sesionDe(u));
      expect(container.read(sesionControllerProvider)!.debeCambiarPassword, isFalse);

      // Un administrador resetea: la contraseña la conoce alguien más.
      await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
          .write(const UsuarioCompanion(debeCambiarPassword: Value(true)));
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(
        container.read(sesionControllerProvider)!.debeCambiarPassword,
        isTrue,
        reason: 'el redirect del router no deja llegar a ninguna pantalla salvo el cambio obligatorio',
      );
    });

    test('el titular cambiando la SUYA no queda obligado ni pierde la sesión', () async {
      final u = await cuenta();
      final container = contenedorCon(sesionDe(u));

      // Así lo deja `cambiarMiContrasena`: nueva contraseña, sin obligación.
      await (db.update(db.usuario)..where((t) => t.id.equals(u.id))).write(
        UsuarioCompanion(passwordHash: Value(hasher.hash('otracontrasena')), debeCambiarPassword: const Value(false)),
      );
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(sesionControllerProvider), isNotNull);
      expect(container.read(sesionControllerProvider)!.debeCambiarPassword, isFalse);
    });
  });

  group('Fail closed', () {
    test('una sesión cuya cuenta ya no está en la base deja de ser válida', () async {
      final u = await cuenta(permisos: {'personal.ver'});
      final container = contenedorCon(sesionDe(u, permisos: {'personal.ver'}));

      // RISEG ONE no borra Usuarios; esto lo produciría restaurar un
      // respaldo de otra instalación. Que sea raro no lo vuelve seguro:
      // una identidad que no se puede comprobar no conserva acceso.
      await (db.delete(db.usuario)..where((t) => t.id.equals(u.id))).go();
      await container.read(sesionControllerProvider.notifier).revalidar();

      expect(container.read(sesionControllerProvider), isNull);
      expect(container.read(permissionServiceProvider).hasCode('personal.ver'), isFalse);
    });
  });
}
