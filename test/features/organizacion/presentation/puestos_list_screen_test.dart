// Pruebas de la pantalla de listado de Puestos — buscador (incluyendo
// descripción, corrección #4) y alta vía el diálogo (corrección #1/#3:
// el Área activa se valida también en dominio, no solo en el selector).

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
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puestos_list_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/lista',
    routes: [
      GoRoute(path: '/lista', builder: (context, state) => const Scaffold(body: PuestosListScreen())),
      GoRoute(
        path: '/organizacion/puestos/:id',
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
    final crear = CrearPuestoUseCase(
      PuestoRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
    await crear.ejecutar(const PuestoBorrador(
      nombre: 'Guardia Norte',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 1,
    ));
    await crear.ejecutar(const PuestoBorrador(
      nombre: 'Analista de Reclutamiento',
      areaId: SeedIds.areaReclutamiento,
      tipo: TipoPuesto.administrativo,
      nivelJerarquico: 4,
      descripcion: 'Entrevistas y seguimiento de candidatos',
    ));
  });

  tearDown(() => db.close());

  testWidgets('muestra los Puestos sembrados', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('Guardia Norte'), findsOneWidget);
    expect(find.text('Analista de Reclutamiento'), findsOneWidget);
  });

  testWidgets('el buscador filtra por descripción', (tester) async {
    await _pumpScreen(tester, db);

    await tester.enterText(find.byType(TextField), 'candidatos');
    await tester.pumpAndSettle();

    expect(find.text('Analista de Reclutamiento'), findsOneWidget);
    expect(find.text('Guardia Norte'), findsNothing);
  });

  testWidgets('tocar una fila navega al expediente de ese Puesto', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.text('Guardia Norte'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('crear un nuevo Puesto vía el diálogo de alta', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('puestos_boton_nueva')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Supervisor');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Operaciones').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<TipoPuesto>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.puestoTipoOperativo).last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, '5');

    await tester.tap(find.text(l10n.puestoAltaBotonCrear));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Placeholder), findsOneWidget);
  });
}
