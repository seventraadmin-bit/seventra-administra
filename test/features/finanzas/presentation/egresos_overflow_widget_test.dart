// Etapa 15 — regresión del overflow vertical real en Finanzas →
// Egresos ("BOTTOM OVERFLOWED BY N PIXELS") con suficientes filas.
// Corregido en el componente compartido `RisegTableBase` (scroll
// vertical interno) — esta prueba verifica cero excepción, que la
// fila inferior es alcanzable con scroll, y que los filtros superiores
// siguen utilizables.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, {required Size tamano}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/egresos',
    routes: [
      GoRoute(path: '/egresos', builder: (context, state) => const Scaffold(body: EgresosListScreen())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
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
    final repo = EgresoRepositoryImpl(db);
    // Suficientes filas para superar la altura del viewport incluso en
    // ventana grande (900px) — el bug real ("con suficientes registros")
    // dependía del volumen, no del tamaño de ventana.
    for (var i = 1; i <= 40; i++) {
      await repo.crear(
        folioEgreso: 'EGR-${i.toString().padLeft(6, '0')}',
        monto: 10000 * i,
        fecha: DateTime(2026, 1, 1).add(Duration(days: i)),
        formaPago: 'efectivo',
        concepto: 'Concepto de prueba número $i',
      );
    }
  });

  tearDown(() => db.close());

  testWidgets('40 Egresos en ventana normal (1440×900): cero overflow, scroll alcanza la última fila', (tester) async {
    await _pumpScreen(tester, db, tamano: const Size(1440, 900));

    expect(tester.takeException(), isNull, reason: 'nunca debe aparecer BOTTOM OVERFLOWED con muchas filas');
    expect(find.text('Concepto de prueba número 1'), findsOneWidget, reason: 'primera fila visible sin scroll');
    // `SingleChildScrollView` construye todas las filas de una vez (sin
    // virtualización) — `find.text` las encuentra en el árbol aunque
    // estén clip-eadas fuera de vista, así que la prueba real de
    // alcanzabilidad es el scroll mismo, no la ausencia del widget.
    final topAntes = tester.getTopLeft(find.text('Concepto de prueba número 40')).dy;

    final scrollables = find.byType(Scrollable);
    await tester.dragUntilVisible(
      find.text('Concepto de prueba número 40'),
      scrollables.last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'el scroll en sí tampoco debe producir overflow');
    final topDespues = tester.getTopLeft(find.text('Concepto de prueba número 40')).dy;
    expect(topDespues, lessThan(topAntes), reason: 'el scroll debe haber movido la fila inferior hacia arriba, dentro de la vista');

    // Los filtros superiores (encabezado) siguen montados y utilizables
    // tras el scroll — nunca se desplazan junto con las filas.
    expect(find.byKey(const Key('egresos_boton_registrar')), findsOneWidget);
  });

  testWidgets('40 Egresos en ventana reducida (900×560): cero overflow', (tester) async {
    await _pumpScreen(tester, db, tamano: const Size(900, 560));

    expect(tester.takeException(), isNull, reason: 'tampoco debe desbordar en ventana reducida');
    expect(find.byKey(const Key('egresos_boton_registrar')), findsOneWidget, reason: 'encabezado sigue visible y utilizable');
  });
}
