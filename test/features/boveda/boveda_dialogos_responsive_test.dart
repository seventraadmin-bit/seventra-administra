// Cierre de la deuda de validación de la Etapa 2: los tres formularios de
// Bóveda y el menú contextual, en los cuatro anchos de trabajo.
//
// No se prueba "que se vea bonito": se comprueba que no haya overflow, que
// los controles existan y sean alcanzables, y que la terminología visible
// diga siempre Contraseña.

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
import 'package:riseg_one/features/boveda/presentation/boveda_controller.dart';
import 'package:riseg_one/features/boveda/presentation/boveda_screen.dart';
import 'package:riseg_one/features/boveda/presentation/widgets/credencial_boveda_detalle_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

/// Los cuatro anchos de trabajo declarados para RISEG ONE.
const _anchos = [1366.0, 1024.0, 700.0, 500.0];

void main() {
  late AppDatabase db;
  late CredentialCipher cipher;
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
    cipher = CredentialCipher(almacen: _AlmacenEnMemoria());

    // Varias filas, para que la última quede cerca del borde inferior y el
    // menú tenga que reposicionarse.
    for (var i = 0; i < 12; i++) {
      await db
          .into(db.bovedaCredencial)
          .insert(
            BovedaCredencialCompanion.insert(
              nombre: 'Acceso $i',
              tipo: i.isEven ? 'software' : 'portal',
              usuarioAcceso: Value('USUARIO-$i'),
              secretoCifrado: Value(await cipher.cifrar('Contrasena-$i')),
            ),
          );
    }

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        credentialCipherProvider.overrideWithValue(cipher),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<void> montar(WidgetTester tester, double ancho) async {
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
          home: const Scaffold(body: BovedaScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Abre el menú de la ÚLTIMA fila: es la que queda pegada al borde
  /// inferior y obliga a Flutter a reposicionar el desplegable.
  Future<void> abrirMenuUltimaFila(WidgetTester tester) async {
    final menus = find.byIcon(Icons.more_vert);
    expect(menus, findsWidgets, reason: "la tabla debe ofrecer el menú por fila");
    // La última fila puede quedar fuera de la ventana: se trae a la vista,
    // que es lo que haría la persona, y así el menú se abre pegado al borde
    // inferior — el caso que obliga a Flutter a reposicionarlo.
    final ultimo = menus.last;
    await tester.ensureVisible(ultimo);
    await tester.pumpAndSettle();
    await tester.tap(ultimo);
    await tester.pumpAndSettle();
  }

  for (final ancho in _anchos) {
    final px = ancho.toInt();

    testWidgets('A. Nueva credencial a ${px}px: sin overflow y con todos los campos', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, ancho);

      await tester.tap(find.byKey(const Key('boveda_boton_nueva_credencial')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'cero overflow en el formulario de alta');
      // Los campos que el modelo realmente tiene.
      expect(find.text(l10n.bovedaCampoNombre), findsWidgets);
      expect(find.text(l10n.bovedaCampoTipo), findsWidgets);
      expect(find.text(l10n.bovedaCampoUsuarioAcceso), findsWidgets);
      expect(find.text(l10n.bovedaCampoCorreo), findsWidgets);
      expect(find.text(l10n.bovedaCampoUrl), findsWidgets);
      expect(find.text(l10n.bovedaCampoObservaciones), findsWidgets);
      // La contraseña sólo existe en el ALTA, y se llama Contraseña.
      expect(find.text('Contraseña'), findsWidgets);
      expect(find.textContaining('Secreto'), findsNothing);
    });

    testWidgets('B. Editar a ${px}px: sin overflow y SIN campo de contraseña', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, ancho);

      await abrirMenuUltimaFila(tester);
      await tester.tap(find.text(l10n.bovedaAccionEditar).last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.bovedaCampoNombre), findsWidgets);
      expect(find.text(l10n.bovedaCampoObservaciones), findsWidgets);
      expect(
        find.text('Contraseña'),
        findsNothing,
        reason: 'editar son metadatos: el campo de contraseña no existe aquí',
      );
    });

    testWidgets('C. Cambiar contraseña a ${px}px: sin overflow y con su campo', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, ancho);

      await abrirMenuUltimaFila(tester);
      await tester.tap(find.text(l10n.bovedaAccionCambiarSecreto).last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cambiar contraseña'), findsWidgets);
      expect(find.text('Nueva contraseña'), findsWidgets);
      expect(find.text('Actualizar contraseña'), findsWidgets);
      expect(find.textContaining('Secreto'), findsNothing);
    });

    testWidgets('D. Menú de la última fila a ${px}px: dentro del viewport y completo', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, ancho);

      await abrirMenuUltimaFila(tester);

      expect(tester.takeException(), isNull);

      // Las seis opciones reales de una credencial activa.
      for (final etiqueta in [
        l10n.bovedaAccionEditar,
        l10n.bovedaAccionCambiarSecreto,
        l10n.bovedaAccionMostrarSecreto,
        l10n.bovedaAccionCopiarSecreto,
        l10n.bovedaAccionHistorial,
        l10n.bovedaAccionDarDeBaja,
      ]) {
        final opcion = find.text(etiqueta).last;
        expect(opcion, findsOneWidget, reason: 'falta "$etiqueta"');
        // Ninguna opción puede quedar fuera de la pantalla.
        final caja = tester.getRect(opcion);
        expect(caja.left, greaterThanOrEqualTo(0), reason: '"$etiqueta" se sale por la izquierda');
        expect(caja.right, lessThanOrEqualTo(ancho), reason: '"$etiqueta" se sale por la derecha');
        expect(caja.top, greaterThanOrEqualTo(0), reason: '"$etiqueta" se sale por arriba');
        expect(caja.bottom, lessThanOrEqualTo(768), reason: '"$etiqueta" se sale por abajo');
      }

      // Y abrir el menú NO abre además la ficha.
      expect(find.byType(CredencialBovedaDetalleDialog), findsNothing);
    });
  }

  testWidgets('E. una credencial dada de baja ofrece Reactivar, no Dar de baja', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await db
        .into(db.bovedaCredencial)
        .insert(
          BovedaCredencialCompanion.insert(
            nombre: 'Acceso retirado',
            tipo: 'portal',
            cicloVidaRegistro: const Value('baja'),
          ),
        );
    // El listado oculta las inactivas por omisión: hay que pedirlas.
    await montar(tester, 1366);
    // Se aísla esa credencial: así el único menú en pantalla es el suyo.
    await container
        .read(bovedaControllerProvider.notifier)
        .aplicarFiltros(soloActivos: false, texto: 'Acceso retirado');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.bovedaAccionReactivar), findsOneWidget);
    expect(find.text(l10n.bovedaAccionDarDeBaja), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F. elegir una acción del menú no dispara además el detalle', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await montar(tester, 1366);

    await abrirMenuUltimaFila(tester);
    await tester.tap(find.text(l10n.bovedaAccionHistorial).last);
    await tester.pumpAndSettle();

    expect(find.byType(CredencialBovedaDetalleDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
