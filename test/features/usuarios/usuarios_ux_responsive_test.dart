// Etapa "Usuarios, permisos y UX de seguridad" — punto 20 del pedido de
// Marlon, la parte que NO cubre
// `gestionar_permisos_usuario_dialog_responsive_test.dart`:
//
//  - "Crear usuario + permisos" (el alta con el paso Permisos embebido);
//  - el menú de cuenta de la barra superior (identidad + acciones);
//  - "Cambiar mi contraseña".
//
// Matriz 1536/1366/1024/700/500 × claro/oscuro. La evidencia de que no
// hay overflow es `tester.takeException()` nulo tras dibujar: un
// RenderFlex desbordado se reporta como excepción del framework, y así
// se detectaron los dos overflows reales de esta etapa (la plantilla
// administrativa compacta y el propio menú de cuenta).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/shell/widgets/app_breadcrumb.dart';
import 'package:riseg_one/app/shell/widgets/app_top_bar.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/widgets/cambiar_mi_contrasena_dialog.dart';
import 'package:riseg_one/features/usuarios/presentation/widgets/gestionar_usuario_dialog.dart';

/// Nombre deliberadamente largo: el menú de cuenta y el chip de perfil
/// tienen que truncar, no desbordar. Un nombre corto no probaría nada.
const _nombreLargo = 'MARÍA GUADALUPE HERNÁNDEZ DE LA TORRE Y ARELLANO';

class _SesionDePrueba extends SesionController {
  _SesionDePrueba({required this.esMaestro});
  final bool esMaestro;

  @override
  SesionUsuario? build() => SesionUsuario(
        usuarioId: 'usuario-sesion',
        nombre: _nombreLargo,
        nombreUsuario: 'maria.guadalupe.hernandez',
        esMaestro: esMaestro,
        permisos: const {'usuarios.administrar', 'usuarios.otorgarPermisos'},
      );
}

const _anchos = [Size(1536, 864), Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)];

Future<void> _ajustarVentana(WidgetTester tester, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _montar(
  WidgetTester tester, {
  required AppDatabase db,
  required ThemeData tema,
  required Widget Function(BuildContext context, WidgetRef ref) cuerpo,
  bool esMaestro = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionDePrueba(esMaestro: esMaestro)),
      ],
      child: MaterialApp(
        theme: tema,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(builder: (context, ref, _) => cuerpo(context, ref)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late List<PuestoData> puestos;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-sesion'),
            nombre: _nombreLargo,
            nombreUsuario: 'maria.guadalupe.hernandez',
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

  tearDown(() => db.close());

  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};

  for (final entradaTema in temas.entries) {
    for (final tamano in _anchos) {
      final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()}, ${entradaTema.key}';

      testWidgets('Crear usuario + permisos ($etiqueta): sin overflow y con ambas secciones', (tester) async {
        await _ajustarVentana(tester, tamano);
        await _montar(
          tester,
          db: db,
          tema: entradaTema.value,
          cuerpo: (context, ref) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarDialogoGestionarUsuario(context, ref, puestos: puestos),
                child: const Text('abrir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(tester.takeException(), isNull, reason: 'el alta con el catálogo de permisos embebido no debe desbordar');

        // Las dos secciones del alta conviven en un solo formulario: los
        // permisos viajan CON la cuenta, no en una segunda operación.
        expect(find.text(l10n.usuarioSeccionCuenta), findsOneWidget);
        expect(find.text(l10n.usuarioSeccionPermisos), findsOneWidget);
        expect(find.byKey(const Key('usuario_campo_nombre')), findsOneWidget);
        expect(find.byKey(const Key('selector_permisos_buscar')), findsOneWidget);

        // El botón de confirmación sigue alcanzable: el scroll del
        // catálogo es interno, no empuja el footer del diálogo.
        expect(find.text(l10n.usuarioAltaBotonCrear), findsWidgets);
      });

      testWidgets('Menú de cuenta ($etiqueta): identidad y acciones sin overflow', (tester) async {
        await _ajustarVentana(tester, tamano);
        await _montar(
          tester,
          db: db,
          tema: entradaTema.value,
          esMaestro: true,
          cuerpo: (context, ref) => const Scaffold(
            body: Column(
              children: [
                AppTopBar(breadcrumbSegments: [BreadcrumbSegment(label: 'Configuración')]),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull, reason: 'la barra superior con un nombre largo debe truncar, no desbordar');

        await tester.tap(find.byKey(const Key('top_bar_profile')));
        await tester.pumpAndSettle();
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(tester.takeException(), isNull, reason: 'el menú de cuenta desbordaba 30px antes de esta etapa');

        // El menú dice DE QUIÉN es la sesión antes de ofrecer acciones —
        // era un popup suelto de una sola línea.
        expect(find.byKey(const Key('top_bar_identidad')), findsOneWidget);
        expect(find.text(l10n.shellCuentaMaestro), findsOneWidget, reason: 'un Maestro se identifica como tal');
        expect(find.byKey(const Key('top_bar_cambiar_contrasena')), findsOneWidget);
        expect(find.byKey(const Key('top_bar_cerrar_sesion')), findsOneWidget);
      });

      testWidgets('Cambiar mi contraseña ($etiqueta): sin overflow', (tester) async {
        await _ajustarVentana(tester, tamano);
        await _montar(
          tester,
          db: db,
          tema: entradaTema.value,
          cuerpo: (context, ref) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarDialogoCambiarMiContrasena(context, ref),
                child: const Text('abrir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('mi_contrasena_nueva')), findsOneWidget);
        expect(find.byKey(const Key('mi_contrasena_confirmar')), findsOneWidget);
      });
    }
  }

  testWidgets('el menú de cuenta de un usuario Normal muestra su nombre de usuario, no un rol inventado', (tester) async {
    await _ajustarVentana(tester, const Size(1366, 768));
    await _montar(
      tester,
      db: db,
      tema: AppTheme.light(),
      cuerpo: (context, ref) => const Scaffold(
        body: Column(children: [AppTopBar(breadcrumbSegments: [BreadcrumbSegment(label: 'Inicio')])]),
      ),
    );

    await tester.tap(find.byKey(const Key('top_bar_profile')));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text('maria.guadalupe.hernandez'), findsOneWidget);
    expect(
      find.text(l10n.shellCuentaMaestro),
      findsNothing,
      reason: 'una cuenta Normal nunca se rotula como Maestro',
    );
  });

  testWidgets('confirmación distinta NO cierra "Cambiar mi contraseña" y avisa inline', (tester) async {
    await _ajustarVentana(tester, const Size(1366, 768));
    await _montar(
      tester,
      db: db,
      tema: AppTheme.light(),
      cuerpo: (context, ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => mostrarDialogoCambiarMiContrasena(context, ref),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.enterText(find.byKey(const Key('mi_contrasena_nueva')), 'contrasenaLarga1');
    await tester.enterText(find.byKey(const Key('mi_contrasena_confirmar')), 'otraDistinta9');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.usuarioCambiarContrasenaBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mi_contrasena_nueva')), findsOneWidget, reason: 'la validación recuperable no cierra el diálogo');
    expect(find.text(l10n.usuarioErrorContrasenasNoCoinciden), findsOneWidget);
  });
}
