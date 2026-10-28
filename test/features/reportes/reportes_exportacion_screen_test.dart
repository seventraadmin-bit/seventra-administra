// Etapa 12D (Reportes generales — Exportación) — pruebas de pantalla:
// los botones de exportación solo aparecen donde ya aparecía la
// sección correspondiente (mismo permiso, sin comprobación nueva).
// Nunca se toca (`tester.tap`) un botón de exportación real — eso
// invocaría `AttachmentStorage.abrir` (`cmd /c start`, un proceso real
// del sistema operativo) — estas pruebas solo verifican presencia o
// ausencia del botón.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
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

class _SesionSoloReportesDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-reportes',
      nombre: 'Reportes de prueba',
      nombreUsuario: 'reportes',
      esMaestro: false,
      permisos: {'reportes.ver'},
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

Future<void> _pumpAppEnPestana(
  WidgetTester tester, {
  required String etiquetaPestana,
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
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-reportes', nombre: 'Reportes de prueba', nombreUsuario: 'reportes', esMaestro: false, permisos: {'reportes.ver'}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-rrhh', nombre: 'RRHH de prueba', nombreUsuario: 'rrhh', esMaestro: false, permisos: {'reportes.ver', 'personal.ver'}, ));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
        // Etapa B: la pestaña Finanzas ahora resuelve Servicio y
        // Entidad fiscal de cada CxC vía `DocumentoPorEmitirRepository`,
        // que arrastra `attachmentStorageProvider` (sin `path_provider`
        // bajo `flutter test`).
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_reportes')));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(Tab, etiquetaPestana));
  await tester.pumpAndSettle();
}

/// Navega directamente por ruta (sin tocar la pestaña) — prueba la
/// guardia real del controller, no solo la capa cosmética de
/// `ReportesShellScreen` que oculta la pestaña. Necesario para
/// sesiones que, precisamente por no tener el permiso, nunca podrían
/// llegar tocando la pestaña (no existe).
Future<void> _pumpAppEnRuta(
  WidgetTester tester, {
  required String ruta,
  required SesionController Function() sesion,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});

  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-reportes', nombre: 'Reportes de prueba', nombreUsuario: 'reportes', esMaestro: false, permisos: {'reportes.ver'}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-rrhh', nombre: 'RRHH de prueba', nombreUsuario: 'rrhh', esMaestro: false, permisos: {'reportes.ver', 'personal.ver'}, ));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
        // Etapa B: la pestaña Finanzas ahora resuelve Servicio y
        // Entidad fiscal de cada CxC vía `DocumentoPorEmitirRepository`,
        // que arrastra `attachmentStorageProvider` (sin `path_provider`
        // bajo `flutter test`).
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go(ruta);
  await tester.pumpAndSettle();
}

void main() {
  group('Reporte General — botón de exportación', () {
    testWidgets('Maestro ve "Exportar PDF"', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _pumpAppEnPestana(tester, etiquetaPestana: l10n.reportesTabGeneral);

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesExportarPdf), findsOneWidget);
    });
  });

  group('Reporte Finanzas — botón de exportación gateado por finanzas.ver', () {
    testWidgets('sesión sin finanzas.ver no ve ningún botón de exportación', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _pumpAppEnRuta(
        tester,
        ruta: '/reportes/finanzas',
        sesion: _SesionSoloReportesDePrueba.new,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesSinSeccionesTitulo), findsOneWidget);
      expect(find.text(l10n.reportesExportarPdf), findsNothing);
      expect(find.text(l10n.reportesExportarExcel), findsNothing);
    });

    testWidgets('Maestro ve "Exportar PDF" y "Exportar Excel"', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _pumpAppEnPestana(tester, etiquetaPestana: l10n.reportesTabFinanzas);

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesExportarPdf), findsOneWidget);
      expect(find.text(l10n.reportesExportarExcel), findsOneWidget);
    });
  });

  group('Personal · Nómina — exportación independiente por subsección', () {
    testWidgets('RRHH (personal.ver sin nomina.ver) ve un solo botón "Exportar Excel" (Personal)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _pumpAppEnPestana(
        tester,
        etiquetaPestana: l10n.reportesTabPersonalNomina,
        sesion: _SesionRrhhDePrueba.new,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesExportarExcel), findsOneWidget, reason: 'sin nomina.ver, el botón de Nómina no debe aparecer');
    });

    testWidgets('Maestro ve dos botones "Exportar Excel" (Personal y Nómina)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _pumpAppEnPestana(tester, etiquetaPestana: l10n.reportesTabPersonalNomina);

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesExportarExcel), findsNWidgets(2));
    });
  });

  group('Operación — exportación independiente por bloque, Inventario sin botón', () {
    testWidgets('Maestro ve tres botones "Exportar Excel" (Compras, Vehículos, Telefonía)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _pumpAppEnPestana(tester, etiquetaPestana: l10n.reportesTabOperacion);

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesExportarExcel), findsNWidgets(3));
    });
  });
}
