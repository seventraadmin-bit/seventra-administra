// Etapa 4D — la pantalla de Respaldos COMPLETA, con las dos mitades.
//
// La sección portable ya se prueba aislada, pero eso no dice si cabe junto
// a lo que ya había. Esta pantalla creció: descripción, aviso de
// credenciales, dos botones, la lista de respaldos y ahora cinco acciones
// más. A 500 px es el sitio donde este proyecto ha tenido desbordes reales
// antes, así que se comprueba la composición entera.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/respaldo/presentation/respaldo_screen.dart';
import 'package:riseg_one/features/respaldo/respaldo_providers.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required Size tamano, required Brightness brillo}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Una carpeta que no existe: el controlador ya trata ese caso
          // como "sin respaldos", y así la prueba no toca el disco real.
          backupsDirProvider.overrideWithValue(r'C:\riseg_respaldo_responsive_inexistente'),
        ],
        child: MaterialApp(
          theme: brillo == Brightness.light ? AppTheme.light() : AppTheme.dark(),
          locale: const Locale('es'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es')],
          home: const Scaffold(body: RespaldoScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final tamano in [const Size(1366, 768), const Size(1024, 700), const Size(700, 700), const Size(500, 700)]) {
    for (final brillo in [Brightness.light, Brightness.dark]) {
      testWidgets('Respaldos completo a ${tamano.width.toInt()} px, ${brillo.name}', (tester) async {
        await pump(tester, tamano: tamano, brillo: brillo);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('respaldo_boton_crear')), findsOneWidget);

        // Hay que desplazar para llegar a la segunda mitad: la pantalla es
        // una lista perezosa, que no construye lo que está bajo el pliegue. En
        // los anchos estrechos la sección portable empieza fuera de la
        // ventana, así que buscarla sin desplazar diría 'no está' cuando lo
        // que ocurre es que todavía no se ha creado.
        await tester.dragUntilVisible(
          find.byKey(const Key('portable_boton_preparar')),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'la segunda mitad tampoco puede desbordar');
        expect(find.byKey(const Key('portable_boton_preparar')), findsOneWidget);
      });
    }
  }
}
