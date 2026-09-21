// Etapa "Usuarios, permisos y UX de seguridad" — punto 1 del pedido.
//
// BUG REAL que fija: escribir una contraseña de menos de 8 caracteres y
// pulsar "Crear usuario" CERRABA el diálogo, perdía todo lo capturado y
// recién entonces mostraba un snackbar. Causa: cada rama de validación
// hacía `return false`, y `RisegDialog.showForm` cierra con cualquier
// valor NO nulo — `null` es su convenio documentado de "no es válido,
// corrígelo y seguimos aquí".
//
// Regla que protege: ninguna validación RECUPERABLE cierra el
// formulario, y el error se muestra inline en su propio campo.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/usuarios_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/widgets/gestionar_usuario_dialog.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'MARLON',
        nombreUsuario: 'marlon',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late List<PuestoData> puestos;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_usuario_dialog_test_');
    // El Maestro de la sesión debe EXISTIR de verdad: `actorUsuarioId`
    // es una FK real hacia `Usuario`, así que una sesión de prueba que
    // apunte a un id inexistente rompe el alta con un error de llave
    // foránea (encontrado al escribir esta prueba).
    await db.into(db.usuario).insert(
      UsuarioCompanion.insert(
        id: const Value('maestro'),
        nombre: 'MARLON',
        nombreUsuario: 'marlon',
        passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
        esMaestro: const Value(true),
      ),
    );

    puestos = await db.select(db.puesto).get();
    if (puestos.isEmpty) {
      final areaId = (await db.select(db.area).get()).first.id;
      await db.into(db.puesto).insert(
            PuestoCompanion.insert(
              codigo: 'PUE-ADM',
              nombre: 'Gerente en Recursos Humanos',
              areaId: areaId,
              tipo: 'administrativo',
              nivelJerarquico: 7,
            ),
          );
      puestos = await db.select(db.puesto).get();
    }
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> abrirAlta(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 900);
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
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => mostrarDialogoGestionarUsuario(context, ref, puestos: puestos),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('una contraseña corta NO cierra el diálogo y conserva lo capturado', (tester) async {
    await abrirAlta(tester);

    await tester.enterText(find.byKey(const Key('usuario_campo_nombre')), 'JAVIER RIOS');
    await tester.enterText(find.byKey(const Key('usuario_campo_nombre_usuario')), 'javier');
    await tester.enterText(find.byKey(const Key('usuario_campo_contrasena')), 'corta');
    await tester.pumpAndSettle();

    // Confirmar con la contraseña inválida.
    await tester.tap(find.text('Crear usuario').last);
    await tester.pumpAndSettle();

    // 1. El diálogo SIGUE ABIERTO (antes se cerraba aquí).
    expect(
      find.byKey(const Key('usuario_campo_contrasena')),
      findsOneWidget,
      reason: 'una validación recuperable nunca cierra el formulario',
    );
    // 2. Los datos capturados se conservan.
    expect(
      tester.widget<TextField>(find.descendant(of: find.byKey(const Key('usuario_campo_nombre_usuario')), matching: find.byType(TextField))).controller?.text,
      'javier',
      reason: 'no se pierde lo ya escrito',
    );
    // 3. El error se muestra INLINE, no solo en un snackbar posterior.
    expect(find.text('La contraseña debe tener al menos 8 caracteres.'), findsOneWidget);
    // 4. Nada se persistió.
    expect(await db.select(db.usuario).get(), hasLength(1), reason: 'solo el Maestro de la sesión: ninguna fila parcial');
  });

  testWidgets('un nombre de usuario vacío también deja el diálogo abierto, con error inline', (tester) async {
    await abrirAlta(tester);

    await tester.enterText(find.byKey(const Key('usuario_campo_nombre')), 'JAVIER RIOS');
    await tester.enterText(find.byKey(const Key('usuario_campo_contrasena')), 'contrasenaLarga1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear usuario').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('usuario_campo_nombre_usuario')), findsOneWidget);
    expect(await db.select(db.usuario).get(), hasLength(1));
  });

  // La atomicidad del alta se verifica en el caso de uso, no arrastrando
  // el formulario: lo que debe quedar fijado es que cuenta, permisos y
  // evento se escriben JUNTOS, no cómo se pulsan los controles. Los dos
  // tests de arriba ya cubren el comportamiento del diálogo.
  test('el alta escribe cuenta, permisos y evento en UNA sola operación', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(usuariosControllerProvider.notifier).crear(
          nombre: 'JAVIER RIOS',
          nombreUsuario: 'javier',
          password: 'contrasenaLarga1',
          puestoId: puestos.first.id,
          permisosIniciales: {'personal.ver', 'nomina.ver'},
        );

    expect(
      resultado,
      isA<CrearUsuarioExitoso>(),
      reason: resultado is CrearUsuarioErrorInesperado ? 'falló con: ${resultado.mensaje}' : null,
    );

    final usuarios = await db.select(db.usuario).get();
    expect(usuarios, hasLength(2), reason: 'el Maestro de la sesión + la cuenta nueva');
    final creado = usuarios.firstWhere((u) => u.nombreUsuario == 'javier');
    // Contraseña temporal: debe cambiarla en su primer acceso.
    expect(creado.debeCambiarPassword, isTrue);

    final permisos = await db.select(db.permisoUsuario).get();
    expect(
      permisos.map((p) => p.codigo),
      containsAll({'personal.ver', 'nomina.ver'}),
      reason: 'los permisos viajan con el alta, nunca en una segunda operación vulnerable',
    );

    // La contraseña NUNCA se guarda en claro, ni aparece en auditoría.
    expect(creado.passwordHash, isNot(contains('contrasenaLarga1')));
    final eventos = await db.select(db.usuarioEvento).get();
    expect(eventos, isNotEmpty, reason: 'el alta deja su evento en la misma transacción');
    for (final e in eventos) {
      expect(e.datosRelevantes ?? '', isNot(contains('contrasenaLarga1')));
    }
  });

  test('un alta rechazada no deja NADA a medias: ni cuenta, ni permisos, ni evento', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(usuariosControllerProvider.notifier).crear(
          nombre: 'JAVIER RIOS',
          nombreUsuario: 'javier',
          password: 'corta',
          puestoId: puestos.first.id,
          permisosIniciales: {'personal.ver'},
        );

    expect(resultado, isA<CrearUsuarioContrasenaInvalida>());
    expect(await db.select(db.usuario).get(), hasLength(1));
    expect(await db.select(db.permisoUsuario).get(), isEmpty);
    expect(await db.select(db.usuarioEvento).get(), isEmpty);
  });

  test('un Maestro nunca recibe filas de permiso, aunque se le pasen', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(usuariosControllerProvider.notifier).crear(
          nombre: 'OTRO MAESTRO',
          nombreUsuario: 'maestro2',
          password: 'contrasenaLarga1',
          puestoId: puestos.first.id,
          esMaestro: true,
          permisosIniciales: {'personal.ver', 'finanzas.ver'},
        );

    expect(
      await db.select(db.permisoUsuario).get(),
      isEmpty,
      reason: 'su acceso se recalcula en vivo; guardarle filas sería una segunda fuente de verdad',
    );
  });
}
