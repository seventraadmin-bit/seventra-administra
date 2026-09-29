// Etapa 12A (Reportes generales) — pruebas de pantalla: visibilidad de
// pestañas por permiso (capa cosmética) y la guardia real en el punto
// de carga de datos (capa de seguridad — nunca solo esconder la
// pestaña). `reportes.ver` ya gatea el módulo completo a nivel router
// (11B); estas pruebas cubren el gap real encontrado en la auditoría:
// `permisoRequeridoParaRuta` solo exige `reportes.ver` para CUALQUIER
// subruta de `/reportes/...`, nunca el permiso de dominio (ej.
// `finanzas.ver`) — así que la barrera real tiene que vivir en el
// controller de cada pestaña, no solo en qué pestaña se muestra.

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

/// RRHH: puede entrar a Reportes y ver Personal, pero no Finanzas —
/// exactamente el ejemplo del punto 15 del pedido de Marlon.
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

/// Solo `reportes.ver`, ningún permiso de dominio — el caso límite de
/// "sin ninguna sección autorizada".
class _SesionSoloReportesDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-solo-reportes',
      nombre: 'Solo reportes',
      nombreUsuario: 'soloreportes',
      esMaestro: false,
      permisos: {'reportes.ver'},
    );
  }
}

Future<GoRouter> _pumpAppEnReportes(
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
  await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-solo-reportes', nombre: 'Solo reportes', nombreUsuario: 'soloreportes', esMaestro: false, permisos: {'reportes.ver'}, ));
  addTearDown(db.close);
  final router = createAppRouter();

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
      child: RisegOneApp(router: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_reportes')));
  await tester.pumpAndSettle();

  return router;
}

void main() {
  group('ReportesShellScreen — sesión Maestro ve todas las pestañas', () {
    testWidgets('/reportes redirige a /reportes/general con el resumen consolidado', (tester) async {
      final router = await _pumpAppEnReportes(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/reportes/general');
      expect(find.text(l10n.reportesTabGeneral), findsOneWidget);
      // "Finanzas" también es el nombre del módulo en el sidebar — se
      // busca específicamente el `Tab` de la franja de pestañas, no
      // cualquier texto "Finanzas" en pantalla.
      expect(find.widgetWithText(Tab, l10n.reportesTabFinanzas), findsOneWidget, reason: 'Maestro ve ambas pestañas');
      expect(find.text(l10n.reportesGeneralIngresos), findsOneWidget);
      expect(find.text(l10n.reportesGeneralPersonalActivo), findsOneWidget);
    });

    testWidgets('la pestaña Finanzas carga sin excepción y muestra sus indicadores', (tester) async {
      await _pumpAppEnReportes(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.widgetWithText(Tab, l10n.reportesTabFinanzas));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesFinanzasPagosRecibidos), findsOneWidget);
      expect(find.text(l10n.reportesFinanzasAntiguedadTitulo), findsOneWidget);
      // El bloque de egresos por origen ahora es la gráfica de
      // composición del gasto, no una lista de textos sueltos.
      expect(find.text(l10n.reportesFinanzasComposicionTitulo), findsOneWidget);
      expect(find.text(l10n.reportesFinanzasFinanciamientoTitulo), findsOneWidget);
    });
  });

  group('ReportesShellScreen — permisos granulares (RRHH: personal.ver sin finanzas.ver)', () {
    testWidgets('la pestaña Finanzas no se muestra, y General solo expone la tarjeta de Personal', (tester) async {
      await _pumpAppEnReportes(tester, sesion: _SesionRrhhDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesTabGeneral), findsOneWidget);
      expect(find.text(l10n.reportesTabFinanzas), findsNothing, reason: 'sin finanzas.ver, la pestaña no debe mostrarse');

      expect(find.text(l10n.reportesGeneralPersonalActivo), findsOneWidget);
      expect(find.text(l10n.reportesGeneralIngresos), findsNothing, reason: 'sin finanzas.ver, nunca se muestra Ingresos');
      expect(find.text(l10n.reportesGeneralGastoOperativo), findsNothing);
      expect(find.text(l10n.reportesGeneralCompras), findsNothing, reason: 'sin compras.ver');
      expect(find.text(l10n.reportesGeneralServiciosActivos), findsNothing, reason: 'sin comercial.ver');
    });

    testWidgets(
      'navegar directamente a /reportes/finanzas (bookmark obsoleto) no expone datos financieros — '
      'la guardia real vive en el controller, no solo en la pestaña oculta',
      (tester) async {
        final router = await _pumpAppEnReportes(tester, sesion: _SesionRrhhDePrueba.new);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        // `permisoRequeridoParaRuta` solo exige `reportes.ver` para
        // cualquier subruta — navegar directo a /reportes/finanzas no
        // lo bloquea el router. La pantalla debe seguir sin exponer
        // ninguna cifra financiera real.
        router.go('/reportes/finanzas');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(l10n.reportesSinSeccionesTitulo), findsOneWidget);
        expect(find.text(l10n.reportesFinanzasPagosRecibidos), findsNothing);
        expect(find.textContaining('\$'), findsNothing, reason: 'ninguna cifra en pesos debe renderizarse sin autorización');
      },
    );
  });

  group('ReportesShellScreen — sin ninguna sección autorizada', () {
    testWidgets('General muestra el estado "sin secciones disponibles", sin excepción', (tester) async {
      await _pumpAppEnReportes(tester, sesion: _SesionSoloReportesDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesTabFinanzas), findsNothing);
      expect(find.text(l10n.reportesSinSeccionesTitulo), findsOneWidget);
    });
  });

  group('ReportesShellScreen — periodo/base de datos vacíos', () {
    testWidgets('Maestro sin ningún dato sembrado: cifras en cero, sin excepción', (tester) async {
      await _pumpAppEnReportes(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining(r'$0.00'), findsWidgets);
    });
  });
}
