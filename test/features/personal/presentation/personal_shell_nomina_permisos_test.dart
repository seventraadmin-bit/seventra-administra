// Etapa 0 (auditoría de consistencia transversal) — la auditoría
// encontró que el sub-shell de Personal no filtraba su pestaña Nómina
// por permiso: un usuario con `personal.ver` pero sin `nomina.ver`
// podía ver la pestaña y, más grave, entrar directo a `/personal/nomina`
// por ruta (el router solo exige `personal.ver` para cualquier
// `/personal/**`, ver `permisoRequeridoParaRuta`). Estas pruebas cubren
// las dos capas: ocultar la pestaña (cosmética, en `PersonalShellScreen`)
// y bloquear el acceso real a los datos (`NominasController.tieneNomina`),
// mismo patrón que `reportes_shell_screen_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

const _folioSecreto = 'NOM-SECRETA-0001';

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

/// Personal.ver sin nomina.ver — exactamente el caso pedido: puede
/// entrar a Personal, pero no debe ver ni poder abrir Nómina.
class _SesionPersonalSinNominaDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-personal',
      nombre: 'RRHH sin nómina',
      nombreUsuario: 'rrhh-sin-nomina',
      esMaestro: false,
      permisos: {'personal.ver'},
    );
  }
}

Future<void> _sembrarNominaSecreta(AppDatabase db) async {
  await db.into(db.nomina).insert(NominaCompanion.insert(
        id: const Value('nomina-secreta'),
        folio: _folioSecreto,
        anio: 2026,
        mes: 9,
        tipoPeriodo: TipoPeriodoNomina.primera.name,
        fechaInicioPeriodo: DateTime(2026, 9, 1),
        fechaFinPeriodo: DateTime(2026, 9, 15),
        fechaPagoOrdinaria: DateTime(2026, 9, 15),
      ));
}

Future<GoRouter> _pumpAppComoPersonal(
  WidgetTester tester, {
  required AppDatabase db,
  SesionController Function() sesion = _SesionMaestroDePrueba.new,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});

  final router = createAppRouter();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(sesion),
      ],
      child: RisegOneApp(router: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_personal')));
  await tester.pumpAndSettle();

  return router;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrarNominaSecreta(db);
  });

  tearDown(() => db.close());

  group('PersonalShellScreen — sesión Maestro (control positivo)', () {
    testWidgets('ve la pestaña Nómina y, al abrirla, el folio real', (tester) async {
      await _pumpAppComoPersonal(tester, db: db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(Tab, l10n.personalTabNomina), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, l10n.personalTabNomina));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_folioSecreto), findsOneWidget, reason: 'con nomina.ver, el folio real de la Nómina sembrada debe verse');
    });
  });

  group('PersonalShellScreen — personal.ver sin nomina.ver', () {
    testWidgets('puede entrar a Personal, pero no ve la pestaña Nómina', (tester) async {
      await _pumpAppComoPersonal(tester, db: db, sesion: _SesionPersonalSinNominaDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull, reason: 'entrar a Personal no debe lanzar ninguna excepción');
      expect(find.widgetWithText(Tab, l10n.personalTabEmpleados), findsOneWidget, reason: 'Empleados sí es visible con personal.ver');
      expect(find.widgetWithText(Tab, l10n.personalTabNomina), findsNothing, reason: 'sin nomina.ver, la pestaña no debe mostrarse');
    });

    testWidgets(
      'navegar directamente a /personal/nomina (bookmark/URL) no expone el folio real — '
      'la guardia real vive en NominasController, no solo en la pestaña oculta',
      (tester) async {
        final router = await _pumpAppComoPersonal(tester, db: db, sesion: _SesionPersonalSinNominaDePrueba.new);

        // `permisoRequeridoParaRuta` solo exige `personal.ver` para
        // cualquier subruta de `/personal/**` — navegar directo a
        // /personal/nomina no lo bloquea el router. La pantalla debe
        // seguir sin exponer el folio real de la Nómina sembrada.
        router.go('/personal/nomina');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(_folioSecreto), findsNothing, reason: 'sin nomina.ver, el folio real nunca debe renderizarse por ruta directa');
      },
    );

    testWidgets(
      'navegar directamente a /personal/nomina/:id (detalle) no expone la Nómina real',
      (tester) async {
        final router = await _pumpAppComoPersonal(tester, db: db, sesion: _SesionPersonalSinNominaDePrueba.new);

        router.go('/personal/nomina/nomina-secreta');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(_folioSecreto), findsNothing, reason: 'sin nomina.ver, el detalle tampoco debe exponer la Nómina real');
      },
    );
  });
}
