import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/shell/shell_destinations.dart';
import 'package:riseg_one/app/shell/widgets/app_sidebar.dart';
import 'package:riseg_one/app/theme/app_theme.dart';

/// Regresión de una excepción real vista corriendo RISEG ONE en Windows:
/// "The Scrollbar's ScrollController has no ScrollPosition attached."
///
/// Causa: el `Scrollbar` de la zona de navegación del sidebar (agregado
/// en el commit `ee1b4ea`, `thumbVisibility: true`) y el `ListView` que
/// envuelve no compartían ningún `ScrollController` explícito. Sin uno,
/// cada widget resuelve su controller por su cuenta y en producción
/// terminan usando controllers *distintos*:
///
/// - `Scrollbar` sin `controller` cae en `PrimaryScrollController.maybeOf`
///   — que sí existe (todo `ModalRoute`/página envuelve su contenido en
///   uno, ver `routes.dart`), pero nada más en esta página está
///   escribiéndole ninguna `ScrollPosition`.
/// - `ListView` sin `controller` resuelve `primary` a través de
///   `PrimaryScrollController.shouldInherit`, que por diseño **solo
///   hereda automáticamente en plataformas móviles** (ver
///   `primary_scroll_controller.dart`, `_kMobilePlatforms`). En
///   Windows/macOS/Linux esto es `false`, así que el `ListView` arma su
///   propio `Scrollable` con un controller interno, no el ambiental.
///
/// El resultado: el controller que ve el `Scrollbar` nunca tiene
/// clientes (`hasClients == false`) → la aserción de Flutter dispara.
///
/// Por qué no apareció en la suite hasta ahora: `flutter test` fuerza
/// `defaultTargetPlatform` a `TargetPlatform.android` salvo que se
/// sobreescriba (ver el doc comment de `defaultTargetPlatform` en
/// `foundation/platform.dart`) — Android sí es una plataforma "móvil",
/// así que en pruebas el `ListView` heredaba correctamente el mismo
/// controller que el `Scrollbar` y el bug quedaba invisible. Estas
/// pruebas fuerzan `debugDefaultTargetPlatformOverride` a cada
/// plataforma de escritorio real para reproducirlo de verdad.
///
/// El override se restaura con `try/finally` dentro del propio cuerpo
/// de la prueba (no `addTearDown`): `TestWidgetsFlutterBinding`
/// verifica que ningún "debug var" de foundation haya quedado
/// modificado justo al terminar el callback de `testWidgets`, antes de
/// que corran los `addTearDown` registrados — dejarlo en un
/// `addTearDown` dispara un segundo error ("debug variable was changed
/// by the test") aunque la prueba en sí haya pasado.
void main() {
  final destinations = [
    for (final def in shellModuleDefs) ShellDestination(path: def.path, icon: def.icon, label: def.path),
  ];

  Future<void> pumpSidebar(WidgetTester tester, {bool collapsed = false}) async {
    // Un `MaterialApp` real (no solo un `Widget` suelto) es necesario:
    // el `PrimaryScrollController` ambiental que dispara el bug lo
    // provee `ModalRoute`/`Navigator`, exactamente como en la app real
    // (ver `routes.dart`) — envolver el sidebar directo en `Directionality`
    // no reproduciría el desajuste.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AppSidebar(
            destinations: destinations,
            activeIndex: 0,
            collapsed: collapsed,
            onDestinationSelected: (_) {},
            onToggleCollapse: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]) {
    testWidgets(
      'en $platform, el Scrollbar de la navegación del sidebar no lanza '
      '"ScrollController has no ScrollPosition attached"',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await pumpSidebar(tester);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'en Windows, arrastrar la lista de navegación sigue funcionando (Scrollbar y ListView comparten controller)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        tester.view.physicalSize = const Size(1440, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpSidebar(tester);
        expect(tester.takeException(), isNull);

        await tester.drag(find.byKey(const Key('app_sidebar_nav_scroll')), const Offset(0, -600));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(Key('nav_item_${destinations.last.id}')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('en Windows, colapsar el sidebar tampoco lanza la excepción', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpSidebar(tester, collapsed: true);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
