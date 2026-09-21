// Regresión: "A RenderFlex overflowed by 147 pixels on the right." en
// Inventario → expediente del Artículo → sección Unidades. El `Row` de
// acciones por fila (agregado junto con "Corregir identificación", ver
// memoria de la Etapa 9D) tenía dos `RisegButton` de texto largo dentro
// de una columna de ancho fijo (`actionsWidth`, 96px por defecto) —
// desbordaba sin importar el ancho de ventana, porque `actionsWidth` es
// una constante, no algo que se ajuste con el espacio disponible. Se
// corrigió reemplazando el `Row` de botones por un menú compacto
// (`PopupMenuButton`, ícono ⋮) con `actionsWidth` reducido a 56 — un
// solo ícono, no texto largo, cabe siempre. De paso, esta misma prueba
// encontró que la columna "Estatus" (130px) también desbordaba por el
// padding interno de `RisegStatusBadge` con la etiqueta más larga
// ("Disponible") — se amplió a 150px, usando parte del espacio que
// `actionsWidth` dejó libre (96→56 = 40px ganados; Estatus 130→150 =
// 20px usados; el resto queda para las columnas flexibles).
//
// Segunda regresión, mismo archivo: al ensayar anchos genuinamente
// angostos (<900px, donde el sidebar colapsa automáticamente) esta
// misma prueba encontró OTRO desborde, ajeno a la tabla de Unidades y
// ya existente antes de ese primer cambio — el encabezado de la
// sección "Existencia" (`Row` con el título + hasta 3 botones:
// "Registrar entrada"/"Registrar baja"/"Ajustar") no cabía cuando el
// ancho de contenido disponible bajaba de ~880px, porque el `Expanded`
// solo podía encoger el título, nunca los botones. Corregido con
// `Wrap`/`WrapAlignment.spaceBetween` directo en esta pantalla.
//
// Tercera regresión, encontrada al aislar la segunda con una sesión
// no-Maestro: el encabezado SUPERIOR del propio Artículo (título +
// "Editar" + "Archivar"/"Eliminar físicamente (Maestro)") usa
// `RisegSectionHeader` — el mismo problema estructural, pero en el
// componente compartido del Design System, no en esta pantalla. Se
// corrigió ahí (`lib/core/design_system/components/riseg_section_header.dart`,
// ver `test/design_system/riseg_section_header_test.dart` para las
// pruebas del componente en aislamiento) — el último grupo de pruebas
// de este archivo confirma la corrección end-to-end, con una sesión
// Maestro real, en esta pantalla real.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

/// No-Maestro: el expediente del Artículo no gatea ningún botón por
/// permiso (confirmado — solo `esMaestro`/`activo`/`manejaSerie`
/// deciden qué se muestra), así que esta sesión solo sirve para NO
/// mostrar "Eliminar físicamente" en el encabezado superior del
/// Artículo (`RisegSectionHeader` con Editar/Archivar/Eliminar) — un
/// desborde propio de ESE encabezado, ajeno al de "Existencia" y fuera
/// del alcance de esta corrección, que de otro modo se mezclaría con
/// las pruebas de abajo a anchos angostos.
class _SesionNoMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba-2',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba2',
      esMaestro: false,
      permisos: {
        'inventario.ver',
        'inventario.crear',
        'inventario.corregir',
        'inventario.ajustarExistencia',
        'inventario.archivar',
      },
    );
  }
}

/// Artículo serializado con 3 unidades — suficiente para que la sección
/// "Unidades" tenga filas reales que renderizar en cada escenario de
/// ancho.
Future<String> _sembrarArticuloConUnidades(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso)
          .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'SMARTPHONE',
    manejaVariante: false,
    manejaSerie: true,
  ) as CrearArticuloExitoso)
      .articulo;

  final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
  for (var i = 1; i <= 3; i++) {
    await registrarEntradaUnidad.ejecutar(
      articuloId: articulo.id,
      numeroSerie: 'SN-REAL-00$i',
      marca: 'Samsung',
      modelo: 'A15',
      fecha: DateTime(2026, 1, 1),
      costoUnitario: 179400,
    );
  }

  return articulo.id;
}

/// Artículo por cantidad (`manejaSerie: false`) — a diferencia del
/// SMARTPHONE serializado de arriba, este muestra los 3 botones de la
/// sección Existencia a la vez ("Registrar entrada"/"Registrar baja"/
/// "Ajustar" — el tercero solo aparece cuando `!manejaSerie`), el
/// escenario real que reportó el desborde del encabezado.
Future<String> _sembrarArticuloPorCantidad(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'CAMISOLA TACTICA',
    manejaVariante: false,
    manejaSerie: false,
  ) as CrearArticuloExitoso)
      .articulo;

  return articulo.id;
}

Future<AppDatabase> _pumpAppEnExpediente(
  WidgetTester tester, {
  required Size size,
  required Future<String> Function(AppDatabase db) sembrar,
  required String nombreArticulo,
  SesionController Function() sesion = _SesionControllerDePrueba.new,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await sembrar(db);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(sesion),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('nav_item_inventario')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(nombreArticulo).first);
  await tester.pumpAndSettle();

  return db;
}

Future<AppDatabase> _pumpAppEnExpedienteArticulo(WidgetTester tester, {required Size size}) {
  return _pumpAppEnExpediente(tester, size: size, sembrar: _sembrarArticuloConUnidades, nombreArticulo: 'SMARTPHONE');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ArticuloExpedienteScreen — sección Unidades no desborda (regresión RenderFlex)', () {
    testWidgets('ventana normal (1440×900), sidebar expandido por defecto', (tester) async {
      await _pumpAppEnExpedienteArticulo(tester, size: const Size(1440, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('SMARTPHONE'), findsWidgets);
    });

    testWidgets('sidebar forzado colapsado en ventana normal (1440×900)', (tester) async {
      await _pumpAppEnExpedienteArticulo(tester, size: const Size(1440, 900));

      await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ancho menor soportado (1200×900), sidebar expandido (modo automático por defecto, '
      '≥900px) — el caso más exigente para la tabla de Unidades, el mismo tipo de escenario '
      'que reproducía el overflow original de 147px',
      (tester) async {
        // Sin tocar el botón de colapso: a este ancho el modo
        // `automatico` ya da sidebar expandido (≥ ShellBreakpoints.
        // sidebarAutoCollapse) — es justo el escenario más exigente, no
        // hace falta forzarlo.
        await _pumpAppEnExpedienteArticulo(tester, size: const Size(1200, 900));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('ancho menor soportado (1200×900) con el sidebar forzado colapsado', (tester) async {
      await _pumpAppEnExpedienteArticulo(tester, size: const Size(1200, 900));

      await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ArticuloExpedienteScreen — acciones de unidad accesibles vía el menú ⋮', () {
    testWidgets(
      'en el ancho que reproducía el overflow, el menú de acciones abre "Corregir identificación" y "Historial"',
      (tester) async {
        // Ancho reducido con sidebar expandido por defecto (automático,
        // sin tocar el botón de colapso) — el caso más exigente.
        final db = await _pumpAppEnExpedienteArticulo(tester, size: const Size(1200, 900));
        expect(tester.takeException(), isNull);

        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        final unidades = await InventarioRepositoryImpl(db).listarTodasUnidades();
        expect(unidades, hasLength(3));
        final primeraUnidad = unidades.first;

        final menuFinder = find.byKey(Key('unidad_acciones_${primeraUnidad.id}'));
        expect(menuFinder, findsOneWidget, reason: 'el menú ⋮ debe seguir presente y accesible en este ancho');

        await tester.tap(menuFinder);
        await tester.pumpAndSettle();

        expect(find.text(l10n.corregirIdentidadUnidadBotonAccion), findsWidgets);
        expect(find.text(l10n.asignacionSeccionHistorial), findsWidgets);

        await tester.tap(find.text(l10n.corregirIdentidadUnidadBotonAccion).last);
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.corregirIdentidadUnidadDialogoTitulo),
          findsOneWidget,
          reason: '"Corregir identificación" abre su diálogo',
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(l10n.corregirIdentidadUnidadBotonCancelar));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('unidad_acciones_${primeraUnidad.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.asignacionSeccionHistorial).last);
        await tester.pumpAndSettle();

        expect(find.textContaining(primeraUnidad.codigo), findsWidgets, reason: '"Historial" sigue accesible y abre su diálogo');
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ArticuloExpedienteScreen — encabezado de Existencia no desborda (regresión RenderFlex)', () {
    Future<void> verificarAccionesAccesibles(WidgetTester tester, AppLocalizations l10n) async {
      expect(find.text(l10n.articuloExpedienteSeccionExistencia), findsOneWidget, reason: 'el título sigue visible');
      expect(find.byKey(const Key('articulo_expediente_boton_entrada')), findsOneWidget);
      expect(find.byKey(const Key('articulo_expediente_boton_baja')), findsOneWidget);
      expect(find.byKey(const Key('articulo_expediente_boton_ajuste')), findsOneWidget, reason: 'artículo por cantidad: los 3 botones se muestran');

      // No solo presentes en el árbol — también con `hitTestable` real
      // (nunca detrás de otro widget, ni con tamaño cero por el propio
      // desborde que se está probando).
      await tester.ensureVisible(find.byKey(const Key('articulo_expediente_boton_ajuste')));
      expect(find.byKey(const Key('articulo_expediente_boton_ajuste')).hitTestable(), findsOneWidget);
    }

    testWidgets('ventana normal (1440×900), sidebar expandido por defecto', (tester) async {
      await _pumpAppEnExpediente(
        tester,
        size: const Size(1440, 900),
        sembrar: _sembrarArticuloPorCantidad,
        nombreArticulo: 'CAMISOLA TACTICA',
        sesion: _SesionNoMaestroDePrueba.new,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      await verificarAccionesAccesibles(tester, l10n);
    });

    testWidgets('sidebar forzado colapsado en ventana normal (1440×900)', (tester) async {
      await _pumpAppEnExpediente(
        tester,
        size: const Size(1440, 900),
        sembrar: _sembrarArticuloPorCantidad,
        nombreArticulo: 'CAMISOLA TACTICA',
        sesion: _SesionNoMaestroDePrueba.new,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await verificarAccionesAccesibles(tester, l10n);
    });

    testWidgets(
      'ancho reducido soportado (850×900), sidebar colapsado automáticamente — el ancho '
      'exacto donde el encabezado desbordaba antes de esta corrección',
      (tester) async {
        await _pumpAppEnExpediente(
          tester,
          size: const Size(850, 900),
          sembrar: _sembrarArticuloPorCantidad,
          nombreArticulo: 'CAMISOLA TACTICA',
          sesion: _SesionNoMaestroDePrueba.new,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(tester.takeException(), isNull);
        await verificarAccionesAccesibles(tester, l10n);
      },
    );

    testWidgets(
      'ancho reducido soportado (850×900) con el sidebar forzado expandido — el caso más exigente',
      (tester) async {
        await _pumpAppEnExpediente(
          tester,
          size: const Size(850, 900),
          sembrar: _sembrarArticuloPorCantidad,
          nombreArticulo: 'CAMISOLA TACTICA',
          sesion: _SesionNoMaestroDePrueba.new,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        // Por debajo de ShellBreakpoints.sidebarAutoCollapse (900) el
        // sidebar arranca colapsado automáticamente; forzarlo expandido
        // reduce el ancho de contenido disponible al mínimo real.
        await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await verificarAccionesAccesibles(tester, l10n);

        // Y siguen siendo funcionales, no solo visibles: tocar "Ajustar"
        // abre su diálogo incluso en este ancho.
        await tester.tap(find.byKey(const Key('articulo_expediente_boton_ajuste')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group(
    'ArticuloExpedienteScreen — encabezado superior del Artículo (RisegSectionHeader) no desborda '
    '(regresión end-to-end, corrección en el Design System)',
    () {
      Future<AppLocalizations> l10nDePrueba() => AppLocalizations.delegate.load(const Locale('es'));

      // Etapa 18: Archivar/Eliminar físicamente se movieron del
      // `secondaryAction` (botones sueltos) a un menú ⋯
      // (`RisegActionsMenu`) — sus `PopupMenuItem` solo existen en el
      // árbol una vez abierto el menú.
      Future<void> abrirMenuAcciones(WidgetTester tester) async {
        await tester.ensureVisible(find.byKey(const Key('articulo_expediente_menu_acciones')));
        await tester.tap(find.byKey(const Key('articulo_expediente_menu_acciones')));
        await tester.pumpAndSettle();
      }

      testWidgets(
        'sesión Maestro (3 acciones: Editar/Archivar/Eliminar físicamente), ventana normal (1440×900)',
        (tester) async {
          await _pumpAppEnExpediente(
            tester,
            size: const Size(1440, 900),
            sembrar: _sembrarArticuloPorCantidad,
            nombreArticulo: 'CAMISOLA TACTICA',
            // Sesión Maestro (default de _pumpAppEnExpediente): las 3
            // acciones aparecen a la vez — el peor caso real.
          );
          final l10n = await l10nDePrueba();

          expect(tester.takeException(), isNull);
          expect(find.text('CAMISOLA TACTICA'), findsWidgets, reason: 'AppBar + título del encabezado');
          expect(find.text(l10n.articuloExpedienteBotonEditar), findsOneWidget);

          await abrirMenuAcciones(tester);
          expect(tester.takeException(), isNull);
          expect(find.text(l10n.articuloBotonArchivar), findsOneWidget);
          expect(find.text(l10n.eliminacionFisicaAccionMenu), findsOneWidget, reason: '"Eliminar físicamente" solo para Maestro');
        },
      );

      testWidgets(
        'sesión Maestro, ancho reducido soportado (850×900) con sidebar forzado expandido — '
        'el caso más exigente, el mismo que causaba el desborde original',
        (tester) async {
          await _pumpAppEnExpediente(
            tester,
            size: const Size(850, 900),
            sembrar: _sembrarArticuloPorCantidad,
            nombreArticulo: 'CAMISOLA TACTICA',
          );
          final l10n = await l10nDePrueba();

          await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('CAMISOLA TACTICA'), findsWidgets, reason: 'el título sigue visible');

          await tester.ensureVisible(find.text(l10n.articuloExpedienteBotonEditar));
          expect(find.text(l10n.articuloExpedienteBotonEditar).hitTestable(), findsOneWidget);

          await abrirMenuAcciones(tester);
          for (final texto in [l10n.articuloBotonArchivar, l10n.eliminacionFisicaAccionMenu]) {
            expect(find.text(texto).hitTestable(), findsOneWidget, reason: '"$texto" sigue accesible en este ancho');
          }
          // Cierra el menú antes de tocar "Editar" — tocar la barrera
          // modal del propio menú (nunca una coordenada fija arbitraria,
          // que podría caer sobre otro widget del shell real y no
          // cerrar nada) es lo que garantiza el cierre.
          await tester.tapAt(tester.getTopLeft(find.byType(ModalBarrier).last));
          await tester.pumpAndSettle();
          expect(find.text(l10n.articuloBotonArchivar), findsNothing, reason: 'el menú ya debe estar cerrado');

          // Funcional, no solo visible: "Editar" sigue siendo tocable y
          // abre su diálogo incluso en el ancho más exigente.
          await tester.tap(find.text(l10n.articuloExpedienteBotonEditar));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'sesión Maestro, ancho reducido soportado (850×900) con sidebar colapsado automáticamente',
        (tester) async {
          await _pumpAppEnExpediente(
            tester,
            size: const Size(850, 900),
            sembrar: _sembrarArticuloPorCantidad,
            nombreArticulo: 'CAMISOLA TACTICA',
          );
          final l10n = await l10nDePrueba();

          expect(tester.takeException(), isNull);
          expect(find.text(l10n.articuloExpedienteBotonEditar).hitTestable(), findsOneWidget);

          await abrirMenuAcciones(tester);
          for (final texto in [l10n.articuloBotonArchivar, l10n.eliminacionFisicaAccionMenu]) {
            expect(find.text(texto).hitTestable(), findsOneWidget);
          }
        },
      );

      testWidgets(
        'sesión normal (menos acciones: solo Editar/Archivar, sin Eliminar físicamente), ancho '
        'reducido soportado (850×900) con sidebar forzado expandido',
        (tester) async {
          await _pumpAppEnExpediente(
            tester,
            size: const Size(850, 900),
            sembrar: _sembrarArticuloPorCantidad,
            nombreArticulo: 'CAMISOLA TACTICA',
            sesion: _SesionNoMaestroDePrueba.new,
          );
          final l10n = await l10nDePrueba();

          await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text(l10n.articuloExpedienteBotonEditar), findsOneWidget);

          await abrirMenuAcciones(tester);
          expect(find.text(l10n.articuloBotonArchivar), findsOneWidget);
          expect(find.text(l10n.eliminacionFisicaAccionMenu), findsNothing, reason: 'no-Maestro: sin la acción extraordinaria');
        },
      );
    },
  );
}
