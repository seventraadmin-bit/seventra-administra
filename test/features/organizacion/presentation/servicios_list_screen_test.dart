// Pruebas de la pantalla de listado de Servicios — buscador (código,
// nombre, Cliente, Tipo de Servicio, observaciones) y alta mínima vía
// el diálogo (nombre, Cliente, Tipo de Servicio, fecha de inicio,
// observaciones opcionales).

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
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicios_list_screen.dart';

Future<GoRouter> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/lista',
    routes: [
      GoRoute(path: '/lista', builder: (context, state) => const Scaffold(body: ServiciosListScreen())),
      GoRoute(
        path: '/comercial/servicios/:id',
        builder: (context, state) => Scaffold(appBar: AppBar(), body: const Placeholder()),
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
  return router;
}

/// El campo de fecha (`RisegDateField`) abre el selector nativo de
/// Material — confirmar sin elegir otra fecha basta para las pruebas de
/// este archivo, que no dependen de una fecha específica. El selector
/// se abre COMO UN SEGUNDO diálogo apilado sobre el de alta — se busca
/// su botón de confirmar (localizado, "ACEPTAR" en es, no "OK") solo
/// entre los descendientes del diálogo más reciente
/// (`find.byType(Dialog).last`), nunca por texto ni con `.last` global
/// sobre `TextFormField`/`TextButton`, que también encontraría campos y
/// botones del diálogo de alta debajo (el de observaciones, por
/// ejemplo, es el último `TextFormField` del formulario, no la fecha).
Future<void> _confirmarFechaEnDialogo(WidgetTester tester, Finder campoFecha) async {
  await tester.tap(campoFecha);
  await tester.pumpAndSettle();

  final dialogoSelector = find.byType(Dialog).last;
  await tester.tap(find.descendant(of: dialogoSelector, matching: find.byType(TextButton)).last);
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final crearServicio = CrearServicioUseCase(ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), generarCodigo, validator);

    final sportium = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    final sportiumId = sportium.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
    await crearServicio.ejecutar(
      clienteId: sportiumId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );

    final construcciones = await crearCliente.ejecutar(nombreComercial: 'Construcciones Habitacionales');
    final construccionesId =
        construcciones.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
    await crearServicio.ejecutar(
      clienteId: construccionesId,
      borrador: ServicioBorrador(
        nombre: 'Mirabilia',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
  });

  tearDown(() => db.close());

  testWidgets('muestra los Servicios creados, con su Cliente y Tipo de Servicio', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('Vigilancia Sportium Toluca'), findsOneWidget);
    expect(find.text('Mirabilia'), findsOneWidget);
    expect(find.text('Sportium'), findsOneWidget);
    expect(find.text('Construcciones Habitacionales'), findsOneWidget);
    expect(find.text('Vigilancia fija'), findsNWidgets(2));
  });

  testWidgets('el buscador filtra por nombre del Cliente (Construcciones Habitacionales → Mirabilia)', (tester) async {
    await _pumpScreen(tester, db);

    await tester.enterText(find.byType(TextField), 'construcciones habitacionales');
    await tester.pumpAndSettle();

    expect(find.text('Mirabilia'), findsOneWidget);
    expect(find.text('Vigilancia Sportium Toluca'), findsNothing);
  });

  testWidgets('tocar una fila navega al expediente de ese Servicio', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.text('Mirabilia'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('alta mínima: nombre, Cliente, Tipo de Servicio, fecha de inicio', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('servicios_boton_nuevo')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Rondín Sportium CDMX');

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sportium').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vigilancia fija').last);
    await tester.pumpAndSettle();

    await _confirmarFechaEnDialogo(tester, find.byType(TextFormField).at(1));

    await tester.tap(find.text(l10n.servicioAltaBotonCrear));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Placeholder), findsOneWidget, reason: 'navega al expediente del Servicio recién creado');
  });

  testWidgets('Sportium puede tener cuatro Servicios distintos', (tester) async {
    final router = await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    for (final nombre in ['Vigilancia Sportium Interlomas', 'Vigilancia Sportium Satélite', 'Rondín Sportium CDMX']) {
      await tester.tap(find.byKey(const Key('servicios_boton_nuevo')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, nombre);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sportium').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vigilancia fija').last);
      await tester.pumpAndSettle();
      await _confirmarFechaEnDialogo(tester, find.byType(TextFormField).at(1));
      await tester.tap(find.text(l10n.servicioAltaBotonCrear));
      await tester.pumpAndSettle();

      // Regresa al listado para la siguiente alta.
      router.pop();
      await tester.pumpAndSettle();
    }

    await tester.enterText(find.byType(TextField), 'sportium');
    await tester.pumpAndSettle();
    expect(find.text('Vigilancia Sportium Toluca'), findsOneWidget);
    expect(find.text('Vigilancia Sportium Interlomas'), findsOneWidget);
    expect(find.text('Vigilancia Sportium Satélite'), findsOneWidget);
    expect(find.text('Rondín Sportium CDMX'), findsOneWidget);
  });
}
