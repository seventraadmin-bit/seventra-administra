// Etapa 14B (Centro de notificaciones) — pruebas de pantalla: la
// campana muestra el conteo real, el panel respeta permisos, sin
// pendientes muestra el mensaje correspondiente, y tocar una
// notificación navega y cierra el panel.

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

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

Future<AppDatabase> _dbConVehiculoVencido() async {
  final db = AppDatabase(NativeDatabase.memory());
  final vehiculo = await db.into(db.vehiculo).insertReturning(
        VehiculoCompanion.insert(
          codigo: 'VH-001',
          marca: 'Nissan',
          modelo: 'NP300',
          tipoVehiculo: 'pickup',
          placas: const Value('ABC-123'),
        ),
      );
  await db.into(db.vehiculoDocumento).insert(
        VehiculoDocumentoCompanion.insert(
          vehiculoId: vehiculo.id,
          tipo: 'verificacion',
          fechaVencimiento: Value(DateTime(2020, 1, 1)),
        ),
      );
  return db;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  SesionController Function() sesion = _SesionMaestroDePrueba.new,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(sesion),
        // `documentoPorEmitirRepositoryProvider` ahora depende de
        // `attachmentStorageProvider` (Etapa 15, eliminación física
        // ampliada) — se sobreescribe directo para no necesitar
        // `appPathsProvider` (requiere `path_provider`).
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Centro de notificaciones — Maestro', () {
    testWidgets('la campana muestra el conteo y el panel el detalle', (tester) async {
      final db = await _dbConVehiculoVencido();
      await _pumpApp(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('notification_bell_badge')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('notification_bell_badge'))).data,
        '1',
        reason: 'badge con el conteo total',
      );

      await tester.tap(find.byKey(const Key('top_bar_notifications')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.notificacionesGrupoVerificacion.toUpperCase()), findsOneWidget);
      expect(find.text('Nissan NP300'), findsOneWidget);
    });

    testWidgets('tocar una notificación navega y cierra el panel', (tester) async {
      final db = await _dbConVehiculoVencido();
      await _pumpApp(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('top_bar_notifications')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nissan NP300'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text(l10n.notificacionesGrupoVerificacion.toUpperCase()),
        findsNothing,
        reason: 'el panel debe cerrarse tras navegar',
      );
    });
  });

  group('Centro de notificaciones — sin datos pendientes', () {
    testWidgets('sin badge y el panel muestra el mensaje de vacío', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _pumpApp(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.byKey(const Key('top_bar_notifications')), findsOneWidget);

      await tester.tap(find.byKey(const Key('top_bar_notifications')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.notificacionesSinPendientes), findsOneWidget);
    });
  });

  group('Centro de notificaciones — RRHH (personal.ver únicamente)', () {
    testWidgets('nunca ve el grupo de Verificación (sin vehiculos.ver)', (tester) async {
      final db = await _dbConVehiculoVencido();
      await _pumpApp(tester, db: db, sesion: _SesionRrhhDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('top_bar_notifications')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.notificacionesGrupoVerificacion.toUpperCase()), findsNothing);
      expect(find.text(l10n.notificacionesSinPendientes), findsOneWidget);
    });
  });
}
