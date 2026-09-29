// IF-5 — EL DEFECTO DE LA RESTAURACIÓN, y su regresión.
//
// Síntoma observado en ejecución real: entrar, cerrar la ventana con la X (sin
// «Cerrar sesión») y volver a abrir dejaba la aplicación en «Iniciar sesión»,
// con la credencial intacta en el almacén seguro.
//
// CAUSA: restaurar la sesión pasó de ser una lectura LOCAL —instantánea, hecha
// antes de `runApp`— a una llamada de RED. Se lanzó sin esperar para no dejar la
// ventana en blanco, así que el primer `redirect` del router corría con la sesión
// todavía en `null` y mandaba a `/login`. Cuando la restauración terminaba y
// publicaba la sesión, **nada le decía al router que volviera a evaluar**: el
// `redirect` de GoRouter sólo corre al navegar.
//
// Estas pruebas fijan las dos direcciones de la condición de aceptación.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/app/router/refresco_de_sesion.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'package:drift/native.dart';

import '../support/sesion_en_base.dart';

/// Sesión que empieza vacía y se publica DESPUÉS, igual que hace la restauración
/// remota cuando el refresco vuelve del servidor.
class _SesionTardia extends SesionController {
  @override
  SesionUsuario? build() => null;

  void publicar(SesionUsuario sesion) => state = sesion;
}

void main() {
  const maestro = SesionUsuario(
    usuarioId: '01a0eca0-fcec-78e4-b3d9-6566cb214aa3',
    nombre: 'Maestro RISEG',
    nombreUsuario: 'maestro@riseg.mx',
    esMaestro: true,
    permisos: {},
  );

  Future<({ProviderContainer contenedor, GoRouter router})> montar(
    WidgetTester tester,
    AppDatabase db,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final contenedor = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionTardia.new),
      ],
    );
    addTearDown(contenedor.dispose);

    // Exactamente como lo arma `bootstrap()`: el router recibe el puente que le
    // avisa cuando la sesión cambia.
    final refresco = RefrescoDeSesion(contenedor);
    addTearDown(refresco.dispose);

    final router = createAppRouter(refreshListenable: refresco);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: RisegOneApp(router: router),
      ),
    );
    await tester.pumpAndSettle();

    return (contenedor: contenedor, router: router);
  }

  testWidgets(
    'una sesión restaurada TARDE saca la aplicación del login sin tocar nada',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await sembrarSesionEnBase(db, maestro);

      final montaje = await montar(tester, db);

      // Primer fotograma: la restauración todavía no volvió del servidor, así que
      // se ve el login. Eso es correcto y esperado.
      expect(find.byKey(const Key('login_screen')), findsOneWidget);
      expect(find.byKey(const Key('app_shell')), findsNothing);

      // Llega el refresco y se publica la sesión — nadie navega ni pulsa nada.
      (montaje.contenedor.read(sesionControllerProvider.notifier) as _SesionTardia)
          .publicar(maestro);
      await tester.pumpAndSettle();

      // ESTE es el defecto: sin `refreshListenable` el router no volvía a
      // evaluar y la aplicación se quedaba en «Iniciar sesión» para siempre,
      // aunque la sesión ya estuviera viva.
      expect(
        find.byKey(const Key('app_shell')),
        findsOneWidget,
        reason: 'publicar la sesión debe reevaluar el gate y entrar al shell',
      );
      expect(find.byKey(const Key('login_screen')), findsNothing);
    },
  );

  testWidgets(
    'la condición inversa: sin sesión que restaurar, se queda en el login',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await montar(tester, db);

      // Nada que publicar —es el caso de «Cerrar sesión» explícito, que borró la
      // credencial— y por tanto nada que reevaluar.
      expect(find.byKey(const Key('login_screen')), findsOneWidget);
      expect(find.byKey(const Key('app_shell')), findsNothing);
    },
  );

  testWidgets(
    'perder la sesión ya dentro devuelve al login en el acto',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await sembrarSesionEnBase(db, maestro);

      final montaje = await montar(tester, db);
      final controlador =
          montaje.contenedor.read(sesionControllerProvider.notifier) as _SesionTardia;

      controlador.publicar(maestro);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app_shell')), findsOneWidget);

      // El mismo puente tiene que funcionar en la otra dirección: si la sesión
      // muere —acceso revocado, suscripción caída, cierre en otro sitio— el gate
      // se vuelve a evaluar sin esperar a que alguien navegue.
      controlador.logout();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_screen')), findsOneWidget);
      expect(find.byKey(const Key('app_shell')), findsNothing);
    },
  );

  test('el puente se suscribe a la sesión y avisa de cada cambio', () {
    final contenedor = ProviderContainer(
      overrides: [sesionControllerProvider.overrideWith(_SesionTardia.new)],
    );
    addTearDown(contenedor.dispose);

    final refresco = RefrescoDeSesion(contenedor);
    addTearDown(refresco.dispose);

    var avisos = 0;
    refresco.addListener(() => avisos++);

    final controlador = contenedor.read(sesionControllerProvider.notifier) as _SesionTardia;

    controlador.publicar(maestro);
    expect(avisos, 1, reason: 'publicar la sesión avisa');

    controlador.logout();
    expect(avisos, 2, reason: 'perderla también');
  });
}
