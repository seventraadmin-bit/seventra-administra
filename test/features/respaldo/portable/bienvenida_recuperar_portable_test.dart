// Etapa 4D — la puerta de entrada en un equipo nuevo.
//
// Esta prueba cubre el hueco que casi se quedó abierto: la sección de
// recuperación portable vive en Configuración, y a Configuración no se
// llega sin sesión. En una computadora recién instalada no hay ninguna
// sesión que iniciar, así que sin una entrada en la pantalla de bienvenida
// el respaldo portable no tendría por dónde entrar y la etapa entera no
// serviría para lo único que se construyó: la computadora se destruyó.
//
// IF-5 — el alta del primer Maestro se retiró con la autenticación local, así
// que la pantalla sin sesión es el LOGIN. La entrada de recuperación se movió
// ahí: si no, en un equipo recién instalado no habría por dónde entrar, y la
// etapa 4D no serviría para lo único que se construyó.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required Size tamano}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: RisegOneApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('en un equipo nuevo se puede recuperar SIN crear antes un usuario', (tester) async {
    await pump(tester, tamano: const Size(1366, 768));

    // IF-5 — la entrada vive ahora en el login, que es LA pantalla sin sesión.
    expect(find.byKey(const Key('login_screen')), findsOneWidget);
    expect(
      find.byKey(const Key('bootstrap_boton_recuperar_portable')),
      findsOneWidget,
      reason: 'sin esto, recuperar exigiría crear primero un Maestro, y la instalación dejaría de estar vacía',
    );
  });

  testWidgets('la invitación se explica sin jerga', (tester) async {
    await pump(tester, tamano: const Size(1366, 768));
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.portableBienvenidaYaTeniasTitulo), findsOneWidget);
    for (final prohibida in ['DEK', 'MWK', 'KDF', 'Argon', 'AES', 'payload']) {
      expect(find.textContaining(prohibida, findRichText: true), findsNothing);
    }
  });

  group('Sin desbordes en la pantalla de bienvenida', () {
    // 900 px es el umbral de las dos zonas de esta pantalla, así que se
    // prueba a los dos lados.
    for (final tamano in [const Size(1366, 768), const Size(1024, 700), const Size(700, 700), const Size(500, 700)]) {
      testWidgets('a ${tamano.width.toInt()} px', (tester) async {
        await pump(tester, tamano: tamano);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('bootstrap_boton_recuperar_portable')), findsOneWidget);
      });
    }
  });
}
