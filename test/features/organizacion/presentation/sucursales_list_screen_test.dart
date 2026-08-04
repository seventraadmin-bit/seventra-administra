import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursales_list_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/lista',
    routes: [
      GoRoute(path: '/lista', builder: (context, state) => const Scaffold(body: SucursalesListScreen())),
      GoRoute(
        path: '/organizacion/sucursales/:id',
        builder: (context, state) => const Scaffold(body: Placeholder()),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final crear = CrearSucursalUseCase(
      SucursalRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );
    await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    await crear.ejecutar(nombre: 'Bodega Sur', tipoSucursalId: SeedIds.tipoSucursalBodega);
  });

  tearDown(() => db.close());

  testWidgets('muestra las sucursales sembradas', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('Sucursal Norte'), findsOneWidget);
    expect(find.text('Bodega Sur'), findsOneWidget);
  });

  testWidgets('el buscador filtra por nombre', (tester) async {
    await _pumpScreen(tester, db);

    await tester.enterText(find.byType(TextField), 'bodega');
    await tester.pumpAndSettle();

    expect(find.text('Bodega Sur'), findsOneWidget);
    expect(find.text('Sucursal Norte'), findsNothing);
  });

  testWidgets('tocar una fila navega al expediente de esa Sucursal', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.text('Sucursal Norte'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });
}
