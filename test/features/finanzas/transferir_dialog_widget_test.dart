// El diálogo real de Transferir: que el recorrido completo funcione y
// que un saldo insuficiente NO cierre el formulario.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'MARLON',
        nombreUsuario: 'MARLONRH',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // El evento de auditoria sella `actorUsuarioId`: sin la fila del
    // Usuario, la insercion muere por llave foranea.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'MARLONRH',
            passwordHash: r'pbkdf2\====',
            esMaestro: const Value(true),
          ),
        );
    await db.into(db.cuentaFinanciera).insert(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0001',
            // El selector lista por nombre, así que ésta queda de origen.
            nombre: 'Aurora Origen',
            tipo: 'banco',
            saldoInicial: 500000,
            fechaSaldoInicial: DateTime(2020, 1, 1),
          ),
        );
    await db.into(db.cuentaFinanciera).insert(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0002',
            nombre: 'Zeta Destino',
            tipo: 'banco',
            saldoInicial: 0,
            fechaSaldoInicial: DateTime(2020, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CuentasFinancierasListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boton = find.byKey(const Key('cuentas_financieras_boton_transferir'));
    expect(boton, findsOneWidget, reason: 'Transferir vive junto a las cuentas, no en un módulo nuevo');
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  /// Elige una cuenta en un selector. El sistema NO elige por el
  /// usuario, así que sin esto no hay ni origen ni destino.
  Future<void> elegir(WidgetTester tester, Key selector, String nombreCuenta) async {
    await tester.tap(find.byKey(selector));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(nombreCuenta).last);
    await tester.pumpAndSettle();
  }

  testWidgets('transferir con saldo: registra y cierra', (tester) async {
    await abrir(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await elegir(tester, const Key('transferir_origen'), 'Aurora Origen');
    await elegir(tester, const Key('transferir_destino'), 'Zeta Destino');

    await tester.enterText(find.byKey(const Key('transferir_importe')), '3000.00');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RisegButton, l10n.transferirConfirmar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.transferirTitulo), findsNothing, reason: 'el diálogo cierra al registrar');
    final registradas = await db.select(db.transferenciaCuenta).get();
    expect(registradas, hasLength(1));
    expect(registradas.single.importe, 300000);
    expect(await db.select(db.ingreso).get(), isEmpty, reason: 'nunca un Ingreso');
    expect(await db.select(db.egreso).get(), isEmpty, reason: 'nunca un Egreso');
  });

  testWidgets('sin saldo: el diálogo NO cierra y muestra el faltante', (tester) async {
    await abrir(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await elegir(tester, const Key('transferir_origen'), 'Aurora Origen');
    await elegir(tester, const Key('transferir_destino'), 'Zeta Destino');

    await tester.enterText(find.byKey(const Key('transferir_importe')), '9000.00');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RisegButton, l10n.transferirConfirmar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.transferirTitulo), findsOneWidget, reason: 'el formulario sigue abierto');
    expect(find.byKey(const Key('transferir_error')), findsOneWidget);
    expect(await db.select(db.transferenciaCuenta).get(), isEmpty);
  });

  testWidgets('no elige cuenta por el usuario: sin selección no se registra nada', (tester) async {
    await abrir(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Ni origen ni destino vienen preseleccionados.
    expect(find.text(l10n.selectorCuentaPlaceholder), findsNWidgets(2));

    await tester.enterText(find.byKey(const Key('transferir_importe')), '1000.00');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RisegButton, l10n.transferirConfirmar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.transferirTitulo), findsOneWidget, reason: 'el formulario sigue abierto');
    expect(await db.select(db.transferenciaCuenta).get(), isEmpty);
  });

  testWidgets('el selector muestra el saldo de cada cuenta', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('transferir_origen')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aurora Origen').first, findsOneWidget);
    expect(find.textContaining(r'$5,000.00').first, findsOneWidget,
        reason: 'elegir de dónde sale el dinero sin ver cuánto hay es adivinar');
  });
}
