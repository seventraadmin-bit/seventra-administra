// Etapa 12B (Reportes generales — Personal · Nómina) — pruebas de
// pantalla: la subsección Personal nunca muestra una cifra en pesos
// (regla de diseño explícita), un usuario con solo personal.ver no ve
// la subsección Nómina y viceversa, Maestro ve ambas, y la pestaña
// completa se oculta solo cuando faltan los dos permisos a la vez.

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
      permisos: {'reportes.ver', 'personal.ver'},
    );
  }
}

/// Usuario de Nómina — el caso simétrico opuesto a RRHH.
class _SesionNominaDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-nomina',
      nombre: 'Nómina de prueba',
      nombreUsuario: 'nomina',
      esMaestro: false,
      permisos: {'reportes.ver', 'nomina.ver'},
    );
  }
}

Future<void> _pumpAppEnPersonalNomina(
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
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-rrhh', nombre: 'RRHH de prueba', nombreUsuario: 'rrhh', esMaestro: false, permisos: {'reportes.ver', 'personal.ver'}, ));
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-nomina', nombre: 'Nómina de prueba', nombreUsuario: 'nomina', esMaestro: false, permisos: {'reportes.ver', 'nomina.ver'}, ));
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

  await tester.tap(find.byKey(const Key('nav_item_reportes')));
  await tester.pumpAndSettle();

  final l10n = await AppLocalizations.delegate.load(const Locale('es'));
  await tester.tap(find.widgetWithText(Tab, l10n.reportesTabPersonalNomina));
  await tester.pumpAndSettle();
}

void main() {
  group('ReportesPersonalNominaScreen — Maestro ve ambas subsecciones', () {
    testWidgets('Personal y Nómina cargan sin excepción', (tester) async {
      await _pumpAppEnPersonalNomina(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesPersonalSeccionTitulo), findsWidgets, reason: '"Personal" también es el nombre del módulo en el sidebar');
      expect(find.text(l10n.reportesPersonalActivos), findsOneWidget);
      expect(find.text(l10n.reportesNominaSeccionTitulo), findsOneWidget);
      expect(find.text(l10n.reportesNominaTotalGenerado), findsOneWidget);
    });
  });

  group('ReportesPersonalNominaScreen — RRHH (personal.ver sin nomina.ver)', () {
    testWidgets('ve Personal completo, cero cifras de Nómina, y ninguna tarjeta de Personal muestra un monto en pesos', (tester) async {
      await _pumpAppEnPersonalNomina(tester, sesion: _SesionRrhhDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesPersonalSeccionTitulo), findsWidgets, reason: '"Personal" también es el nombre del módulo en el sidebar');
      expect(find.text(l10n.reportesPersonalActivos), findsOneWidget);
      expect(find.text(l10n.reportesNominaSeccionTitulo), findsNothing, reason: 'sin nomina.ver, la subsección no debe aparecer');
      expect(find.text(l10n.reportesNominaTotalGenerado), findsNothing);
      expect(find.text(l10n.reportesNominaTotalPagado), findsNothing);
      expect(find.textContaining('\$'), findsNothing, reason: 'Personal nunca muestra una cifra en pesos');
    });
  });

  group('ReportesPersonalNominaScreen — usuario de Nómina (nomina.ver sin personal.ver)', () {
    testWidgets('ve Nómina completo, cero secciones de Personal', (tester) async {
      await _pumpAppEnPersonalNomina(tester, sesion: _SesionNominaDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesNominaSeccionTitulo), findsOneWidget);
      expect(find.text(l10n.reportesNominaTotalGenerado), findsOneWidget);
      expect(find.text(l10n.reportesPersonalSeccionTitulo), findsNothing, reason: 'sin personal.ver, la subsección no debe aparecer');
      expect(find.text(l10n.reportesPersonalActivos), findsNothing);
    });
  });
}
