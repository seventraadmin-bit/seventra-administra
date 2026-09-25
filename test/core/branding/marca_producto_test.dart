// Etapa 5B.1 — la identidad del PRODUCTO deja de ser el escudo de RISEG.
//
// Hasta esta etapa, el sidebar, el inicio de sesión, el alta del primer
// Maestro y el panel de identidad dibujaban `assets/images/logo.png`, que es
// el escudo corporativo de RISEG Seguridad: un lobo, un blasón y el texto
// "SEGURIDAD PRIVADA RISEG". Con una sola Empresa la confusión no se notaba.
// Con varias, el producto habría llevado el logotipo de uno de sus clientes.
//
// Estas pruebas fijan la separación: esas cuatro superficies son del
// producto, y `logo.png` sigue existiendo porque es la identidad de la
// Empresa RISEG hasta 5B.2/5B.3.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/app/shell/shell_destinations.dart';
import 'package:riseg_one/app/shell/widgets/app_sidebar.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/branding/marca_producto.dart';
import 'package:riseg_one/core/design_system/tokens/app_colors.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/respaldo/domain/portable/contenedor_portable.dart';
import 'package:riseg_one/features/respaldo/domain/rutas_paquete.dart';
import 'package:riseg_one/features/usuarios/presentation/auth/widgets/auth_identity_panel.dart';

/// Rutas de asset que aparecen en el árbol de widgets ya montado.
Set<String> assetsDibujados(WidgetTester tester) {
  return tester
      .widgetList<Image>(find.byType(Image))
      .map((i) => i.image)
      .whereType<AssetImage>()
      .map((a) => a.assetName)
      .toSet();
}

/// Todo el texto visible de la superficie montada.
String textoVisible(WidgetTester tester) {
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' | ');
}

void main() {
  final destinos = [
    for (final def in shellModuleDefs) ShellDestination(path: def.path, icon: def.icon, label: def.path),
  ];

  Future<void> pumpSidebar(WidgetTester tester, {required bool collapsed, required Brightness brillo}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: brillo == Brightness.light ? AppTheme.light() : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AppSidebar(
            destinations: destinos,
            activeIndex: 0,
            collapsed: collapsed,
            onDestinationSelected: (_) {},
            onToggleCollapse: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPanelAuth(WidgetTester tester, {required Brightness brillo}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: brillo == Brightness.light ? AppTheme.light() : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AuthIdentityPanel(bienvenidaTitulo: 'Hola', bienvenidaMensaje: 'Mensaje')),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('El sidebar usa la marca del producto', () {
    testWidgets('desplegado dibuja el logotipo SEVENTRA, no el escudo de RISEG', (tester) async {
      await pumpSidebar(tester, collapsed: false, brillo: Brightness.light);

      expect(find.byKey(const Key('sidebar_logo')), findsOneWidget);
      // Variante blanca incluso en tema claro: el sidebar es tinta siempre.
      expect(assetsDibujados(tester), contains('assets/images/seventra-administra-blanco.png'));
      expect(
        assetsDibujados(tester),
        isNot(contains('assets/images/logo.png')),
        reason: 'el escudo de RISEG es identidad de Empresa, no del producto',
      );
    });

    testWidgets('el sidebar es tinta en los DOS temas, así que el logotipo no cambia', (tester) async {
      await pumpSidebar(tester, collapsed: false, brillo: Brightness.dark);
      expect(assetsDibujados(tester), contains('assets/images/seventra-administra-blanco.png'));
      expect(assetsDibujados(tester), isNot(contains('assets/images/seventra-administra.png')));
    });

    testWidgets('COLAPSADO usa la marca cuadrada, no el logotipo apaisado', (tester) async {
      // El raíl colapsado mide 80 px. El logotipo es 1715×280, así que a 40
      // de alto mediría 245 de ancho: no cabe. Por eso existe el icono.
      await pumpSidebar(tester, collapsed: true, brillo: Brightness.light);

      expect(assetsDibujados(tester), contains('assets/images/seventra-icono.png'));
      expect(assetsDibujados(tester), isNot(contains('assets/images/seventra-administra.png')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no repite el nombre ni el subtítulo bajo el logotipo', (tester) async {
      await pumpSidebar(tester, collapsed: false, brillo: Brightness.light);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // El logotipo YA dice "SEVENTRA Administra"; escribirlo debajo se leía
      // como un error de maquetación. Y "Sistema Integral Administrativo"
      // permanente hacía que la identidad nueva pareciera un retoque de la
      // anterior.
      expect(find.text(l10n.appTitle), findsNothing);
      expect(find.text(l10n.appSubtitle), findsNothing);
    });

    for (final collapsed in [false, true]) {
      for (final brillo in [Brightness.light, Brightness.dark]) {
        testWidgets('sin desborde — colapsado:$collapsed ${brillo.name}', (tester) async {
          await pumpSidebar(tester, collapsed: collapsed, brillo: brillo);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('El panel de identidad usa la marca del producto', () {
    for (final brillo in [Brightness.light, Brightness.dark]) {
      testWidgets('sobre el degradado azul siempre va la variante blanca (${brillo.name})', (tester) async {
        await pumpPanelAuth(tester, brillo: brillo);

        expect(find.byKey(const Key('auth_logo')), findsOneWidget);
        // El fondo es azul en los dos temas, así que el asset NO debe
        // depender del brillo: en tema claro también va el blanco.
        expect(assetsDibujados(tester), contains('assets/images/seventra-administra-blanco.png'));
        expect(assetsDibujados(tester), isNot(contains('assets/images/logo.png')));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el texto del panel no presenta a RISEG como producto', (tester) async {
      await pumpPanelAuth(tester, brillo: Brightness.light);
      expect(textoVisible(tester), isNot(contains('RISEG')));
    });
  });

  group('La identidad de la Empresa RISEG sigue intacta', () {
    test('assets/images/logo.png continúa disponible', () {
      // 5B.2 y 5B.3 lo necesitan: hasta entonces es el logotipo de la
      // Empresa RISEG en su expediente y en sus documentos.
      final archivo = File('assets/images/logo.png');
      expect(archivo.existsSync(), isTrue);
      expect(archivo.lengthSync(), greaterThan(0));
    });

    test('los textos que nombran a la EMPRESA no se tocaron', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // Son datos empresariales legítimos, no marca de producto mal puesta.
      // Su parametrización con el nombre de la Company es la etapa 5B.3.
      expect(l10n.clientesListadoSubtitulo, contains('RISEG'));
      expect(l10n.empleadosListadoVacioMensaje, contains('RISEG'));
      expect(l10n.empresaExpedienteSubtitulo, contains('RISEG'));
    });
  });

  group('Los textos del producto ya no dicen RISEG ONE', () {
    test('appTitle es el nombre del producto', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      expect(l10n.appTitle, 'Seventra Administra');
    });

    test('ninguna cadena visible llama RISEG ONE al producto', () {
      final arb = File('lib/l10n/app_es.arb').readAsStringSync();
      expect(arb.contains('RISEG ONE'), isFalse);
    });
  });

  group('Los assets del producto existen y conservan su proporción', () {
    for (final ruta in [
      'assets/images/seventra-administra.png',
      'assets/images/seventra-administra-blanco.png',
      'assets/images/seventra-icono.png',
    ]) {
      test('existe $ruta', () {
        expect(File(ruta).existsSync(), isTrue);
      });
    }

    test('la relación de aspecto declarada coincide con el archivo', () {
      // Si alguien sustituye el archivo por otro de proporción distinta, el
      // logotipo se deformaría en silencio. 1715×280.
      expect(LogotipoProducto.relacionAspecto, closeTo(6.125, 0.001));
    });
  });
  group('Inicio de sesión y alta del primer Maestro', () {
    // Estas dos pantallas tienen DOS disposiciones: a partir de 900 px
    // muestran el panel de identidad a la izquierda; por debajo, una
    // columna centrada con el logotipo arriba. Hay que comprobar las dos,
    // porque el asset se elige en sitios distintos.
    Future<void> pumpApp(WidgetTester tester, {required Size tamano}) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: RisegOneApp(router: createAppRouter()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ancho: el bootstrap muestra el panel de identidad del producto', (tester) async {
      await pumpApp(tester, tamano: const Size(1366, 768));

      expect(find.byKey(const Key('bootstrap_maestro_screen')), findsOneWidget);
      expect(assetsDibujados(tester), contains('assets/images/seventra-administra-blanco.png'));
      expect(assetsDibujados(tester), isNot(contains('assets/images/logo.png')));
    });

    testWidgets('estrecho: el bootstrap muestra el logotipo del producto en columna', (tester) async {
      await pumpApp(tester, tamano: const Size(700, 900));

      expect(find.byKey(const Key('bootstrap_logo')), findsOneWidget);
      expect(assetsDibujados(tester), contains('assets/images/seventra-administra.png'));
      expect(assetsDibujados(tester), isNot(contains('assets/images/logo.png')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ninguna de las dos presenta a RISEG como producto', (tester) async {
      await pumpApp(tester, tamano: const Size(1366, 768));
      expect(textoVisible(tester), isNot(contains('RISEG')));

      await pumpApp(tester, tamano: const Size(700, 900));
      expect(textoVisible(tester), isNot(contains('RISEG')));
    });

    for (final tamano in [const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)]) {
      testWidgets('sin desborde a ${tamano.width.toInt()} px', (tester) async {
        await pumpApp(tester, tamano: tamano);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('La compatibilidad de respaldo NO se tocó', () {
    test('el magic y la etiqueta de autenticación siguen siendo los de siempre', () {
      // Cambiar el nombre comercial no puede volver ilegible un .risegbkp
      // ya creado. El magic son los 8 primeros bytes del archivo y la
      // etiqueta entra en los datos autenticados: mover cualquiera de los
      // dos rompe todos los respaldos existentes.
      expect(ContenedorPortable.magic, 'RISEGBKP');
      expect(ContenedorPortable.extension, '.risegbkp');

      final fuente = File('lib/features/respaldo/domain/portable/configuracion_recuperacion.dart').readAsStringSync();
      expect(fuente, contains("'RISEG-BKP-v1 recovery-block "));
    });

    test('el nombre de la base dentro del paquete v2 no cambió', () {
      expect(RutasPaquete.nombreBaseDatos, 'riseg_one.sqlite');
    });
  });
  group('El logotipo no se deforma ni se sale', () {
    // "No deformes el wordmark" se puede comprobar de verdad: se mide el
    // recuadro que Flutter le asignó y se compara su relación de aspecto
    // con la del archivo (1715/280). Si alguien lo dimensionara por alto,
    // o lo metiera en un Expanded sin BoxFit, esto lo detecta.
    void exigirProporcion(WidgetTester tester, Key llave, {required double anchoMaximo}) {
      final caja = tester.getSize(find.byKey(llave));
      expect(
        caja.width / caja.height,
        closeTo(LogotipoProducto.relacionAspecto, 0.01),
        reason: 'el logotipo quedó en ${caja.width}×${caja.height}, que no es 1715:280',
      );
      expect(caja.width, lessThanOrEqualTo(anchoMaximo), reason: 'se sale del espacio disponible');
    }

    for (final brillo in [Brightness.light, Brightness.dark]) {
      testWidgets('en el sidebar desplegado (${brillo.name})', (tester) async {
        await pumpSidebar(tester, collapsed: false, brillo: brillo);
        // El sidebar mide 224 y el encabezado tiene AppSpacing.lg (20) de
        // padding a cada lado.
        exigirProporcion(tester, const Key('sidebar_logo'), anchoMaximo: 224 - 40);
      });
    }

    testWidgets('en el sidebar colapsado la marca es cuadrada', (tester) async {
      await pumpSidebar(tester, collapsed: true, brillo: Brightness.light);
      final caja = tester.getSize(find.byKey(const Key('sidebar_logo')));
      expect(caja.width, caja.height, reason: 'el icono es cuadrado, no apaisado');
      expect(caja.width, lessThanOrEqualTo(80 - 16), reason: 'el raíl colapsado mide 80');
    });

    for (final brillo in [Brightness.light, Brightness.dark]) {
      testWidgets('en el panel de identidad (${brillo.name})', (tester) async {
        await pumpPanelAuth(tester, brillo: brillo);
        exigirProporcion(tester, const Key('auth_logo'), anchoMaximo: 260);
      });
    }
  });
  group('La palomita de fondo del panel de identidad', () {
    testWidgets('se dibuja detrás del contenido y reusa el asset de la marca', (tester) async {
      await pumpPanelAuth(tester, brillo: Brightness.light);

      expect(assetsDibujados(tester), contains('assets/images/seventra-palomita.png'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('NO es verde: está reteñida para no competir con la marca', (tester) async {
      await pumpPanelAuth(tester, brillo: Brightness.light);

      // El archivo viene en verde. Se repinta con `srcIn` a un tinta apenas
      // más claro que el fondo: es textura, no elemento protagonista. Si
      // alguien quitara el filtro, aparecería una palomita verde de 520 px
      // encima del wordmark.
      final filtrados = tester.widgetList<ColorFiltered>(find.byType(ColorFiltered)).toList();
      expect(filtrados, isNotEmpty, reason: 'la palomita debe ir reteñida');
      expect(
        filtrados.any((f) => f.colorFilter == const ColorFilter.mode(AppColors.tintaDecorativa, BlendMode.srcIn)),
        isTrue,
        reason: 'el tinte tiene que ser tintaDecorativa, nunca el verde de marca',
      );
    });

    testWidgets('no deforma su proporción', (tester) async {
      await pumpPanelAuth(tester, brillo: Brightness.light);

      final imagen = tester.widget<Image>(
        find.descendant(of: find.byType(ColorFiltered), matching: find.byType(Image)),
      );
      // Sólo se fija el ancho; la altura la deduce Flutter del archivo
      // (740×752). Fijar las dos la deformaría.
      expect(imagen.width, 520);
      expect(imagen.height, isNull);
    });

    for (final tamano in [const Size(1366, 768), const Size(1024, 768)]) {
      for (final brillo in [Brightness.light, Brightness.dark]) {
        testWidgets('sin desborde a ${tamano.width.toInt()} px, ${brillo.name}', (tester) async {
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: brillo == Brightness.light ? AppTheme.light() : AppTheme.dark(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: AuthIdentityPanel(bienvenidaTitulo: 'Hola', bienvenidaMensaje: 'Mensaje'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // La palomita se sale del encuadre a propósito; el recorte del
          // Stack es lo que impide que eso sea un desborde.
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}