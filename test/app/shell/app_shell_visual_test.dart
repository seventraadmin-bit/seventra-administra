// Etapa 16 — evolución visual del App Shell (topbar azul institucional,
// jerarquía de superficies, sidebar). Verifica, con la app real montada
// (mismo patrón que `smoke_test.dart`): la barra superior usa el azul
// institucional, el área de contenido usa un tono distinto al de
// sidebar/topbar, y Dashboard/Organización/Comercial/Personal/Nómina y
// un diálogo no producen overflow en claro/oscuro y en los breakpoints
// soportados.

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/app/theme/theme_mode_controller.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _TemaFijo extends ThemeModeController {
  _TemaFijo(this._modo);
  final ThemeMode _modo;

  @override
  ThemeMode build() => _modo;
}

Future<AppDatabase> _pumpApp(WidgetTester tester, {required Size tamano, required ThemeMode tema}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Usuario de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        themeModeControllerProvider.overrideWith(() => _TemaFijo(tema)),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

const _breakpoints = [
  Size(1366, 768),
  Size(1024, 768),
  Size(700, 900),
  Size(500, 900),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Identidad del App Shell', () {
    testWidgets('la barra superior es NEUTRA, no azul (Etapa 5B.1)', (tester) async {
      // Hasta 5B.1 la barra se vestía entera con `colors.accent`. En la
      // identidad de Seventra Administra el Azul Administra se reserva para
      // acciones y estados seleccionados; la superficie de marca es el
      // sidebar, en tinta.
      for (final tema in [ThemeMode.light, ThemeMode.dark]) {
        await _pumpApp(tester, tamano: const Size(1366, 768), tema: tema);

        final contexto = tester.element(find.byKey(const Key('app_top_bar')));
        final colors = Theme.of(contexto).extension<AppColorScheme>()!;
        final contenedor = tester.widget<Container>(find.byKey(const Key('app_top_bar')));
        final color = (contenedor.decoration as BoxDecoration?)?.color ?? contenedor.color;

        expect(color, colors.surface, reason: 'tema: $tema');
        expect(color, isNot(colors.accent), reason: 'la barra azul pertenecía a la identidad anterior');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('el sidebar es la superficie de marca: tinta en claro y oscuro', (tester) async {
      for (final tema in [ThemeMode.light, ThemeMode.dark]) {
        await _pumpApp(tester, tamano: const Size(1366, 768), tema: tema);

        final contexto = tester.element(find.byKey(const Key('app_sidebar')));
        final colors = Theme.of(contexto).extension<AppColorScheme>()!;
        final contenedor = tester.widget<AnimatedContainer>(find.byKey(const Key('app_sidebar')));
        final color = (contenedor.decoration as BoxDecoration?)?.color;

        expect(color, colors.shellSurface, reason: 'tema: $tema');
        expect(color, AppColors.tinta, reason: 'la marca no cambia con el tema');
      }
    });

    testWidgets('el área de contenido usa un tono distinto al de la barra superior/sidebar (canvas vs. surface)', (tester) async {
      await _pumpApp(tester, tamano: const Size(1366, 768), tema: ThemeMode.light);

      final contenido = tester.widget<Container>(find.byKey(const Key('shell_content_area')));
      final contexto = tester.element(find.byKey(const Key('shell_content_area')));
      final colors = Theme.of(contexto).extension<AppColorScheme>()!;

      expect(contenido.color, colors.canvas);
      expect(contenido.color, isNot(colors.surface), reason: 'área de trabajo debe distinguirse de sidebar/topbar');
    });

    testWidgets('los tokens shell* son idénticos en claro y oscuro — identidad de marca constante', (tester) async {
      final claro = AppColorScheme.light();
      final oscuro = AppColorScheme.dark();

      expect(claro.shellForeground, oscuro.shellForeground);
      expect(claro.shellForegroundMuted, oscuro.shellForegroundMuted);
      expect(claro.shellOverlaySubtle, oscuro.shellOverlaySubtle);
      expect(claro.shellOverlayStrong, oscuro.shellOverlayStrong);
      expect(claro.shellSearchBg, oscuro.shellSearchBg);
      expect(claro.shellSearchBorder, oscuro.shellSearchBorder);
      expect(claro.shellFocusRing, oscuro.shellFocusRing);
    });

    testWidgets('pasar el mouse sobre un ítem del sidebar no lanza excepción', (tester) async {
      await _pumpApp(tester, tamano: const Size(1366, 768), tema: ThemeMode.light);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      final item = find.byKey(const Key('nav_item_organizacion'));
      expect(item, findsOneWidget);
      await gesture.moveTo(tester.getCenter(item));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Pantallas piloto — sin overflow en claro/oscuro y breakpoints soportados', () {
    for (final tema in [ThemeMode.light, ThemeMode.dark]) {
      for (final tamano in _breakpoints) {
        final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()} ($tema)';

        testWidgets('Dashboard $etiqueta', (tester) async {
          await _conCapturaDeOverflow(() async {
            await _pumpApp(tester, tamano: tamano, tema: tema);
            expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        });

        testWidgets('Organización $etiqueta', (tester) async {
          await _conCapturaDeOverflow(() async {
            await _pumpApp(tester, tamano: tamano, tema: tema);
            await tester.tap(find.byKey(const Key('nav_item_organizacion')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        });

        testWidgets('Comercial $etiqueta', (tester) async {
          await _conCapturaDeOverflow(() async {
            await _pumpApp(tester, tamano: tamano, tema: tema);
            await tester.tap(find.byKey(const Key('nav_item_comercial')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        });

        testWidgets('Personal (Plantilla activa) $etiqueta', (tester) async {
          await _conCapturaDeOverflow(() async {
            await _pumpApp(tester, tamano: tamano, tema: tema);
            await tester.tap(find.byKey(const Key('nav_item_personal')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        });

        testWidgets('Nómina $etiqueta', (tester) async {
          await _conCapturaDeOverflow(() async {
            await _pumpApp(tester, tamano: tamano, tema: tema);
            await tester.tap(find.byKey(const Key('nav_item_personal')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Nómina').first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        });

        testWidgets('Diálogo (alta de Cliente) $etiqueta', (tester) async {
          await _conCapturaDeOverflow(() async {
            await _pumpApp(tester, tamano: tamano, tema: tema);
            await tester.tap(find.byKey(const Key('nav_item_comercial')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('clientes_boton_nueva')));
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsWidgets);
            expect(tester.takeException(), isNull);
          });
        });
      }
    }
  });
}

/// Instala temporalmente un `FlutterError.onError` que además imprime el
/// diagnóstico completo (widget/línea causante) — sin esto, un
/// `RenderFlex overflowed` capturado por `tester.takeException()` solo
/// reporta el mensaje corto, sin el widget exacto que lo causó.
Future<void> _conCapturaDeOverflow(Future<void> Function() cuerpo) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    // ignore: avoid_print
    print(details.toString());
    original?.call(details);
  };
  try {
    await cuerpo();
  } finally {
    FlutterError.onError = original;
  }
}
