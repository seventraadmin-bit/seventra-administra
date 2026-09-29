// Etapa 14A (Búsqueda global) — pruebas de pantalla: escribir en el
// campo de la barra superior muestra resultados reales por permiso,
// menos de 2 caracteres no dispara nada, sin coincidencias muestra el
// mensaje correspondiente, tocar un resultado navega, y en modo
// compacto el ícono abre el diálogo en vez del overlay.

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

class _SesionRrhhDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-rrhh',
      nombre: 'RRHH de prueba',
      nombreUsuario: 'rrhh',
      esMaestro: false,
      permisos: {'personal.ver'},
    );
  }
}

Future<AppDatabase> _dbConClienteSembrado() async {
  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-rrhh', nombre: 'RRHH de prueba', nombreUsuario: 'rrhh', esMaestro: false, permisos: {'personal.ver'}, ));
  await db.into(db.cliente).insert(
        ClienteCompanion.insert(codigo: 'CLI-001', nombreComercial: 'Residencial Tikal'),
      );
  return db;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  SesionController Function() sesion = _SesionMaestroDePrueba.new,
  Size tamano = const Size(1440, 900),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _escribirYEsperarDebounce(WidgetTester tester, Finder campo, String texto) async {
  await tester.enterText(campo, texto);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  group('Búsqueda global — Maestro', () {
    testWidgets('escribir 2+ caracteres muestra resultados reales (Cliente sembrado)', (tester) async {
      final db = await _dbConClienteSembrado();
      await _pumpApp(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _escribirYEsperarDebounce(tester, find.byKey(const Key('top_bar_search')), 'Tikal');

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.busquedaGrupoClientes.toUpperCase()), findsOneWidget);
      expect(find.text('Residencial Tikal'), findsOneWidget);
    });

    testWidgets('menos de 2 caracteres no muestra ningún resultado', (tester) async {
      final db = await _dbConClienteSembrado();
      await _pumpApp(tester, db: db);

      await _escribirYEsperarDebounce(tester, find.byKey(const Key('top_bar_search')), 'T');

      expect(tester.takeException(), isNull);
      expect(find.text('Residencial Tikal'), findsNothing);
    });

    testWidgets('sin coincidencias muestra el mensaje "Sin resultados"', (tester) async {
      final db = await _dbConClienteSembrado();
      await _pumpApp(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _escribirYEsperarDebounce(tester, find.byKey(const Key('top_bar_search')), 'zzzzz');

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.busquedaSinResultados('zzzzz')), findsOneWidget);
    });

    testWidgets('tocar un resultado navega al expediente y cierra el overlay', (tester) async {
      final db = await _dbConClienteSembrado();
      await _pumpApp(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _escribirYEsperarDebounce(tester, find.byKey(const Key('top_bar_search')), 'Tikal');
      await tester.tap(find.text('Residencial Tikal').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text(l10n.busquedaGrupoClientes.toUpperCase()),
        findsNothing,
        reason: 'el encabezado de grupo del overlay no debe seguir visible tras navegar',
      );
      final campoBusqueda = tester.widget<TextField>(find.byKey(const Key('top_bar_search')));
      expect(campoBusqueda.controller?.text, isEmpty, reason: 'el campo se limpia tras seleccionar un resultado');
    });
  });

  group('Búsqueda global — RRHH (personal.ver únicamente)', () {
    testWidgets('nunca ve resultados de Clientes (sin comercial.ver)', (tester) async {
      final db = await _dbConClienteSembrado();
      await _pumpApp(tester, db: db, sesion: _SesionRrhhDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _escribirYEsperarDebounce(tester, find.byKey(const Key('top_bar_search')), 'Tikal');

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.busquedaGrupoClientes.toUpperCase()), findsNothing);
      expect(find.text('Residencial Tikal'), findsNothing);
      expect(find.text(l10n.busquedaSinResultados('Tikal')), findsOneWidget);
    });
  });

  group('Búsqueda global — modo compacto', () {
    testWidgets('ventana angosta: el ícono abre el diálogo, no un overlay', (tester) async {
      final db = await _dbConClienteSembrado();
      await _pumpApp(tester, db: db, tamano: const Size(900, 900));

      expect(find.byKey(const Key('top_bar_search')), findsOneWidget);
      await tester.tap(find.byKey(const Key('top_bar_search')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('global_search_dialog_field')), findsOneWidget);

      await _escribirYEsperarDebounce(tester, find.byKey(const Key('global_search_dialog_field')), 'Tikal');
      expect(find.text('Residencial Tikal'), findsOneWidget);
    });
  });
}
