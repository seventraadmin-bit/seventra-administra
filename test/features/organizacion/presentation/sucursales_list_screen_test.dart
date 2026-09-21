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

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, {Size tamano = const Size(1440, 900), ThemeData? tema}) async {
  tester.view.physicalSize = tamano;
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
        theme: tema ?? AppTheme.light(),
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

  // Etapa 16, tercera pasada visual: Sucursales pasó de tabla a tarjetas
  // — el nombre se muestra en mayúsculas (`_SucursalCard`), nunca tal
  // cual se capturó.
  testWidgets('muestra las sucursales sembradas', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('SUCURSAL NORTE'), findsOneWidget);
    expect(find.text('BODEGA SUR'), findsOneWidget);
  });

  testWidgets('el buscador filtra por nombre', (tester) async {
    await _pumpScreen(tester, db);

    await tester.enterText(find.byType(TextField), 'bodega');
    await tester.pumpAndSettle();

    expect(find.text('BODEGA SUR'), findsOneWidget);
    expect(find.text('SUCURSAL NORTE'), findsNothing);
  });

  testWidgets('tocar una tarjeta navega al expediente de esa Sucursal', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.text('SUCURSAL NORTE'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('la tarjeta muestra el estado operativo y las métricas reales (0 Personal/0 Servicios sin relaciones)', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.sucursalEstadoOperativoOperando), findsWidgets);
    expect(find.textContaining('Personal'), findsWidgets);
    expect(find.textContaining('Servicios'), findsWidgets);
    expect(find.text(l10n.sucursalUbicacionNoRegistrada), findsWidgets, reason: 'ninguna Sucursal sembrada tiene dirección capturada');
  });

  group('columnas adaptativas', () {
    testWidgets('ancho amplio (≥1200): 3 columnas — las 2 primeras tarjetas comparten fila', (tester) async {
      await _pumpScreen(tester, db, tamano: const Size(1400, 900));

      final yNorte = tester.getTopLeft(find.text('SUCURSAL NORTE')).dy;
      final ySur = tester.getTopLeft(find.text('BODEGA SUR')).dy;
      expect(yNorte, ySur);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho angosto (~500): 1 columna — las tarjetas se apilan', (tester) async {
      await _pumpScreen(tester, db, tamano: const Size(500, 900));

      final yNorte = tester.getTopLeft(find.text('SUCURSAL NORTE')).dy;
      final ySur = tester.getTopLeft(find.text('BODEGA SUR')).dy;
      expect(ySur, greaterThan(yNorte));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('sin ninguna sucursal: estado vacío con acción de alta, sin overflow', (tester) async {
    final dbVacia = AppDatabase(NativeDatabase.memory());
    addTearDown(dbVacia.close);
    await _pumpScreen(tester, dbVacia);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.sucursalesListadoVacioTitulo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modo oscuro: cero overflow', (tester) async {
    await _pumpScreen(tester, db, tema: AppTheme.dark());
    expect(tester.takeException(), isNull);
  });
}
