// Etapa "Usuarios, permisos y UX de seguridad" — punto 20 del pedido de
// Marlon: el diálogo de permisos NO puede ser "una tira vertical de 3
// pantallas sin estructura".
//
// El diseño anterior (una tarjeta por módulo, 23 seguidas, dentro de un
// SingleChildScrollView) se sustituyó por `SelectorPermisos`: buscador,
// grupos colapsables con contador n/total, "Marcar todo"/"Quitar todo"
// por grupo y scroll interno para que el footer Cancelar/Guardar quede
// SIEMPRE visible.
//
// Esta prueba fija ese contrato en los anchos responsive estándar
// (1536/1366/1024/700/500) × claro/oscuro, y por separado el
// comportamiento funcional del selector (búsqueda, colapso, marcar por
// grupo, persistencia).
//
// Nota sobre el `ListView` interno: es perezoso, así que un encabezado
// que queda fuera de la ventana NO se construye. Por eso las aserciones
// se apoyan en lo que siempre está en pantalla (el primer grupo, el
// buscador, el footer) o en filtrar con el buscador, nunca en que un
// módulo arbitrario del catálogo esté renderizado.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/core/permissions/plantillas_permiso.dart';
import 'package:riseg_one/features/usuarios/data/repositories/permiso_usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/widgets/gestionar_permisos_usuario_dialog.dart';

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

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  String usuarioId, {
  required Size tamano,
  required ThemeData tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: RisegButton(
                label: 'Abrir',
                onPressed: () async {
                  final repo = UsuarioRepositoryImpl(db);
                  final usuario = await repo.obtenerPorId(usuarioId);
                  if (!context.mounted || usuario == null) return;
                  await mostrarDialogoGestionarPermisosUsuario(context, ref, usuario);
                },
              ),
            ),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: MaterialApp.router(
        theme: tema,
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

/// Códigos de un grupo visual del selector — se calculan del catálogo
/// real, nunca se escriben a mano: si mañana entra un permiso nuevo al
/// grupo, la prueba sigue siendo cierta sin editarla.
Set<String> _codigosDelGrupo(String grupo) {
  return {
    for (final m in modulosPermiso)
      if ((m.grupoVisual ?? m.codigo) == grupo) ...m.todosLosCodigos,
  };
}

void main() {
  late AppDatabase db;
  late String usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final repo = UsuarioRepositoryImpl(db);
    final usuario = await repo.crear(nombre: 'Empleada de prueba', nombreUsuario: 'prueba', passwordHash: 'x');
    usuarioId = usuario.id;
    // `_SesionMaestroDePrueba.usuarioId` necesita una fila real —
    // `GuardarPermisosUsuarioUseCase` registra un `UsuarioEvento` con
    // `actorUsuarioId` (FK real a Usuario, Etapa 11D).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  const anchos = [Size(1536, 864), Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)];
  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};

  for (final entradaTema in temas.entries) {
    for (final tamano in anchos) {
      final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()}, ${entradaTema.key}';

      testWidgets('Selector de permisos ($etiqueta): cero overflow y estructura completa', (tester) async {
        await _pump(tester, db, usuarioId, tamano: tamano, tema: entradaTema.value);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(tester.takeException(), isNull, reason: 'el catálogo completo no debe desbordar en ningún ancho/tema');

        // 1. El buscador existe y es único — sin él, el catálogo completo
        //    solo se puede recorrer a scroll.
        expect(find.byKey(const Key('selector_permisos_buscar')), findsOneWidget);

        // 2. El resumen de selección (arranca en cero: la cuenta no tiene
        //    permisos).
        expect(find.text(l10n.permisosSeleccionadosTotal(0)), findsOneWidget);

        // 3. Estructura por grupos: el primero del catálogo siempre está
        //    construido, con su acción de grupo.
        expect(find.text(l10n.modulePersonal), findsWidgets, reason: 'el primer grupo debe tener encabezado propio');
        expect(find.text(l10n.permisosMarcarTodoGrupo), findsWidgets, reason: 'cada grupo ofrece marcar/quitar todo');

        // 4. El scroll vive DENTRO del selector: el footer del diálogo
        //    sigue visible aunque el catálogo sea largo. Esta es la
        //    diferencia concreta con "una tira vertical de 3 pantallas".
        expect(find.text(l10n.permisosBotonGuardar), findsOneWidget, reason: 'Guardar nunca queda debajo del fold');

        // 5. El buscador filtra de verdad, y el estado vacío también se
        //    dibuja sin overflow en este ancho.
        await tester.enterText(find.byKey(const Key('selector_permisos_buscar')), 'zzz-ningun-permiso');
        await tester.pumpAndSettle();
        expect(find.text(l10n.permisosBusquedaSinResultados), findsOneWidget);
        expect(find.text(l10n.permisosMarcarTodoGrupo), findsNothing, reason: 'sin grupos visibles no hay acciones de grupo');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('el buscador reduce el catálogo al permiso buscado', (tester) async {
    await _pump(tester, db, usuarioId, tamano: const Size(1366, 768), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.enterText(find.byKey(const Key('selector_permisos_buscar')), l10n.permisoIngresosCrear);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('permiso_ingresos.crear')), findsOneWidget);
    expect(
      find.byKey(const Key('permiso_personal.ver')),
      findsNothing,
      reason: 'un permiso que no coincide desaparece, no solo se desplaza',
    );
    // El grupo dueño del resultado sigue rotulado: el resultado no queda
    // suelto sin decir a qué pertenece.
    expect(find.text(l10n.moduleFinanzas), findsWidgets);
  });

  testWidgets('un grupo colapsado esconde sus permisos y se vuelve a abrir', (tester) async {
    await _pump(tester, db, usuarioId, tamano: const Size(1366, 768), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.byKey(const Key('permiso_personal.ver')), findsOneWidget);

    // El encabezado del grupo es el primer "Personal" en pantalla (el del
    // grupo, antes del encabezado del módulo homónimo).
    await tester.tap(find.text(l10n.modulePersonal).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('permiso_personal.ver')), findsNothing, reason: 'colapsar oculta el contenido del grupo');
    expect(find.text(l10n.modulePersonal), findsWidgets, reason: 'el encabezado del grupo permanece');

    await tester.tap(find.text(l10n.modulePersonal).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('permiso_personal.ver')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Marcar todo" del grupo marca sus permisos y actualiza el contador', (tester) async {
    await _pump(tester, db, usuarioId, tamano: const Size(1366, 768), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    final codigosPersonal = _codigosDelGrupo('personal');

    // El primer "Marcar todo" de la lista es el del primer grupo.
    await tester.tap(find.text(l10n.permisosMarcarTodoGrupo).first);
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.permisosGrupoConteo(codigosPersonal.length, codigosPersonal.length)),
      findsWidgets,
      reason: 'el contador del grupo pasa a n/n',
    );
    expect(find.text(l10n.permisosQuitarTodoGrupo), findsWidgets, reason: 'la acción se invierte cuando el grupo está completo');
    expect(find.text(l10n.permisosSeleccionadosTotal(codigosPersonal.length)), findsOneWidget);

    // Y se deshace con la misma acción.
    await tester.tap(find.text(l10n.permisosQuitarTodoGrupo).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.permisosSeleccionadosTotal(0)), findsOneWidget);
  });

  testWidgets('marcar "Registrar ingreso" y guardar persiste ingresos.crear para el usuario', (tester) async {
    await _pump(tester, db, usuarioId, tamano: const Size(1366, 768), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Se llega al permiso por el buscador — la vía real con el catálogo
    // completo, y además evita depender de que el `ListView` perezoso lo
    // haya construido.
    await tester.enterText(find.byKey(const Key('selector_permisos_buscar')), l10n.permisoIngresosCrear);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('permiso_ingresos.crear')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.permisosBotonGuardar));
    await tester.pumpAndSettle();

    final permisoRepo = PermisoUsuarioRepositoryImpl(db);
    final codigos = await permisoRepo.obtenerCodigos(usuarioId);
    expect(
      codigos,
      {'ingresos.crear'},
      reason: 'se persiste exactamente lo marcado: `ingresos` no declara acción `ver`, '
          'así que normalizar no le agrega nada (a diferencia de `personal`)',
    );
  });

  testWidgets('aplicar una plantilla precarga sus permisos, ajustables antes de guardar', (tester) async {
    await _pump(tester, db, usuarioId, tamano: const Size(1366, 900), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('selector_permisos_plantilla')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.permisosPlantillaComercial).last);
    await tester.pumpAndSettle();

    final plantilla = codigosDePlantilla('comercial');
    expect(
      find.text(l10n.permisosPlantillaAplicada(plantilla.length)),
      findsOneWidget,
      reason: 'el aviso dice cuántos permisos se precargaron y pide revisarlos',
    );

    // La plantilla es un PUNTO DE PARTIDA: se puede quitar un permiso
    // suelto antes de guardar, y lo que se persiste es el ajuste, no la
    // plantilla.
    await tester.enterText(find.byKey(const Key('selector_permisos_buscar')), l10n.permisoClientesArchivar);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('permiso_clientes.archivar')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.permisosBotonGuardar));
    await tester.pumpAndSettle();

    final codigos = await PermisoUsuarioRepositoryImpl(db).obtenerCodigos(usuarioId);
    expect(codigos, plantilla.difference({'clientes.archivar'}));
    expect(codigos, isNot(contains('clientes.archivar')), reason: 'el ajuste manual manda sobre la plantilla');
  });

  testWidgets('marcar una acción arrastra el `ver` de su módulo al guardar', (tester) async {
    await _pump(tester, db, usuarioId, tamano: const Size(1366, 768), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // `personal` SÍ tiene acción base `ver`: marcar solo "Crear" debe
    // guardarse junto con `personal.ver` (`normalizarPermisos`), o la
    // cuenta quedaría con facultad de crear sobre un módulo al que no
    // puede ni entrar.
    await tester.tap(find.byKey(const Key('permiso_personal.crear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.permisosBotonGuardar));
    await tester.pumpAndSettle();

    final codigos = await PermisoUsuarioRepositoryImpl(db).obtenerCodigos(usuarioId);
    expect(codigos, containsAll({'personal.crear', 'personal.ver'}));
  });
}
