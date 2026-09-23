// Etapa "Usuarios, permisos y UX de seguridad" — cambio obligatorio de
// contraseña, y el gate de rutas del router.
//
// Regla: una contraseña temporal (la del alta, o la de un reseteo
// administrativo) la conoce alguien más que su titular. Mientras siga
// vigente, la sesión existe pero NO opera: el `redirect` del router
// manda todo a `/cambiar-contrasena` antes de construir ninguna
// pantalla, exactamente como hace con los permisos.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/login_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/usuarios_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

class _SesionFija extends SesionController {
  _SesionFija(this._inicial);
  final SesionUsuario? _inicial;

  @override
  SesionUsuario? build() => _inicial;
}

void main() {
  late AppDatabase db;
  const hasher = PasswordHasher();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Un Maestro que actúa como administrador, ya sin obligación.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: hasher.hash('contrasenaMaestro1'),
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<String> crearCuentaConTemporal({String nombreUsuario = 'javier'}) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(
          () => _SesionFija(
            const SesionUsuario(
              usuarioId: 'maestro',
              nombre: 'MARLON',
              nombreUsuario: 'marlon',
              esMaestro: true,
              permisos: {},
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    var puestos = await db.select(db.puesto).get();
    if (puestos.isEmpty) {
      await db.into(db.puesto).insert(
            PuestoCompanion.insert(
              codigo: 'PUE-OPE',
              nombre: 'Guardia',
              areaId: (await db.select(db.area).get()).first.id,
              tipo: 'operativo',
              nivelJerarquico: 1,
            ),
          );
      puestos = await db.select(db.puesto).get();
    }

    await container.read(usuariosControllerProvider.notifier).crear(
          nombre: 'JAVIER RIOS',
          nombreUsuario: nombreUsuario,
          password: 'temporalDelAlta1',
          puestoId: puestos.first.id,
          permisosIniciales: {'personal.ver'},
        );

    final creado = await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals(nombreUsuario))).getSingle();
    return creado.id;
  }

  group('El alta deja obligación de cambio, y el login la trae a la sesión', () {
    test('una cuenta recién creada nace con debeCambiarPassword', () async {
      final id = await crearCuentaConTemporal();
      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(id))).getSingle();
      expect(fila.debeCambiarPassword, isTrue);
    });

    test('el login trae la obligación en la SesionUsuario', () async {
      await crearCuentaConTemporal();
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final resultado = await container.read(loginUseCaseProvider).ejecutar(
            nombreUsuario: 'javier',
            password: 'temporalDelAlta1',
          );

      expect(resultado, isA<LoginExitoso>());
      expect((resultado as LoginExitoso).sesion.debeCambiarPassword, isTrue);
    });

    test('cambiar la propia contraseña apaga la obligación, en BD y en la sesión viva', () async {
      final id = await crearCuentaConTemporal();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(
            () => _SesionFija(
              SesionUsuario(
                usuarioId: id,
                nombre: 'JAVIER RIOS',
                nombreUsuario: 'javier',
                esMaestro: false,
                permisos: const {'personal.ver'},
                debeCambiarPassword: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cambiarMiContrasenaProvider)('contrasenaPropia9');

      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(id))).getSingle();
      expect(fila.debeCambiarPassword, isFalse, reason: 'el titular cumplió el requisito');
      expect(
        container.read(sesionControllerProvider)!.debeCambiarPassword,
        isFalse,
        reason: 'no se le exige volver a iniciar sesión para poder operar',
      );
    });

    test('un reseteo administrativo VUELVE a exigir el cambio', () async {
      final id = await crearCuentaConTemporal();
      // Primero el titular la cambia: queda sin obligación.
      await db.into(db.usuario).insertOnConflictUpdate(
            (await (db.select(db.usuario)..where((t) => t.id.equals(id))).getSingle())
                .copyWith(debeCambiarPassword: false),
          );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(
            () => _SesionFija(
              const SesionUsuario(
                usuarioId: 'maestro',
                nombre: 'MARLON',
                nombreUsuario: 'marlon',
                esMaestro: true,
                permisos: {},
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(usuariosControllerProvider.notifier).cambiarContrasena(
            usuarioId: id,
            password: 'reseteadaPorMaestro1',
          );

      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(id))).getSingle();
      expect(
        fila.debeCambiarPassword,
        isTrue,
        reason: 'la contraseña vigente la conoce el Maestro que la fijó: no puede quedarse así',
      );
    });
  });

  group('El redirect del router es el candado', () {
    Future<GoRouter> montarConSesion(WidgetTester tester, SesionUsuario sesion) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = createAppRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('con la obligación vigente NO se construye ninguna pantalla del sistema', (tester) async {
      final id = await crearCuentaConTemporal();
      await montarConSesion(
        tester,
        SesionUsuario(
          usuarioId: id,
          nombre: 'JAVIER RIOS',
          nombreUsuario: 'javier',
          esMaestro: false,
          permisos: const {'personal.ver'},
          debeCambiarPassword: true,
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.cambioObligatorioTitulo), findsOneWidget);
      // Ni Shell, ni sidebar, ni barra superior: el `redirect` corre
      // antes de construirlos.
      expect(find.byKey(const Key('app_top_bar')), findsNothing);
      expect(tester.takeException(), isNull);

      // Y hay salida: nunca se deja a alguien atrapado.
      expect(find.byKey(const Key('cambio_obligatorio_cerrar_sesion')), findsOneWidget);
    });

    testWidgets('sin la obligación, /cambiar-contrasena no es alcanzable', (tester) async {
      final id = await crearCuentaConTemporal();
      // El titular YA cumplió el cambio: la cuenta deja de arrastrar
      // contraseña temporal.
      //
      // Etapa 3B — antes bastaba con inyectar una sesión que dijera
      // `debeCambiarPassword: false` sobre una cuenta que en la base
      // seguía obligada, y la prueba pasaba. Esa divergencia entre lo
      // que la sesión cree y lo que la cuenta es fue justo lo que
      // `SesionController.revalidar()` vino a cerrar, así que ahora la
      // base tiene que decir lo mismo que la sesión.
      await (db.update(db.usuario)..where((t) => t.id.equals(id)))
          .write(const UsuarioCompanion(debeCambiarPassword: Value(false)));
      await montarConSesion(
        tester,
        SesionUsuario(
          usuarioId: id,
          nombre: 'JAVIER RIOS',
          nombreUsuario: 'javier',
          esMaestro: false,
          permisos: const {'personal.ver'},
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.cambioObligatorioTitulo), findsNothing);
      expect(find.byKey(const Key('app_top_bar')), findsOneWidget, reason: 'la sesión ya opera con normalidad');
    });

    testWidgets('BUG REAL: con solo auditoria.ver el router dejaba fuera de Configuración', (tester) async {
      // El sidebar ya mostraba Configuración con `auditoria.ver`
      // (`permisosQueAbrenRuta`), pero el `redirect` seguía usando
      // `permisoRequeridoParaRuta`, que se queda con el PRIMER código de
      // la lista (`usuarios.administrar`) — así que la sección se veía y
      // al entrar mandaba a /acceso-denegado.
      final router = await montarConSesion(
        tester,
        const SesionUsuario(
          usuarioId: 'maestro',
          nombre: 'AUDITORA',
          nombreUsuario: 'auditora',
          esMaestro: false,
          permisos: {'auditoria.ver'},
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // La raíz de la sección es donde estaba la divergencia: es la que
      // tiene DOS códigos que la abren. (`/configuracion/auditoria`
      // tiene uno solo, así que ahí ambos criterios coincidían y el bug
      // no se veía.)
      router.go('/configuracion');
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        isNot('/acceso-denegado'),
        reason: 'auditoria.ver existe justamente para ver la auditoría sin administrar cuentas: '
            'el sidebar ya mostraba la sección y el redirect la negaba al entrar',
      );
      expect(find.text(l10n.accesoDenegadoTitulo), findsNothing);

      router.go('/configuracion/auditoria');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/configuracion/auditoria');
    });
  });
}
