// Etapa 12C (Reportes generales — Operación) — pruebas de pantalla:
// cada bloque (Compras/Inventario/Vehículos/Telefonía) se omite por
// completo si falta su permiso, Maestro ve los 4, y la pestaña
// completa solo se oculta cuando faltan los 4 permisos a la vez.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _SesionSoloComprasDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-compras',
      nombre: 'Compras de prueba',
      nombreUsuario: 'compras',
      esMaestro: false,
      permisos: {'reportes.ver', 'compras.ver'},
    );
  }
}

/// Inventario sin Telefonía — el caso explícito pedido: confirma que
/// el bloque de Telefonía no aparece cuando falta `telefonia.ver`.
class _SesionInventarioSinTelefoniaDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-inventario',
      nombre: 'Inventario de prueba',
      nombreUsuario: 'inventario',
      esMaestro: false,
      permisos: {'reportes.ver', 'inventario.ver'},
    );
  }
}

Future<void> _pumpAppEnOperacion(
  WidgetTester tester, {
  SesionController Function() sesion = _SesionMaestroDePrueba.new,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});

  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-compras', nombre: 'Compras de prueba', nombreUsuario: 'compras', esMaestro: false, permisos: {'reportes.ver', 'compras.ver'}, ));
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-inventario', nombre: 'Inventario de prueba', nombreUsuario: 'inventario', esMaestro: false, permisos: {'reportes.ver', 'inventario.ver'}, ));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(sesion),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_reportes')));
  await tester.pumpAndSettle();

  final l10n = await AppLocalizations.delegate.load(const Locale('es'));
  await tester.tap(find.widgetWithText(Tab, l10n.reportesTabOperacion));
  await tester.pumpAndSettle();
}

void main() {
  group('ReportesOperacionScreen — Maestro ve los 4 bloques', () {
    testWidgets('Compras, Inventario, Vehículos y Telefonía cargan sin excepción', (tester) async {
      await _pumpAppEnOperacion(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesComprasSeccionTitulo), findsWidgets, reason: '"Compras" también es el nombre del módulo en el sidebar');
      expect(find.text(l10n.reportesInventarioSeccionTitulo), findsWidgets, reason: '"Inventario" también es el nombre del módulo en el sidebar');
      expect(find.text(l10n.reportesVehiculosSeccionTitulo), findsWidgets, reason: '"Vehículos" también es el nombre del módulo en el sidebar');
      expect(find.text(l10n.reportesTelefoniaSeccionTitulo), findsWidgets, reason: '"Telefonía" también es el nombre del módulo en el sidebar');
    });
  });

  group('ReportesOperacionScreen — usuario con solo compras.ver', () {
    testWidgets('ve únicamente el bloque de Compras', (tester) async {
      await _pumpAppEnOperacion(tester, sesion: _SesionSoloComprasDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesComprasSeccionTitulo), findsWidgets, reason: '"Compras" también es el nombre del módulo en el sidebar');
      expect(find.text(l10n.reportesInventarioExistencia), findsNothing);
      expect(find.text(l10n.reportesVehiculosCostoMantenimiento), findsNothing);
      expect(find.text(l10n.reportesTelefoniaTotalRecargas), findsNothing);
    });
  });

  group('ReportesOperacionScreen — usuario con inventario.ver sin telefonia.ver', () {
    testWidgets('ve Inventario, no ve Telefonía', (tester) async {
      await _pumpAppEnOperacion(tester, sesion: _SesionInventarioSinTelefoniaDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesInventarioExistencia), findsOneWidget);
      expect(find.text(l10n.reportesTelefoniaTotalRecargas), findsNothing, reason: 'sin telefonia.ver, el bloque no debe aparecer');
      expect(find.text(l10n.reportesComprasSeccionTitulo), findsNothing);
    });
  });

  group('ReportesOperacionScreen — periodo/base de datos vacíos', () {
    testWidgets('Maestro sin ningún dato sembrado: ceros, sin excepción', (tester) async {
      await _pumpAppEnOperacion(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining(r'$0.00'), findsWidgets);
    });
  });
}
