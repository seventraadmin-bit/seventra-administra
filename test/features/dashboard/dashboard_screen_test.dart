// Etapa 13 (Dashboard) — pruebas de pantalla: dinámico por permisos
// (misma filosofía que Reportes), estado vacío real cuando no hay
// pendientes, accesos rápidos gateados por su propio permiso de
// acción, y responsive básico (sidebar colapsado/ventana reducida).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
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
      permisos: {'personal.ver', 'personal.crear'},
    );
  }
}

class _SesionFinanzasDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-finanzas',
      nombre: 'Finanzas de prueba',
      nombreUsuario: 'finanzas',
      esMaestro: false,
      permisos: {'finanzas.ver'},
    );
  }
}

class _SesionComprasDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-compras',
      nombre: 'Compras de prueba',
      nombreUsuario: 'compras',
      esMaestro: false,
      permisos: {'compras.ver', 'compras.crear'},
    );
  }
}

class _SesionInventarioDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-inventario',
      nombre: 'Inventario de prueba',
      nombreUsuario: 'inventario',
      esMaestro: false,
      permisos: {'inventario.ver'},
    );
  }
}

/// Sin ningún permiso de dominio ni de acción — el caso límite: llega
/// a `/dashboard` (no exige permiso propio) pero no debería ver ni un
/// solo bloque ni un solo acceso rápido.
class _SesionSinPermisosDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-sin-permisos',
      nombre: 'Sin permisos',
      nombreUsuario: 'sinpermisos',
      esMaestro: false,
      permisos: {},
    );
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  SesionController Function() sesion = _SesionMaestroDePrueba.new,
  Size tamano = const Size(1440, 900),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});

  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-rrhh', nombre: 'RRHH de prueba', nombreUsuario: 'rrhh', esMaestro: false, permisos: {'personal.ver', 'personal.crear'}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-finanzas', nombre: 'Finanzas de prueba', nombreUsuario: 'finanzas', esMaestro: false, permisos: {'finanzas.ver'}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-compras', nombre: 'Compras de prueba', nombreUsuario: 'compras', esMaestro: false, permisos: {'compras.ver', 'compras.crear'}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-inventario', nombre: 'Inventario de prueba', nombreUsuario: 'inventario', esMaestro: false, permisos: {'inventario.ver'}, ));
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-sin-permisos', nombre: 'Sin permisos', nombreUsuario: 'sinpermisos', esMaestro: false, permisos: {}, ));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
        // Etapa 20: el Dashboard ahora también lee
        // `documentoPorEmitirRepositoryProvider` (alerta de documentos
        // por emitir) — ese provider depende de `attachmentStorageProvider`,
        // que a su vez requiere `appPathsProvider`/`path_provider`
        // (no disponible bajo `flutter test`). Mismo criterio ya usado
        // en las pruebas de Agenda.
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DashboardScreen — Maestro, base de datos vacía', () {
    testWidgets('carga sin excepción y muestra el estado vacío de Atención', (tester) async {
      await _pumpDashboard(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);
      expect(find.text(l10n.dashboardSinPendientesTitulo), findsOneWidget);
    });
  });

  group('DashboardScreen — RRHH (personal.ver, sin finanzas.ver)', () {
    testWidgets('ve Personal, nunca ve Finanzas', (tester) async {
      await _pumpDashboard(tester, sesion: _SesionRrhhDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      // "Personal" a secas colisiona con el ítem del sidebar — se
      // verifica con una etiqueta exclusiva del bloque nuevo.
      expect(find.text(l10n.dashboardPersonalAsignados), findsOneWidget);
      expect(find.text(l10n.reportesGeneralIngresos), findsNothing, reason: 'sin finanzas.ver, Finanzas nunca debe aparecer');
      expect(find.text(l10n.reportesGeneralGastoOperativo), findsNothing);
      expect(find.text(l10n.dashboardAlertaCxcVencida), findsNothing);
      expect(find.text(l10n.dashboardAccesoAltaPersonal), findsOneWidget, reason: 'tiene personal.crear');
      expect(find.text(l10n.dashboardAccesoRegistrarCompra), findsNothing, reason: 'no tiene compras.crear');
    });
  });

  group('DashboardScreen — sesión con solo finanzas.ver', () {
    testWidgets('nunca ve ningún bloque de Personal', (tester) async {
      await _pumpDashboard(tester, sesion: _SesionFinanzasDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.dashboardPersonalTitulo), findsNothing);
      expect(find.text(l10n.dashboardActividadAltas), findsNothing);
      expect(find.text(l10n.dashboardActividadBajas), findsNothing);
      expect(find.text(l10n.dashboardAlertaEmpleadosBajaPendiente), findsNothing);
    });
  });

  group('DashboardScreen — sesión con solo compras.ver/compras.crear', () {
    testWidgets('Dashboard útil: ve Compras del mes, actividad de Compras y el acceso rápido', (tester) async {
      await _pumpDashboard(tester, sesion: _SesionComprasDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      // Etapa 15 (rediseño visual): "Compras del periodo" ahora se
      // muestra junto con su valor en un solo texto ("Compras del
      // periodo · $0.00"), y la Actividad reciente ahora es una sola
      // lista unificada (nunca una tarjeta "Compras recientes" aparte).
      expect(find.textContaining(l10n.reportesGeneralCompras), findsOneWidget);
      expect(find.text(l10n.dashboardSeccionActividad), findsOneWidget);
      expect(find.text(l10n.dashboardAccesoRegistrarCompra), findsOneWidget);
      expect(find.text(l10n.reportesGeneralPersonalActivo), findsNothing);
      expect(find.text(l10n.reportesGeneralIngresos), findsNothing);
    });
  });

  group('DashboardScreen — sesión con solo inventario.ver', () {
    testWidgets('ve el acceso rápido a Inventario, nunca Existencia total/Asignaciones vigentes como KPI', (tester) async {
      await _pumpDashboard(tester, sesion: _SesionInventarioDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      // Etapa 15 (rediseño gerencial): Existencia total/Asignaciones
      // vigentes dejan de ser KPI del Dashboard (Parte A) — Inventario
      // solo ocupa espacio cuando hay una excepción real (Parte L), y
      // esta base de datos vacía no tiene ninguna.
      expect(find.text(l10n.reportesInventarioExistencia), findsNothing);
      expect(find.text(l10n.reportesInventarioAsignaciones), findsNothing);
      expect(find.text(l10n.dashboardAccesoInventario), findsOneWidget);
    });
  });

  group('DashboardScreen — sesión sin ningún permiso', () {
    testWidgets('llega a /dashboard sin excepción, sin accesos rápidos y sin ningún bloque', (tester) async {
      await _pumpDashboard(tester, sesion: _SesionSinPermisosDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);
      expect(find.text(l10n.dashboardAccesoAltaPersonal), findsNothing);
      expect(find.text(l10n.dashboardAccesoRegistrarCompra), findsNothing);
      expect(find.text(l10n.dashboardAccesoGenerarNomina), findsNothing);
      expect(find.text(l10n.dashboardAccesoInventario), findsNothing);
      expect(find.text(l10n.dashboardSinPendientesTitulo), findsOneWidget);
    });
  });

  group('DashboardScreen — responsive', () {
    testWidgets('ventana de ancho reducido, sin excepción', (tester) async {
      await _pumpDashboard(tester, tamano: const Size(700, 900));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);
    });

    testWidgets('ventana de altura reducida (sidebar auto-colapsado), sin excepción', (tester) async {
      await _pumpDashboard(tester, tamano: const Size(1440, 500));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);
    });
  });
}
