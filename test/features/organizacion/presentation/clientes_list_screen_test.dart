// Pruebas de la pantalla de listado de Clientes comerciales — buscador
// (incluyendo observaciones) y alta vía el diálogo mínimo (solo nombre
// comercial + observaciones).

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
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

/// Sesión Maestro fija — Etapa 11C activó autorización real en las
/// acciones de esta pantalla; sin este override todas serían
/// rechazadas por `AuthorizationService` (mismo criterio que
/// `smoke_test.dart`).
class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/lista',
    routes: [
      GoRoute(path: '/lista', builder: (context, state) => const Scaffold(body: ClientesListScreen())),
      GoRoute(
        path: '/comercial/clientes/:id',
        builder: (context, state) => const Scaffold(body: Placeholder()),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
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
    final crear = CrearClienteUseCase(ClienteRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    await crear.ejecutar(nombreComercial: 'Sportium');
    await crear.ejecutar(nombreComercial: 'Toluca 32', observaciones: 'Recibo de pago mensual');
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  testWidgets('muestra los Clientes sembrados', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('Sportium'), findsOneWidget);
    expect(find.text('Toluca 32'), findsOneWidget);
  });

  testWidgets('el buscador filtra por observaciones', (tester) async {
    await _pumpScreen(tester, db);

    await tester.enterText(find.byType(TextField), 'recibo de pago');
    await tester.pumpAndSettle();

    expect(find.text('Toluca 32'), findsOneWidget);
    expect(find.text('Sportium'), findsNothing);
  });

  testWidgets('tocar una fila navega al expediente de ese Cliente', (tester) async {
    await _pumpScreen(tester, db);

    await tester.tap(find.text('Sportium'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('crear un nuevo Cliente vía el diálogo de alta mínimo', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('clientes_boton_nueva')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    // Alta mínima: solo dos campos de texto (nombre comercial y
    // observaciones), sin RFC ni dirección ni contactos.
    expect(find.byType(TextFormField), findsNWidgets(2));

    await tester.enterText(find.byType(TextFormField).first, 'Mirabilia');
    await tester.tap(find.text(l10n.clienteAltaBotonCrear));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Placeholder), findsOneWidget);
  });
}
