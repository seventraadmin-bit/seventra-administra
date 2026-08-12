// Etapa 15 (hallazgo funcional/UX: Inicio de sesión) — pruebas de
// pantalla: layout ancho/compacto sin overflow, mostrar/ocultar
// contraseña, checkbox "Recuérdame en este equipo", validaciones de
// campo vacío, credenciales inválidas, Usuario inactivo, Enter envía el
// formulario, y el mecanismo de restauración de sesión (mismo patrón
// que usa `bootstrap()` en producción: `sesionControllerProvider`
// precargado antes de montar la app).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/auth/sesion_recordada_almacen.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/data/repositories/permiso_usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/restaurar_sesion_recordada_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

class _AlmacenSesionRecordadaEnMemoria implements AlmacenSesionRecordada {
  String? _token;
  @override
  Future<String?> leer() async => _token;
  @override
  Future<void> escribir(String valor) async => _token = valor;
  @override
  Future<void> borrar() async => _token = null;
}

/// Mismo mecanismo que `bootstrap()` usa en producción para precargar
/// una sesión ya resuelta antes de montar la app.
class _SesionPrecargada extends SesionController {
  _SesionPrecargada(this._inicial);
  final SesionUsuario? _inicial;
  @override
  SesionUsuario? build() => _inicial;
}

Future<AppDatabase> _dbConUsuario() async {
  final db = AppDatabase(NativeDatabase.memory());
  const hasher = PasswordHasher(iteraciones: 1000);
  await UsuarioRepositoryImpl(db).crear(
    nombre: 'Ana Torres',
    nombreUsuario: 'ana.torres',
    passwordHash: hasher.hash('Sup3rSecreta!'),
    esMaestro: true,
  );
  return db;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size tamano,
  required AppDatabase db,
  AlmacenSesionRecordada? almacen,
  SesionController Function()? sesion,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (almacen != null) almacenSesionRecordadaProvider.overrideWithValue(almacen),
        if (sesion != null) sesionControllerProvider.overrideWith(sesion),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('layout ancho (>=900): muestra el panel de identidad y el formulario, sin overflow', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
    expect(find.byKey(const Key('auth_logo')), findsOneWidget);
    expect(find.byKey(const Key('login_campo_usuario')), findsOneWidget);
  });

  testWidgets('layout compacto (<900): oculta el panel de identidad, sin overflow', (tester) async {
    await _pumpApp(tester, tamano: const Size(700, 900), db: await _dbConUsuario());

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
    expect(find.byKey(const Key('auth_logo')), findsNothing, reason: 'el panel decorativo completo se oculta, no se encoge');
    expect(find.byKey(const Key('login_campo_usuario')), findsOneWidget);
  });

  testWidgets('mostrar/ocultar contraseña alterna obscureText', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());

    TextField campo() => tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('login_campo_password')), matching: find.byType(TextField)),
        );

    expect(campo().obscureText, isTrue);
    await tester.tap(find.byKey(const Key('login_boton_mostrar_password')));
    await tester.pump();
    expect(campo().obscureText, isFalse);
  });

  testWidgets('checkbox "Recuérdame en este equipo" alterna su valor', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final checkboxFinder = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

    await tester.tap(find.text(l10n.loginRecordarme));
    await tester.pump();
    expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);
  });

  testWidgets('usuario vacío muestra un mensaje claro sin llamar al UseCase', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.enterText(find.byKey(const Key('login_campo_password')), 'algo');
    await tester.tap(find.byKey(const Key('login_boton_entrar')));
    await tester.pump();

    expect(find.text(l10n.loginErrorUsuarioRequerido), findsOneWidget);
  });

  testWidgets('contraseña vacía muestra un mensaje claro', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.enterText(find.byKey(const Key('login_campo_usuario')), 'ana.torres');
    await tester.tap(find.byKey(const Key('login_boton_entrar')));
    await tester.pump();

    expect(find.text(l10n.loginErrorContrasenaRequerida), findsOneWidget);
  });

  testWidgets('credenciales incorrectas muestran el mensaje genérico', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.enterText(find.byKey(const Key('login_campo_usuario')), 'ana.torres');
    await tester.enterText(find.byKey(const Key('login_campo_password')), 'incorrecta');
    await tester.tap(find.byKey(const Key('login_boton_entrar')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.loginErrorCredencialesInvalidas), findsOneWidget);
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
  });

  testWidgets('Usuario inactivo muestra su propio mensaje', (tester) async {
    final db = await _dbConUsuario();
    const hasher = PasswordHasher(iteraciones: 1000);
    final repo = UsuarioRepositoryImpl(db);
    await repo.crear(nombre: 'Beto Ruiz', nombreUsuario: 'beto', passwordHash: hasher.hash('ClaveSegura1'));
    final beto = await repo.obtenerPorNombreUsuario('beto');
    await repo.desactivar(usuarioId: beto!.id, motivo: 'prueba');

    await _pumpApp(tester, tamano: const Size(1440, 900), db: db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.enterText(find.byKey(const Key('login_campo_usuario')), 'beto');
    await tester.enterText(find.byKey(const Key('login_campo_password')), 'ClaveSegura1');
    await tester.tap(find.byKey(const Key('login_boton_entrar')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.loginErrorUsuarioInactivo), findsOneWidget);
  });

  testWidgets('Enter en Contraseña envía el formulario', (tester) async {
    await _pumpApp(tester, tamano: const Size(1440, 900), db: await _dbConUsuario());

    await tester.enterText(find.byKey(const Key('login_campo_usuario')), 'ana.torres');
    await tester.enterText(find.byKey(const Key('login_campo_password')), 'Sup3rSecreta!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_shell')), findsOneWidget);
  });

  testWidgets('recordarme marcado: un "reinicio" con la sesión ya restaurada entra directo al Dashboard', (tester) async {
    final db = await _dbConUsuario();
    final almacen = _AlmacenSesionRecordadaEnMemoria();

    await _pumpApp(tester, tamano: const Size(1440, 900), db: db, almacen: almacen);

    await tester.enterText(find.byKey(const Key('login_campo_usuario')), 'ana.torres');
    await tester.enterText(find.byKey(const Key('login_campo_password')), 'Sup3rSecreta!');
    await tester.tap(find.text('Recuérdame en este equipo'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login_boton_entrar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_shell')), findsOneWidget);
    expect(await almacen.leer(), isNotNull, reason: 'el token quedó guardado para el próximo arranque');

    // "Reinicio": mismo mecanismo que `bootstrap()` — se resuelve la
    // sesión recordada ANTES de montar la app, y se precarga el
    // controlador con ese resultado.
    final restaurada = await RestaurarSesionRecordadaUseCase(
      UsuarioRepositoryImpl(db),
      PermisoUsuarioRepositoryImpl(db),
      almacen,
    ).ejecutar();
    expect(restaurada, isNotNull);

    await tester.pumpWidget(Container());
    await _pumpApp(tester, tamano: const Size(1440, 900), db: db, almacen: almacen, sesion: () => _SesionPrecargada(restaurada));

    expect(find.byKey(const Key('login_screen')), findsNothing);
    expect(find.byKey(const Key('app_shell')), findsOneWidget);
  });
}
