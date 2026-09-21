// Etapa 16, tercera pasada visual — Puestos: nueva jerarquía visual
// (Nombre fuerte + Código secundario, sin columna "Código" suelta),
// badges neutrales de Tipo/Nivel, fila interactiva con chevron,
// buscador corto ("Buscar puesto...") y responsive/tema oscuro.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puestos_list_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, {Size tamano = const Size(1366, 900), ThemeData? tema}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/lista',
    routes: [
      GoRoute(path: '/lista', builder: (context, state) => const Scaffold(body: PuestosListScreen())),
      GoRoute(path: '/organizacion/puestos/:id', builder: (context, state) => const Scaffold(body: Placeholder())),
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
    final crear = CrearPuestoUseCase(
      PuestoRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
    await crear.ejecutar(const PuestoBorrador(
      nombre: 'Elemento Operativo',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 1,
    ));
    await crear.ejecutar(const PuestoBorrador(
      nombre: 'Gerente Operativo',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.administrativo,
      nivelJerarquico: 7,
    ));
  });

  tearDown(() => db.close());

  testWidgets('Nombre fuerte + código secundario apilados, sin una columna "Código" suelta', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text('Elemento Operativo'), findsOneWidget);
    expect(find.textContaining('PUE-'), findsWidgets);
    expect(find.text(l10n.puestosColumnaCodigo), findsNothing, reason: 'el código ya vive apilado bajo el nombre, no en su propia columna');
  });

  testWidgets('Tipo y Nivel se muestran como badges ("N1"/"N7")', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('N1'), findsOneWidget);
    expect(find.text('N7'), findsOneWidget);
  });

  testWidgets('fila interactiva: hover/chevron y tocar navega al expediente', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.tap(find.text('Elemento Operativo'));
    await tester.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('el buscador ("Buscar puesto...") filtra por nombre', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.puestosListadoBuscarHint), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gerente');
    await tester.pumpAndSettle();

    expect(find.text('Gerente Operativo'), findsOneWidget);
    expect(find.text('Elemento Operativo'), findsNothing);
  });

  group('responsive y tema', () {
    for (final tamano in const [Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)]) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await _pumpScreen(tester, db, tamano: tamano);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('modo oscuro: cero overflow', (tester) async {
      await _pumpScreen(tester, db, tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });
}
