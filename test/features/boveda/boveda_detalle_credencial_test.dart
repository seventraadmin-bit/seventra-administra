// Ficha de credencial de la Bóveda — Etapa 2.
//
// Lo central: abrir una credencial NO descifra su contraseña. Para pintar
// puntos basta con saber que existe. El descifrado ocurre sólo cuando una
// acción autorizada lo pide, y queda auditado.

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
import 'package:riseg_one/features/boveda/presentation/boveda_screen.dart';
import 'package:riseg_one/features/boveda/presentation/widgets/credencial_boveda_detalle_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

const _contrasenaDePrueba = 'Sup3r-Secreta-De-Prueba';

/// Llave en memoria: las pruebas no hablan con el Almacén de Credenciales.
class _AlmacenEnMemoria implements AlmacenClaveCifrado {
  String? _valor;
  @override
  Future<String?> leer() async => _valor;
  @override
  Future<void> escribir(String valor) async => _valor = valor;
}

/// Cuenta cuántas veces se descifra algo. Es la evidencia de que abrir la
/// ficha no toca el cifrado.
class _CipherContador implements CredentialCipher {
  _CipherContador(this._real);
  final CredentialCipher _real;
  int descifrados = 0;

  @override
  Future<String> cifrar(String textoPlano) => _real.cifrar(textoPlano);

  @override
  Future<String> descifrar(String almacenado) {
    descifrados++;
    return _real.descifrar(almacenado);
  }
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

void main() {
  late AppDatabase db;
  late _CipherContador cipher;
  late String credencialId;

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
    cipher = _CipherContador(CredentialCipher(almacen: _AlmacenEnMemoria()));

    final cifrada = await cipher.cifrar(_contrasenaDePrueba);
    cipher.descifrados = 0; // el cifrado del montaje no cuenta

    final credencial = await db
        .into(db.bovedaCredencial)
        .insertReturning(
          BovedaCredencialCompanion.insert(
            nombre: 'RISEG - ONE MAESTRO',
            tipo: 'software',
            usuarioAcceso: const Value('MARLONRH'),
            correo: const Value('acceso@riseg.mx'),
            url: const Value('https://portal.riseg.mx'),
            observaciones: const Value('USUARIO MAESTRO'),
            secretoCifrado: Value(cifrada),
            fechaActualizacionSecreto: Value(DateTime(2026, 9, 20, 19, 12)),
          ),
        );
    credencialId = credencial.id;
  });

  tearDown(() => db.close());

  Future<ProviderContainer> montar(WidgetTester tester, {Widget? pantalla}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        credentialCipherProvider.overrideWithValue(cipher),
      ],
    );
    addTearDown(container.dispose);

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
    return container;
  }

  testWidgets('1. hacer clic en la fila abre la ficha de esa credencial', (tester) async {
    await montar(tester);

    await tester.tap(find.text('RISEG - ONE MAESTRO'));
    await tester.pumpAndSettle();

    expect(find.byType(CredencialBovedaDetalleDialog), findsOneWidget);
    expect(find.text('MARLONRH'), findsWidgets);
  });

  testWidgets('2. hacer clic en el menú NO abre además la ficha', (tester) async {
    await montar(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(
      find.byType(CredencialBovedaDetalleDialog),
      findsNothing,
      reason: 'el menú es un atajo, no una segunda vía de abrir el detalle',
    );
  });

  testWidgets('3. abrir la ficha NO descifra la contraseña', (tester) async {
    await montar(tester, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));

    expect(cipher.descifrados, 0, reason: 'pintar puntos no exige conocer la contraseña');
    expect(find.text('••••••••••'), findsOneWidget);
    expect(find.text(_contrasenaDePrueba), findsNothing);
  });

  testWidgets('4. Mostrar descifra una sola vez, revela y deja evento', (tester) async {
    await montar(tester, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));

    await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
    await tester.pumpAndSettle();

    expect(cipher.descifrados, 1);
    expect(find.text(_contrasenaDePrueba), findsOneWidget);

    final eventos = await db.select(db.bovedaCredencialEvento).get();
    final revelado = eventos.where((e) => e.tipoEvento == 'secretoRevelado');
    expect(revelado, hasLength(1));
    expect(revelado.single.actorUsuarioId, 'u-maestro');
    expect(
      revelado.single.observacion,
      isNot(contains(_contrasenaDePrueba)),
      reason: 'el evento jamás guarda la contraseña',
    );
  });

  testWidgets('5. Ocultar retira la contraseña de la pantalla', (tester) async {
    await montar(tester, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));

    await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
    await tester.pumpAndSettle();
    expect(find.text(_contrasenaDePrueba), findsOneWidget);

    await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
    await tester.pumpAndSettle();

    expect(find.text(_contrasenaDePrueba), findsNothing);
    expect(find.text('••••••••••'), findsOneWidget);
  });

  testWidgets('6. cerrar la ficha no conserva la contraseña revelada', (tester) async {
    await montar(tester);
    await tester.tap(find.text('RISEG - ONE MAESTRO'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
    await tester.pumpAndSettle();
    expect(find.text(_contrasenaDePrueba), findsOneWidget);

    await tester.tap(find.byKey(const Key('boveda_detalle_cerrar')));
    await tester.pumpAndSettle();

    // Y al reabrir vuelve a estar oculta, sin descifrado automático.
    final antes = cipher.descifrados;
    await tester.tap(find.text('RISEG - ONE MAESTRO'));
    await tester.pumpAndSettle();

    expect(find.text(_contrasenaDePrueba), findsNothing);
    expect(cipher.descifrados, antes, reason: 'reabrir tampoco descifra');
  });

  testWidgets('7. la lista no descifra ninguna contraseña', (tester) async {
    // Varias credenciales: pintar la tabla no puede depender del cifrado.
    for (var i = 0; i < 10; i++) {
      await db
          .into(db.bovedaCredencial)
          .insert(
            BovedaCredencialCompanion.insert(
              nombre: 'Acceso $i',
              tipo: 'portal',
              secretoCifrado: Value(await cipher.cifrar('otra-$i')),
            ),
          );
    }
    cipher.descifrados = 0;

    await montar(tester);

    expect(find.text('Acceso 0'), findsOneWidget);
    expect(cipher.descifrados, 0, reason: 'listar jamás descifra');
  });

  testWidgets('8. la contraseña no aparece en el historial', (tester) async {
    await montar(tester, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));
    await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
    await tester.pumpAndSettle();
    // Se vuelve a ocultar: lo que se comprueba es el historial, no la ficha
    // de atrás.
    await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
    await tester.pumpAndSettle();

    // La ficha se desplaza: hay que traer el botón a la vista, como haría
    // la persona.
    await tester.ensureVisible(find.byKey(const Key('boveda_detalle_historial')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boveda_detalle_historial')));
    await tester.pumpAndSettle();

    // El historial compone fecha y acción en un solo renglón.
    expect(find.textContaining('Contraseña mostrada'), findsWidgets);
    expect(find.textContaining('secretoRevelado'), findsNothing, reason: 'nada técnico a la vista');
    expect(
      find.textContaining(_contrasenaDePrueba),
      findsNothing,
      reason: 'el historial cuenta qué pasó, nunca el valor',
    );
  });
}
