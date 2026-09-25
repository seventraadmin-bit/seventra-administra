// Etapa 4D — la sección "Recuperación en otro equipo".
//
// Se comprueban dos cosas distintas: que ofrece lo correcto según si la
// recuperación está preparada o no, y que no desborda en ninguno de los
// anchos que esta aplicación tiene que soportar. Lo segundo importa porque
// son cinco botones con etiquetas largas en español: el caso obvio de
// desbordamiento horizontal.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/respaldo/domain/portable/configuracion_recuperacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/contenedor_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/kdf_portable.dart';
import 'package:riseg_one/features/respaldo/portable_providers.dart';
import 'package:riseg_one/features/respaldo/presentation/widgets/seccion_recuperacion_portable.dart';

/// Una configuración cualquiera: la sección sólo lee la fecha de la clave,
/// así que las envolturas pueden ser de relleno.
ConfiguracionRecuperacion _configuracionDePrueba() {
  Uint8List relleno(int n) => Uint8List.fromList(List<int>.generate(n, (i) => i & 0xff));

  EnvolturaMwk envoltura(TipoEnvoltura tipo) => EnvolturaMwk(
    tipo: tipo,
    salt: relleno(16),
    nonce: relleno(12),
    cifrado: relleno(EnvolturaMwk.longitudCifrado),
    parametrosArgon2:
        tipo == TipoEnvoltura.frase
            ? ParametrosArgon2id(memoriaKiB: 65536, iteraciones: 3, paralelismo: 1, salt: relleno(16))
            : null,
  );

  return ConfiguracionRecuperacion(
    backupSetId: 'aabbccddeeff00112233445566778899',
    formatoVersion: ConfiguracionRecuperacion.formatoActual,
    envolturaFrase: envoltura(TipoEnvoltura.frase),
    envolturaClaveRecuperacion: envoltura(TipoEnvoltura.claveRecuperacion),
    claveRecuperacionGeneradaEn: DateTime(2026, 9, 24, 10, 30),
  );
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Size tamano,
    required Brightness brillo,
    required ConfiguracionRecuperacion? configuracion,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [configuracionRecuperacionProvider.overrideWith((ref) async => configuracion)],
        child: MaterialApp(
          theme: brillo == Brightness.light ? AppTheme.light() : AppTheme.dark(),
          locale: const Locale('es'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es')],
          home: const Scaffold(
            body: SingleChildScrollView(padding: EdgeInsets.all(AppSpacing.xl), child: SeccionRecuperacionPortable()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Qué ofrece según el estado', () {
    testWidgets('sin preparar: se ofrece prepararla y TAMBIÉN recuperar', (tester) async {
      await pump(tester, tamano: const Size(1366, 768), brillo: Brightness.light, configuracion: null);

      expect(find.byKey(const Key('portable_boton_preparar')), findsOneWidget);
      // Ésta es la que importa: en un equipo nuevo no hay nada preparado, y
      // si el botón de recuperar no estuviera aquí, el respaldo que trae el
      // usuario en su USB no tendría por dónde entrar.
      expect(find.byKey(const Key('portable_boton_recuperar_sin_preparar')), findsOneWidget);
      expect(find.byKey(const Key('portable_boton_crear')), findsNothing);
    });

    testWidgets('preparada: aparecen las cinco acciones y la fecha de la clave', (tester) async {
      await pump(
        tester,
        tamano: const Size(1366, 768),
        brillo: Brightness.light,
        configuracion: _configuracionDePrueba(),
      );

      expect(find.byKey(const Key('portable_boton_crear')), findsOneWidget);
      expect(find.byKey(const Key('portable_boton_revisar')), findsOneWidget);
      expect(find.byKey(const Key('portable_boton_recuperar')), findsOneWidget);
      expect(find.byKey(const Key('portable_boton_cambiar_frase')), findsOneWidget);
      expect(find.byKey(const Key('portable_boton_regenerar_clave')), findsOneWidget);
      expect(find.textContaining('24/09/2026'), findsOneWidget);
    });

    testWidgets('NUNCA aparece jerga técnica en pantalla', (tester) async {
      await pump(
        tester,
        tamano: const Size(1366, 768),
        brillo: Brightness.light,
        configuracion: _configuracionDePrueba(),
      );

      // La lista es la del propio encargo. No se busca "clave" a secas
      // porque "clave de recuperación" es justamente el nombre bueno.
      for (final prohibida in ['DEK', 'MWK', 'KDF', 'Argon', 'AES', 'payload', 'keyId', 'ranura']) {
        expect(
          find.textContaining(prohibida, findRichText: true),
          findsNothing,
          reason: 'la palabra "$prohibida" no le dice nada a quien usa esto',
        );
      }
      // Tampoco se promete lo que no se puede garantizar sobre un disco.
      for (final prohibida in ['irrecuperable', 'de forma segura']) {
        expect(find.textContaining(prohibida, findRichText: true), findsNothing);
      }
    });
  });

  group('Sin desbordes en ningún ancho', () {
    for (final tamano in [const Size(1366, 768), const Size(1024, 700), const Size(700, 700), const Size(500, 700)]) {
      for (final brillo in [Brightness.light, Brightness.dark]) {
        testWidgets('preparada a ${tamano.width.toInt()} px, ${brillo.name}', (tester) async {
          await pump(tester, tamano: tamano, brillo: brillo, configuracion: _configuracionDePrueba());
          expect(tester.takeException(), isNull);
        });

        testWidgets('sin preparar a ${tamano.width.toInt()} px, ${brillo.name}', (tester) async {
          await pump(tester, tamano: tamano, brillo: brillo, configuracion: null);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
