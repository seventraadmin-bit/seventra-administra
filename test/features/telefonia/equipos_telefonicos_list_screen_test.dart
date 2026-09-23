// Regresión representativa (Etapa 9D, corrección de `RisegSectionHeader`
// en el Design System — ver `test/design_system/riseg_section_header_test.dart`
// y `test/features/inventario/articulo_expediente_screen_test.dart` para
// el bug original y la corrección del componente compartido). Esta
// pantalla fue señalada en la auditoría de los 41 usos del componente
// como uno de los casos de mayor riesgo real: "Configurar equipo"
// (primaryAction, gateado por permiso `telefonia.modificar`) +
// "Regularizar artículo" (secondaryAction, solo Maestro) — 2 botones
// junto al título, en una pantalla de LISTADO (no un expediente),
// confirmando que la corrección del componente compartido también
// resuelve este caso sin tocar esta pantalla en absoluto.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpEquiposTelefonicos(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    // Etapa 3B: autorizar revalida contra la base, así que el
    // escenario de la sesión tiene que estar persistido.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          contarUsuariosProvider.overrideWith((ref) async => 1),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        ],
        child: RisegOneApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_item_telefonia')));
    await tester.pumpAndSettle();
  }

  group('EquiposTelefonicosListScreen — encabezado (Configurar equipo + Regularizar artículo) no desborda', () {
    testWidgets('sesión Maestro, ventana normal (1440×900)', (tester) async {
      await pumpEquiposTelefonicos(tester, size: const Size(1440, 900));
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.equiposTelefonicosListadoTitulo), findsOneWidget);
      expect(find.text(l10n.equiposTelefonicosBotonConfigurar), findsOneWidget);
      expect(find.text(l10n.equiposTelefonicosBotonRegularizar), findsOneWidget, reason: 'Maestro: ambas acciones a la vez');
    });

    testWidgets(
      'sesión Maestro, ancho reducido soportado (850×900) con sidebar forzado expandido — el caso más exigente',
      (tester) async {
        await pumpEquiposTelefonicos(tester, size: const Size(850, 900));
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final texto in [l10n.equiposTelefonicosListadoTitulo, l10n.equiposTelefonicosBotonConfigurar, l10n.equiposTelefonicosBotonRegularizar]) {
          await tester.ensureVisible(find.text(texto));
          expect(find.text(texto).hitTestable(), findsOneWidget, reason: '"$texto" sigue accesible en este ancho');
        }
      },
    );

    testWidgets('sesión Maestro, ancho reducido soportado (850×900) con sidebar colapsado automáticamente', (tester) async {
      await pumpEquiposTelefonicos(tester, size: const Size(850, 900));
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.equiposTelefonicosBotonConfigurar).hitTestable(), findsOneWidget);
      expect(find.text(l10n.equiposTelefonicosBotonRegularizar).hitTestable(), findsOneWidget);
    });
  });
}
