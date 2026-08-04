// Pruebas de la pantalla de expediente de Empresa a nivel de widget —
// específicamente el comportamiento del diálogo de confirmación al
// cancelar, que vive en el widget de pantalla y no en el controlador
// (ver `empresa_expediente_controller_test.dart` para las pruebas del
// estado sucio en sí).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EmpresaExpedienteScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('cancelar sin cambios regresa a consulta sin pedir confirmación', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.byKey(const Key('empresa_expediente_boton_editar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empresa_expediente_boton_guardar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('empresa_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('empresa_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('cancelar con cambios pide confirmación antes de descartar', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.byKey(const Key('empresa_expediente_boton_editar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'RISEG modificado');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('empresa_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);

    // "Seguir editando" (cancelar el diálogo) debe mantener el modo
    // edición intacto, sin descartar nada todavía.
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await tester.tap(find.text(l10n.empresaCancelarConfirmacionCancelar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('empresa_expediente_boton_guardar')), findsOneWidget);

    // Ahora sí confirmar el descarte.
    await tester.tap(find.byKey(const Key('empresa_expediente_boton_cancelar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.empresaCancelarConfirmacionConfirmar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('empresa_expediente_boton_editar')), findsOneWidget);
  });
}
