// Smoke test de la Etapa 2 (Shell): confirma navegación, colapso del
// sidebar, marcado del destino activo y presencia del logotipo — usando
// Keys estables, no únicamente texto traducido.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';

/// Fuerza un tamaño de ventana de escritorio "cómodo" (por encima del
/// breakpoint de colapso automático del sidebar) para que las pruebas no
/// dependan del tamaño de superficie por defecto de flutter_test.
///
/// Sobrescribe [appDatabaseProvider] con una base en memoria — desde que
/// `/organizacion` abre `EmpresaExpedienteScreen` (Etapa 4B), el Shell ya
/// depende de la base de datos incluso en estas pruebas de navegación.
Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  // Un router nuevo por prueba: `GoRouter` guarda estado de navegación
  // mutable, así que reusar una instancia entre pruebas filtraría a dónde
  // navegó la prueba anterior.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Dashboard es el destino inicial', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('app_shell')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_welcome')), findsOneWidget);
  });

  testWidgets('Navegar a otra rama cambia el contenido sin reconstruir el shell', (tester) async {
    await _pumpApp(tester);

    // Personal sigue siendo un placeholder genérico — Organización ya
    // no lo es desde la Etapa 4B (ver prueba dedicada más abajo).
    await tester.tap(find.byKey(const Key('nav_item_personal')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_shell')), findsOneWidget);
    expect(find.byKey(const Key('app_sidebar')), findsOneWidget);
    expect(find.byKey(const Key('module_placeholder_personal')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_welcome')), findsNothing);
  });

  testWidgets('La ruta /organizacion abre el expediente de Empresa directamente', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('nav_item_organizacion')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empresa_expediente_screen')), findsOneWidget);
    expect(find.byKey(const Key('module_placeholder_organizacion')), findsNothing);
  });

  testWidgets('El destino activo queda marcado semánticamente', (tester) async {
    await _pumpApp(tester);

    bool? selectedOf(String navItemId) {
      final widget = tester.widget<Semantics>(find.byKey(Key('nav_item_$navItemId')));
      return widget.properties.selected;
    }

    expect(selectedOf('dashboard'), isTrue);
    expect(selectedOf('personal'), isFalse);

    await tester.tap(find.byKey(const Key('nav_item_personal')));
    await tester.pumpAndSettle();

    expect(selectedOf('personal'), isTrue);
    expect(selectedOf('dashboard'), isFalse);
  });

  testWidgets('El sidebar puede colapsarse', (tester) async {
    await _pumpApp(tester);

    final sidebarFinder = find.byKey(const Key('app_sidebar'));
    final widthBefore = tester.getSize(sidebarFinder).width;

    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();

    final widthAfter = tester.getSize(sidebarFinder).width;
    expect(widthAfter, lessThan(widthBefore));
  });

  testWidgets('El logotipo oficial se muestra en el sidebar', (tester) async {
    await _pumpApp(tester);

    final logoFinder = find.byKey(const Key('sidebar_logo'));
    expect(logoFinder, findsOneWidget);

    final image = tester.widget<Image>(logoFinder);
    final assetImage = image.image as AssetImage;
    expect(assetImage.assetName, 'assets/images/logo.png');
  });

  testWidgets('La pantalla de verificación de la Etapa 1 ya no existe', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Etapa 1 — Verificación de infraestructura'), findsNothing);
  });
}
