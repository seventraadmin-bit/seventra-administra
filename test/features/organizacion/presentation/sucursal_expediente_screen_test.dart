// Pruebas de la pantalla de expediente de Sucursal a nivel de widget —
// el diálogo de confirmación al cancelar (mismo patrón que Empresa en
// 4B) y la confirmación al cambiar el estado operativo, que es
// exclusiva de esta pantalla.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_screen.dart';

Future<String> _crearSucursal(AppDatabase db) async {
  final crear = CrearSucursalUseCase(
    SucursalRepositoryImpl(db),
    GenerarCodigoUseCase(CodigoSecuenciaService(db)),
  );
  final creada = await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
  return creada.when(ok: (s) => s.id, failure: (f) => throw StateError(f.message));
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, String sucursalId) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SucursalExpedienteScreen(sucursalId: sucursalId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late String sucursalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sucursalId = await _crearSucursal(db);
  });

  tearDown(() => db.close());

  testWidgets('cancelar sin cambios regresa a consulta sin pedir confirmación', (tester) async {
    await _pumpScreen(tester, db, sucursalId);

    await tester.tap(find.byKey(const Key('sucursal_expediente_boton_editar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sucursal_expediente_boton_guardar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sucursal_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('sucursal_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('cancelar con cambios pide confirmación antes de descartar', (tester) async {
    await _pumpScreen(tester, db, sucursalId);

    await tester.tap(find.byKey(const Key('sucursal_expediente_boton_editar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Nombre modificado');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sucursal_expediente_boton_cancelar')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await tester.tap(find.text(l10n.empresaCancelarConfirmacionConfirmar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('sucursal_expediente_boton_editar')), findsOneWidget);
  });

  testWidgets('cambiar estado operativo pide confirmación y actualiza la insignia', (tester) async {
    await _pumpScreen(tester, db, sucursalId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.sucursalEstadoOperativoOperando), findsOneWidget);

    await tester.tap(find.byKey(const Key('sucursal_boton_estado_operativo')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.sucursalEstadoOperativoCerradaTemporalmente), findsOneWidget);
    expect(find.text(l10n.sucursalBotonReabrir), findsOneWidget);
  });
}
