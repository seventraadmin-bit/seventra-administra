// "Descripción y uso" — el texto que explica para qué sirve un acceso.
//
// Su valor está en que otra persona autorizada pueda entender la credencial
// sin preguntarle a nadie, así que perder una línea por el camino no es un
// detalle estético: es perder la explicación.
//
// Internamente el campo sigue llamándose `observaciones`; sólo cambia cómo se
// presenta y se captura.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/boveda/boveda_providers.dart';
import 'package:riseg_one/features/boveda/domain/usecases/crear_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/presentation/boveda_controller.dart';
import 'package:riseg_one/features/boveda/presentation/boveda_screen.dart';
import 'package:riseg_one/features/boveda/presentation/widgets/credencial_boveda_detalle_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _AlmacenEnMemoria implements AlmacenClaveCifrado {
  String? _valor;
  @override
  Future<String?> leer() async => _valor;
  @override
  Future<void> escribir(String valor) async => _valor = valor;
}

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
    usuarioId: 'u-maestro',
    nombre: 'MARLON',
    nombreUsuario: 'marlon',
    esMaestro: true,
    permisos: {},
  );
}

/// Descripción real: varios párrafos, salto de línea, una URL larga y una
/// cadena sin espacios que podría desbordar si algo no envuelve bien.
const _descripcionLarga = '''
Usuario maestro de RISEG ONE. Permite administrar usuarios, configuraciones
generales y accesos del sistema.

Utilizar esta cuenta cuando se requiera administración completa de la
plataforma. Panel: https://portal.riseg.mx/administracion/usuarios/maestro/configuracion-general
Referencia interna: CUENTA-MAESTRA-ADMINISTRACION-GENERAL-RISEG-ONE-2026''';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.usuario)
        .insert(
          UsuarioCompanion.insert(
            id: const Value('u-maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: 'x',
          ),
        );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        credentialCipherProvider.overrideWithValue(CredentialCipher(almacen: _AlmacenEnMemoria())),
      ],
    );
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'u-maestro', nombre: 'MARLON', nombreUsuario: 'marlon', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<String> crearCon(String descripcion) async {
    final r = await container.read(crearCredencialBovedaAutorizadoProvider)(
      nombre: 'RISEG - ONE MAESTRO',
      tipo: 'software',
      observaciones: descripcion,
    );
    return (r as CrearCredencialBovedaExitoso).credencial.id;
  }

  Future<String?> leerDescripcion(String id) async {
    final c = await container.read(bovedaCredencialRepositoryProvider).obtenerPorId(id);
    return c?.observaciones;
  }

  Future<void> montar(WidgetTester tester, double ancho, {Widget? pantalla}) async {
    tester.view.physicalSize = Size(ancho, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: pantalla ?? const BovedaScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Persistencia íntegra', () {
    for (final largo in [100, 300, 500, 1000]) {
      test('1. un texto de $largo caracteres se guarda y se recupera completo', () async {
        final texto = List.generate(largo, (i) => String.fromCharCode(97 + (i % 26))).join();
        final id = await crearCon(texto);

        final recuperado = await leerDescripcion(id);

        expect(recuperado, texto);
        expect(recuperado!.length, largo, reason: 'la columna es TEXT: no hay límite que recorte');
      });
    }

    test('2. los saltos de línea y los párrafos sobreviven al viaje completo', () async {
      final id = await crearCon(_descripcionLarga);

      final recuperado = await leerDescripcion(id);

      expect(recuperado, _descripcionLarga);
      expect(recuperado!.contains('\n\n'), isTrue, reason: 'el párrafo en blanco se conserva');
      expect('\n'.allMatches(recuperado).length, greaterThanOrEqualTo(5));
    });
  });

  group('La ficha muestra el texto completo', () {
    testWidgets('3. no se recorta ni se sustituye por puntos suspensivos', (tester) async {
      final id = await crearCon(_descripcionLarga);
      await container.read(bovedaControllerProvider.notifier).recargar();

      await montar(tester, 1366, pantalla: CredencialBovedaDetalleDialog(credencialId: id));

      final mostrado = tester.widget<SelectableText>(find.byKey(const Key('boveda_detalle_descripcion')));
      expect(mostrado.data, _descripcionLarga, reason: 'el texto llega entero al widget');
      expect(mostrado.maxLines, isNull, reason: 'sin límite de líneas');
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. la etiqueta visible dice "Descripción y uso"', (tester) async {
      final id = await crearCon('Para qué sirve este acceso.');
      await container.read(bovedaControllerProvider.notifier).recargar();

      await montar(tester, 1366, pantalla: CredencialBovedaDetalleDialog(credencialId: id));

      expect(find.text('Descripción y uso'), findsOneWidget);
      expect(find.text('Observaciones'), findsNothing);
    });
  });

  group('Recorrido real: capturar, ver, editar, ver', () {
    testWidgets('5. nada se pierde entre la interfaz, el dominio y la base', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, 1366);

      // --- Capturar desde el formulario ---
      await tester.tap(find.byKey(const Key('boveda_boton_nueva_credencial')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'RISEG - ONE MAESTRO');
      await tester.enterText(find.byKey(const Key('boveda_campo_descripcion')), _descripcionLarga);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bovedaGestionarBotonConfirmar).last);
      await tester.pumpAndSettle();

      final credenciales = await container.read(bovedaCredencialRepositoryProvider).listar();
      expect(credenciales, hasLength(1));
      final id = credenciales.single.id;
      expect(await leerDescripcion(id), _descripcionLarga, reason: 'llegó completo a la base');

      // --- Verlo en la ficha ---
      await montar(tester, 1366, pantalla: CredencialBovedaDetalleDialog(credencialId: id));
      var mostrado = tester.widget<SelectableText>(find.byKey(const Key('boveda_detalle_descripcion')));
      expect(mostrado.data, _descripcionLarga);

      // --- Editarlo: el formulario debe traer el texto original entero ---
      await montar(tester, 1366);
      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bovedaAccionEditar).last);
      await tester.pumpAndSettle();

      final campo = tester.widget<TextFormField>(
        find.descendant(of: find.byKey(const Key('boveda_campo_descripcion')), matching: find.byType(TextFormField)),
      );
      expect(campo.controller!.text, _descripcionLarga, reason: 'se edita el texto completo, no un recorte');

      const ampliado = '$_descripcionLarga\n\nNota añadida al editar: revisar cada trimestre.';
      await tester.enterText(find.byKey(const Key('boveda_campo_descripcion')), ampliado);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.bovedaGestionarBotonConfirmar).last);
      await tester.pumpAndSettle();

      expect(await leerDescripcion(id), ampliado);

      // --- Y la ficha refleja el texto ampliado ---
      await montar(tester, 1366, pantalla: CredencialBovedaDetalleDialog(credencialId: id));
      mostrado = tester.widget<SelectableText>(find.byKey(const Key('boveda_detalle_descripcion')));
      expect(mostrado.data, ampliado);
    });
  });

  group('Responsive con descripción larga', () {
    for (final ancho in [1366.0, 1024.0, 700.0, 500.0]) {
      final px = ancho.toInt();

      testWidgets('6. ficha a ${px}px con descripción larga: cero overflow', (tester) async {
        final id = await crearCon(_descripcionLarga);
        await container.read(bovedaControllerProvider.notifier).recargar();

        await montar(tester, ancho, pantalla: CredencialBovedaDetalleDialog(credencialId: id));

        expect(tester.takeException(), isNull);
      });

      testWidgets('7. alta a ${px}px con el campo multilínea: cero overflow', (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));
        await montar(tester, ancho);

        await tester.tap(find.byKey(const Key('boveda_boton_nueva_credencial')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('boveda_campo_descripcion')), _descripcionLarga);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Y los botones siguen alcanzables pese al campo alto.
        await tester.ensureVisible(find.text(l10n.bovedaGestionarBotonConfirmar).last);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
