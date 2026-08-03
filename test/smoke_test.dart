// Smoke test de la Etapa 1: confirma que la app arranca, resuelve rutas,
// localización, tema y Riverpod/Drift sin necesitar la inicialización real
// de `bootstrap.dart` (que depende de path_provider, no disponible en
// widget tests).

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_control_activos/app/app.dart';
import 'package:riseg_control_activos/core/config/env.dart';
import 'package:riseg_control_activos/core/database/app_database.dart';
import 'package:riseg_control_activos/core/di/providers.dart';

void main() {
  testWidgets('RISEG ONE arranca y muestra la pantalla de verificación', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final testDatabase = AppDatabase(NativeDatabase.memory());
    addTearDown(testDatabase.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(Env.dev),
          appDatabaseProvider.overrideWithValue(testDatabase),
        ],
        child: const RisegOneApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('RISEG ONE'), findsWidgets);
    expect(find.text('Etapa 1 — Verificación de infraestructura'), findsOneWidget);
  });
}
