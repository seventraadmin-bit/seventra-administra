// Etapa 14C (Respaldo y restauración) — pruebas de pantalla: la
// pestaña "Respaldo" solo aparece para el Usuario Maestro dentro de
// Configuración, y la ruta `/configuracion/respaldo` redirige a
// acceso-denegado si se navega directo sin ser Maestro (doble candado,
// mismo criterio que la eliminación física de la Etapa 11D).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/respaldo/respaldo_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _SesionAdministradorNoMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-admin',
      nombre: 'Administrador de prueba',
      nombreUsuario: 'admin',
      esMaestro: false,
      permisos: {'usuarios.administrar'},
    );
  }
}

Future<void> _pumpApp(WidgetTester tester, {required SesionController Function() sesion}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-admin', nombre: 'Administrador de prueba', nombreUsuario: 'admin', esMaestro: false, permisos: {'usuarios.administrar'}, ));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
        // `RespaldoController` lee `backupsDirProvider` al construirse;
        // se sobreescribe directo (no `appPathsProvider`, que exige
        // `path_provider` real) con una ruta inexistente — el
        // controlador ya maneja ese caso como "sin respaldos".
        backupsDirProvider.overrideWithValue(r'C:\riseg_respaldo_screen_test_inexistente'),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Maestro ve la pestaña Respaldo y puede abrirla', (tester) async {
    await _pumpApp(tester, sesion: _SesionMaestroDePrueba.new);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/configuracion/respaldo');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.configuracionTabRespaldo), findsWidgets);
    expect(find.text(l10n.respaldoTitulo), findsOneWidget);
    expect(find.byKey(const Key('respaldo_boton_crear')), findsOneWidget);
    expect(find.byKey(const Key('respaldo_boton_restaurar')), findsOneWidget);
  });

  testWidgets('Administrador sin ser Maestro no ve la pestaña Respaldo en Configuración', (tester) async {
    await _pumpApp(tester, sesion: _SesionAdministradorNoMaestroDePrueba.new);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/configuracion/usuarios');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.configuracionTabRespaldo), findsNothing);
  });

  testWidgets('Administrador sin ser Maestro es redirigido si navega directo a /configuracion/respaldo', (tester) async {
    await _pumpApp(tester, sesion: _SesionAdministradorNoMaestroDePrueba.new);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/configuracion/respaldo');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.respaldoTitulo), findsNothing);
    expect(find.byKey(const Key('acceso_denegado_screen')), findsOneWidget);
  });
}
