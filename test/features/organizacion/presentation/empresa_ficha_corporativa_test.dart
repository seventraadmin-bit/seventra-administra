// Etapa 16, tercera pasada visual — Empresa como ficha corporativa:
// logo protagónico + identidad en una sola cabecera (sin la extinta
// tarjeta "Logotipo institucional" duplicada), resumen fiscal/contacto/
// domicilio legible en consulta, "Tarjeta fiscal" sigue accesible, y
// responsive/tema oscuro sin overflow.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, {Size tamano = const Size(1200, 900), ThemeData? tema}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: tema ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EmpresaExpedienteScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('la cabecera muestra el logo, el nombre comercial y no hay una tarjeta "Logotipo" separada', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.byWidgetPredicate((w) => w is Image && (w.image as AssetImage).assetName == 'assets/images/logo.png'), findsOneWidget);
    expect(find.text('Seguridad Privada RISEG'), findsOneWidget);
    expect(find.text(l10n.empresaSeccionLogotipoTitulo), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consulta muestra "Información fiscal"/"Contacto"/"Domicilio fiscal" y "Tarjeta fiscal" sigue accesible', (tester) async {
    await _pumpScreen(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.empresaSeccionInformacionFiscalTitulo), findsOneWidget);
    expect(find.text(l10n.empresaSeccionContactoTitulo), findsOneWidget);
    expect(find.text(l10n.empresaSeccionDireccionFiscalTitulo), findsOneWidget);
    expect(find.byKey(const Key('empresa_expediente_boton_tarjeta_fiscal')), findsOneWidget);

    await tester.tap(find.byKey(const Key('empresa_expediente_boton_tarjeta_fiscal')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tarjetaFiscalBloqueadaTitulo), findsOneWidget, reason: 'Empresa sembrada sin razón social/RFC/domicilio — debe bloquear con mensaje claro');
  });

  testWidgets('domicilio con datos capturados se muestra como dirección legible, con "Ver dirección completa" si hay referencias', (tester) async {
    // Completa razón social/RFC/domicilio (con referencias) directo en BD,
    // mismo criterio que otras pruebas de este módulo — sin pasar por el
    // flujo de edición completo, que ya tiene su propia cobertura.
    final empresa = await (db.select(db.empresa)..where((t) => t.cicloVidaRegistro.equals('activo'))).getSingle();
    await (db.update(db.empresa)..where((t) => t.id.equals(empresa.id))).write(
      const EmpresaCompanion(razonSocial: Value('Razón Social S.A. de C.V.'), rfc: Value('RSC123456AB1')),
    );
    await db.into(db.direccion).insert(
          DireccionCompanion.insert(
            empresaId: Value(empresa.id),
            tipoDireccion: 'fiscal',
            calle: 'Valle de los Reyes',
            numeroExterior: '2',
            numeroInterior: const Value('9'),
            colonia: 'Valle del Nevado',
            municipioAlcaldia: 'Calimaya',
            estado: 'Estado de México',
            codigoPostal: '52224',
            referencias: const Value('Entre calles Reforma y Juárez'),
          ),
        );

    await _pumpScreen(tester, db);

    expect(find.text('Valle de los Reyes 2 INT. 9'), findsOneWidget);
    expect(find.text('C.P. 52224'), findsOneWidget);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.empresaVerDireccionCompleta), findsOneWidget);
    expect(find.text('Entre calles Reforma y Juárez'), findsNothing);

    await tester.tap(find.text(l10n.empresaVerDireccionCompleta));
    await tester.pumpAndSettle();
    expect(find.text('Entre calles Reforma y Juárez'), findsOneWidget);
  });

  group('responsive y tema', () {
    for (final tamano in const [Size(1366, 900), Size(1024, 900), Size(700, 900), Size(500, 900)]) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await _pumpScreen(tester, db, tamano: tamano);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('modo oscuro: cero overflow', (tester) async {
      await _pumpScreen(tester, db, tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });
}
