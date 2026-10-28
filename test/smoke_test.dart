// Smoke test de la Etapa 2 (Shell): confirma navegación, colapso del
// sidebar, marcado del destino activo y presencia del logotipo — usando
// Keys estables, no únicamente texto traducido.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'support/sesion_en_base.dart';

/// Sesión Maestro fija para pruebas de navegación — Etapa 11A introdujo
/// login/bootstrap obligatorios; sin este override, cada una de las
/// ~30 pruebas de este archivo tendría que iniciar sesión a mano antes
/// de poder navegar. Un Maestro ve todos los módulos sin necesitar
/// filas de `PermisoUsuario` (`permisos: {}` nunca se consulta — el
/// bypass de `SessionPermissionService` ocurre antes, por `esMaestro`),
/// así que sigue siendo equivalente a "acceso total" para estas
/// pruebas aun con el gate real de la Etapa 11B ya activo.
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

/// Fuerza un tamaño de ventana de escritorio "cómodo" (por encima del
/// breakpoint de colapso automático del sidebar) para que las pruebas no
/// dependan del tamaño de superficie por defecto de flutter_test.
///
/// Sobrescribe [appDatabaseProvider] con una base en memoria — desde que
/// `/organizacion` abre `EmpresaExpedienteScreen` (Etapa 4B), el Shell ya
/// depende de la base de datos incluso en estas pruebas de navegación.
/// IF-5 — ya no se sobrescribe ningún conteo de usuarios locales: ese portón
/// desapareció con la autenticación local. Lo único que se fija es
/// `sesionControllerProvider` (sin esto el `redirect` mandaría a `/login`) —
/// ver `_SesionControllerDePrueba`.
Future<AppDatabase> _pumpApp(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase(NativeDatabase.memory());
  // Etapa 3B: autorizar revalida contra la base, así que el
  // escenario de la sesión tiene que estar persistido.
  await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  addTearDown(db.close);

  // Un router nuevo por prueba: `GoRouter` guarda estado de navegación
  // mutable, así que reusar una instancia entre pruebas filtraría a dónde
  // navegó la prueba anterior.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// Índice de la pestaña realmente marcada como activa en el `TabBar`
/// visible — usado en la Etapa 15 para verificar que la pestaña
/// superior de Organización coincide con la ruta real (`RisegTabs`
/// sincroniza su `TabController` interno con `selectedIndex`; ver
/// `riseg_tabs.dart`). `findsOneWidget` implícito en `tester.widget`:
/// si el bug de instancias duplicadas de `OrganizacionShellScreen`
/// reaparece, esta llamada falla con "too many elements" en vez de
/// leer silenciosamente la instancia equivocada.
int _pestanaActiva(WidgetTester tester) => tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Dashboard es el destino inicial', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('app_shell')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);
  });

  testWidgets('Navegar a otra rama cambia el contenido sin reconstruir el shell', (tester) async {
    await _pumpApp(tester);

    // Personal ya no es un placeholder genérico desde la Etapa 5A
    // (Empleados) — mismo criterio que Organización desde la 4B.
    await tester.tap(find.byKey(const Key('nav_item_personal')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app_shell')), findsOneWidget);
    expect(find.byKey(const Key('app_sidebar')), findsOneWidget);
    expect(find.byKey(const Key('empleados_boton_registrar')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_welcome')), findsNothing);
  });

  testWidgets('La ruta /organizacion abre el expediente de Empresa directamente', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('nav_item_organizacion')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empresa_expediente_screen')), findsOneWidget);
    expect(find.byKey(const Key('module_placeholder_organizacion')), findsNothing);
  });

  testWidgets('El destino activo queda marcado semánticamente', (tester) async {
    await _pumpApp(tester);

    bool? selectedOf(String navItemId) {
      final widget = tester.widget<Semantics>(find.byKey(Key('nav_item_$navItemId')));
      return widget.properties.selected;
    }

    expect(selectedOf('dashboard'), isTrue);
    expect(selectedOf('personal'), isFalse);

    await tester.tap(find.byKey(const Key('nav_item_personal')));
    await tester.pumpAndSettle();

    expect(selectedOf('personal'), isTrue);
    expect(selectedOf('dashboard'), isFalse);
  });

  testWidgets('El sidebar puede colapsarse', (tester) async {
    await _pumpApp(tester);

    final sidebarFinder = find.byKey(const Key('app_sidebar'));
    final widthBefore = tester.getSize(sidebarFinder).width;

    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();

    final widthAfter = tester.getSize(sidebarFinder).width;
    expect(widthAfter, lessThan(widthBefore));
  });

  testWidgets(
    'Con altura de ventana reducida, los destinos inferiores del sidebar siguen siendo accesibles mediante scroll',
    (tester) async {
      // 1440×600: por debajo del alto real donde antes se cortaban los
      // últimos destinos sin forma de alcanzarlos (bug reportado por
      // Marlon) — muy por encima del piso mínimo real del sidebar
      // (~200px, solo el encabezado fijo), así que esta altura representa
      // una ventana reducida "de uso normal", no un caso extremo.
      await _pumpApp(tester, size: const Size(1440, 600));

      // El último destino del menú no cabe sin scroll a esta altura.
      expect(find.byKey(const Key('nav_item_configuracion')), findsNothing);

      // El branding superior permanece visible y fijo mientras tanto.
      expect(find.byKey(const Key('sidebar_logo')), findsOneWidget);

      await tester.drag(find.byKey(const Key('app_sidebar_nav_scroll')), const Offset(0, -600));
      await tester.pumpAndSettle();

      // Tras el scroll, el destino ya es accesible y sigue siendo
      // funcional (navega correctamente).
      expect(find.byKey(const Key('nav_item_configuracion')), findsOneWidget);
      expect(find.byKey(const Key('sidebar_logo')), findsOneWidget, reason: 'el branding sigue fijo tras el scroll');

      await tester.tap(find.byKey(const Key('nav_item_configuracion')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app_shell')), findsOneWidget);
    },
  );

  testWidgets('El logotipo del PRODUCTO se muestra en el sidebar', (tester) async {
    // Etapa 5B.1: hasta aquí esta prueba exigía `assets/images/logo.png`,
    // que es el escudo corporativo de la Empresa RISEG. El sidebar es
    // superficie del producto, así que ahora lleva la marca del producto.
    await _pumpApp(tester);

    final logoFinder = find.byKey(const Key('sidebar_logo'));
    expect(logoFinder, findsOneWidget);

    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName);
    expect(assets, contains('assets/images/seventra-administra-blanco.png'));
    expect(assets, isNot(contains('assets/images/logo.png')));
  });

  testWidgets('La pantalla de verificación de la Etapa 1 ya no existe', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Etapa 1 — Verificación de infraestructura'), findsNothing);
  });

  testWidgets(
    'El módulo Activos fue retirado del sidebar (redundante con Inventario/Vehículos/Telefonía)',
    (tester) async {
      await _pumpApp(tester);
      expect(find.byKey(const Key('nav_item_activos')), findsNothing);
    },
  );

  testWidgets(
    'La pestaña Sucursales permite crear una Sucursal y navega a su expediente',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_organizacion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empresa_expediente_screen')), findsOneWidget);

      await tester.tap(find.text(l10n.organizacionTabSucursales));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sucursales_boton_nueva')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sucursales_boton_nueva')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Sucursal E2E');
      await tester.pumpAndSettle();

      // Abre el selector de tipo y elige el primero de los 3 sembrados
      // (ver `seed_data.dart` — "Oficina Administrativa").
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oficina Administrativa').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.sucursalAltaBotonCrear));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sucursal_expediente_boton_editar')), findsOneWidget);
    },
  );

  testWidgets(
    'Organización expone las 4 pestañas estables y la pestaña Puestos permite crear y navegar al expediente',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_organizacion')));
      await tester.pumpAndSettle();

      // Orden fijo aprobado en la Etapa 4D: Empresa, Sucursales, Puestos,
      // Áreas — no debe reordenarse en etapas futuras. "Empresa" aparece
      // dos veces (la pestaña y el título del expediente ya abierto),
      // así que solo esa se verifica con `findsWidgets`.
      expect(find.text(l10n.organizacionTabEmpresa), findsWidgets);
      expect(find.text(l10n.organizacionTabSucursales), findsOneWidget);
      expect(find.text(l10n.organizacionTabPuestos), findsOneWidget);
      expect(find.text(l10n.organizacionTabAreas), findsOneWidget);

      await tester.tap(find.text(l10n.organizacionTabPuestos));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('puestos_boton_nueva')), findsOneWidget);

      await tester.tap(find.byKey(const Key('puestos_boton_nueva')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Guardia E2E');

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operaciones').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<TipoPuesto>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.puestoTipoOperativo).last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, '5');

      await tester.tap(find.text(l10n.puestoAltaBotonCrear));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('puesto_expediente_boton_editar')), findsOneWidget);
    },
  );

  testWidgets('La pestaña Áreas del listado de Organización es alcanzable', (tester) async {
    await _pumpApp(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('nav_item_organizacion')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.organizacionTabAreas));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('areas_boton_nueva')), findsOneWidget);
    expect(find.text('Operaciones'), findsOneWidget);
  });

  testWidgets(
    'Organización: la pestaña marcada sigue a la ruta real al navegar entre pestañas, en cualquier '
    'dirección (Etapa 15, corrección de la pestaña activa desincronizada)',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_organizacion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empresa_expediente_screen')), findsWidgets);
      expect(_pestanaActiva(tester), 0);

      await tester.tap(find.text(l10n.organizacionTabSucursales));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sucursales_boton_nueva')), findsOneWidget);
      expect(_pestanaActiva(tester), 1);

      await tester.tap(find.text(l10n.organizacionTabPuestos));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('puestos_boton_nueva')), findsOneWidget);
      expect(_pestanaActiva(tester), 2);

      await tester.tap(find.text(l10n.organizacionTabAreas));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('areas_boton_nueva')), findsOneWidget);
      expect(_pestanaActiva(tester), 3);

      // De regreso a Empresa — la dirección "hacia atrás" es la que
      // reproducía el bug original (Sucursales quedaba marcada aunque
      // el contenido ya fuera Empresa).
      await tester.tap(find.text(l10n.organizacionTabEmpresa));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empresa_expediente_screen')), findsWidgets);
      expect(_pestanaActiva(tester), 0);
    },
  );

  testWidgets(
    'Organización: entrar directo por ruta a /organizacion/puestos marca Puestos, no Empresa',
    (tester) async {
      await _pumpApp(tester);

      final context = tester.element(find.byKey(const Key('app_shell')));
      GoRouter.of(context).go('/organizacion/puestos');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('puestos_boton_nueva')), findsOneWidget);
      expect(_pestanaActiva(tester), 2);
    },
  );

  testWidgets(
    'Organización: volver del expediente recién creado de una Sucursal conserva la pestaña '
    'Sucursales marcada (equipo de escritorio: "volver" es el botón de regreso del AppBar, '
    'no un gesto/botón de sistema)',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_organizacion')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.organizacionTabSucursales));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sucursales_boton_nueva')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Sucursal Regreso E2E');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oficina Administrativa').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.sucursalAltaBotonCrear));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sucursal_expediente_boton_editar')), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sucursales_boton_nueva')), findsOneWidget);
      expect(_pestanaActiva(tester), 1);
    },
  );

  testWidgets(
    'El destino Comercial permite crear un Cliente y navega a su expediente',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_comercial')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clientes_boton_nueva')), findsOneWidget);

      await tester.tap(find.byKey(const Key('clientes_boton_nueva')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Sportium E2E');
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.clienteAltaBotonCrear));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cliente_expediente_boton_editar')), findsOneWidget);
    },
  );

  testWidgets(
    'Inventario redirige a Artículos y expone la pestaña Reportes (Etapa 7D)',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_inventario')));
      await tester.pumpAndSettle();

      // `/inventario` en sí redirige a `/inventario/articulos` — mismo
      // patrón que `/personal`/`/comercial`.
      expect(find.byKey(const Key('inventario_boton_nuevo_articulo')), findsOneWidget);

      // "Reportes" también es el nombre de un destino distinto del
      // sidebar (módulo pendiente) — se acota la pestaña a las tabs de
      // Inventario para no ambigüar el tap.
      final tabReportes = find.descendant(of: find.byType(RisegTabs), matching: find.text(l10n.inventarioTabReportes));
      await tester.tap(tabReportes);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inventario_boton_nuevo_articulo')), findsNothing);
      expect(find.text(l10n.reportesSeccionExistencias), findsOneWidget);
      expect(find.text(l10n.reportesExistenciasVacio), findsOneWidget);
      expect(find.text(l10n.reportesSeccionAsignacionesVigentes), findsOneWidget);
      expect(find.text(l10n.reportesSeccionDanadosPerdidos), findsOneWidget);
      expect(find.text(l10n.reportesSeccionDescuentosPendientes), findsOneWidget);
      expect(find.text(l10n.reportesSeccionMovimientos), findsOneWidget);

      final tabArticulos = find.descendant(of: find.byType(RisegTabs), matching: find.text(l10n.inventarioTabArticulos));
      await tester.tap(tabArticulos);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inventario_boton_nuevo_articulo')), findsOneWidget);
    },
  );

  testWidgets(
    'Vehículos permite dar de alta un vehículo y navega a su expediente (Etapa 8A)',
    (tester) async {
      await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('nav_item_vehiculos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vehiculos_boton_nuevo_vehiculo')), findsOneWidget);

      await tester.tap(find.byKey(const Key('vehiculos_boton_nuevo_vehiculo')));
      await tester.pumpAndSettle();

      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'BMW');
      await tester.enterText(campos.at(1), '320i');
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.vehiculoBotonGuardar));
      await tester.pumpAndSettle();

      expect(find.text('VEH-000001'), findsOneWidget);

      await tester.tap(find.text('VEH-000001'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vehiculos_boton_nuevo_vehiculo')), findsNothing);
      expect(find.text(l10n.vehiculoExpedienteSeccionDatosGenerales), findsOneWidget);
    },
  );

  testWidgets(
    'Vehículos permite asignar a un Empleado y retirar la asignación (Etapa 8B)',
    (tester) async {
      final db = await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Ricardo',
              apellidoPaterno: 'Gómez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'GORR900101HDFXXX01',
              rfc: 'GORR900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );

      await tester.tap(find.byKey(const Key('nav_item_vehiculos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vehiculos_boton_nuevo_vehiculo')));
      await tester.pumpAndSettle();
      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'BMW');
      await tester.enterText(campos.at(1), '320i');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.vehiculoBotonGuardar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VEH-000001'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.vehiculoAsignacionVacio), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.vehiculoBotonAsignar));
      await tester.tap(find.text(l10n.vehiculoBotonAsignar));
      await tester.pumpAndSettle();
      // El destino por defecto ya es "Empleado" — solo hace falta
      // elegir cuál en el segundo selector.
      final selectorEmpleado = find.byType(DropdownButtonFormField<String?>).last;
      await tester.tap(selectorEmpleado);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ricardo Gómez').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.vehiculoAsignarBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.estatusVehiculoAsignado), findsWidgets);
      expect(find.text('Ricardo Gómez'), findsWidgets);
      expect(find.text(l10n.vehiculoBotonRetirarAsignacion), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.vehiculoBotonRetirarAsignacion));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.vehiculoBotonRetirarAsignacion));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.vehiculoRetirarAsignacionBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.vehiculoAsignacionVacio), findsOneWidget);
      expect(find.text(l10n.estatusVehiculoDisponible), findsWidgets);

      // Consulta de solo lectura desde el Empleado (punto 5).
      await tester.tap(find.byKey(const Key('nav_item_personal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ricardo Gómez'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.vehiculoAsignadoSeccionTitulo), findsOneWidget);
      expect(find.text(l10n.vehiculoAsignadoVacio), findsOneWidget);

      // Confirma que el Empleado creado directo en BD sí aparece en el
      // listado (sanity check del setup de la prueba).
      expect(empleado.id, isNotEmpty);
    },
  );

  testWidgets(
    'Vehículos: la pestaña Alertas muestra documentos vencidos pero excluye vehículos dados de baja (Etapa 8C, punto 10)',
    (tester) async {
      final db = await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      final activo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(codigo: 'VEH-A', marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'),
          );
      final baja = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-B',
              marca: 'Nissan',
              modelo: 'Versa',
              tipoVehiculo: 'sedan',
              estatus: const Value('baja'),
              fechaBaja: Value(DateTime(2026, 1, 1)),
              motivoBaja: const Value('venta'),
            ),
          );

      // Vencimiento fijo en el pasado lejano — siempre "vencido" sin
      // importar la fecha real en la que corra la prueba.
      await db.into(db.vehiculoDocumento).insert(
            VehiculoDocumentoCompanion.insert(vehiculoId: activo.id, tipo: 'seguro', fechaVencimiento: Value(DateTime(2000, 1, 1))),
          );
      await db.into(db.vehiculoDocumento).insert(
            VehiculoDocumentoCompanion.insert(vehiculoId: baja.id, tipo: 'seguro', fechaVencimiento: Value(DateTime(2000, 1, 1))),
          );

      await tester.tap(find.byKey(const Key('nav_item_vehiculos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.vehiculosTabAlertas));
      await tester.pumpAndSettle();

      expect(find.textContaining('VEH-A'), findsOneWidget, reason: 'el vehículo activo con documento vencido sí genera alerta');
      expect(find.textContaining('VEH-B'), findsNothing, reason: 'el vehículo dado de baja no debe generar ruido de alertas');
    },
  );

  testWidgets(
    'Vehículos: la pestaña Alertas muestra mantenimiento vencido pero excluye vehículos dados de baja (Etapa 8D, punto 15)',
    (tester) async {
      final db = await _pumpApp(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      final activo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(codigo: 'VEH-C', marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'),
          );
      final baja = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VEH-D',
              marca: 'Nissan',
              modelo: 'Versa',
              tipoVehiculo: 'sedan',
              estatus: const Value('baja'),
              fechaBaja: Value(DateTime(2026, 1, 1)),
              motivoBaja: const Value('venta'),
            ),
          );

      // Próximo mantenimiento fijo en el pasado lejano — siempre
      // "vencido" sin importar la fecha real en la que corra la prueba.
      await db.into(db.vehiculoMantenimiento).insert(
            VehiculoMantenimientoCompanion.insert(
              vehiculoId: activo.id,
              fecha: DateTime(1999, 1, 1),
              tipo: 'preventivo',
              descripcion: 'Servicio de prueba',
              proximoMantenimientoFecha: Value(DateTime(2000, 1, 1)),
            ),
          );
      await db.into(db.vehiculoMantenimiento).insert(
            VehiculoMantenimientoCompanion.insert(
              vehiculoId: baja.id,
              fecha: DateTime(1999, 1, 1),
              tipo: 'preventivo',
              descripcion: 'Servicio de prueba',
              proximoMantenimientoFecha: Value(DateTime(2000, 1, 1)),
            ),
          );

      await tester.tap(find.byKey(const Key('nav_item_vehiculos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.vehiculosTabAlertas));
      await tester.pumpAndSettle();

      expect(find.textContaining('VEH-C'), findsOneWidget, reason: 'el vehículo activo con mantenimiento vencido sí genera alerta');
      expect(find.textContaining('VEH-D'), findsNothing, reason: 'el vehículo dado de baja no debe generar nuevas alertas operativas');
    },
  );

  testWidgets(
    'Telefonía permite dar de alta una línea y navega a su expediente (Etapa 9A)',
    (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.byKey(const Key('nav_item_telefonia')));
      await tester.pumpAndSettle();

      // Etapa 9D: /telefonia aterriza en la pestaña Equipos — hace
      // falta cambiar a Líneas antes de llegar al formulario de alta.
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await tester.tap(find.text(l10n.telefoniaTabLineas));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telefonia_boton_nueva_linea')), findsOneWidget);

      await tester.tap(find.byKey(const Key('telefonia_boton_nueva_linea')));
      await tester.pumpAndSettle();

      // Operador y modalidad ya traen un valor por defecto — número es
      // opcional — así que Guardar sin llenar nada más debe bastar.
      await tester.tap(find.text(l10n.lineaTelefonicaBotonGuardar));
      await tester.pumpAndSettle();

      expect(find.text('TEL-000001'), findsOneWidget);

      await tester.tap(find.text('TEL-000001'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telefonia_boton_nueva_linea')), findsNothing);
      expect(find.text(l10n.lineaTelefonicaExpedienteSeccionDatos), findsOneWidget);

      // Etapa 9B: el expediente ya expone Asignar/Asociar equipo — solo
      // se prueba que la UI está montada y el diálogo abre, la lógica de
      // negocio (asignación, equipo, consistencia con Inventario) ya
      // está cubierta por pruebas unitarias dedicadas.
      expect(find.text(l10n.lineaTelefonicaBotonAsignar), findsOneWidget);
      expect(find.text(l10n.lineaTelefonicaBotonAsociarEquipo), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.lineaTelefonicaBotonAsignar));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.lineaTelefonicaBotonAsignar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lineaTelefonicaAsignarDialogoTitulo), findsOneWidget);

      await tester.tap(find.text(l10n.lineaTelefonicaBotonCancelar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lineaTelefonicaAsignarDialogoTitulo), findsNothing);

      // Etapa 9C: Telefonía es prepago — Plan/costo fue retirado por
      // completo (la propia ausencia de `lineaTelefonicaPlanSeccionTitulo`
      // del l10n ya lo demuestra en tiempo de compilación), Recargas
      // ocupa su lugar en el expediente.
      expect(find.text(l10n.lineaTelefonicaRecargaSeccionTitulo), findsOneWidget);
      expect(find.text(l10n.lineaTelefonicaBotonRegistrarRecarga), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.lineaTelefonicaBotonRegistrarRecarga));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.lineaTelefonicaBotonRegistrarRecarga));
      await tester.pumpAndSettle();
      // El diálogo comparte título con el botón que lo abre ("Registrar
      // recarga") — se confirma que abrió por su botón de confirmación,
      // que sí es único ("Guardar recarga").
      expect(find.text(l10n.lineaTelefonicaRecargaBotonGuardar), findsOneWidget);

      await tester.tap(find.text(l10n.lineaTelefonicaBotonCancelar));
      await tester.pumpAndSettle();
      expect(find.text(l10n.lineaTelefonicaRecargaBotonGuardar), findsNothing);
    },
  );

  testWidgets(
    'Compras permite abrir el formulario de registro de una compra (Etapa 10)',
    (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.byKey(const Key('nav_item_compras')));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.byKey(const Key('compras_boton_registrar')), findsOneWidget);
      expect(find.text(l10n.comprasListadoVacioTitulo), findsOneWidget);

      await tester.tap(find.byKey(const Key('compras_boton_registrar')));
      await tester.pumpAndSettle();

      // El título de la pantalla ("Registrar compra") repite el texto
      // del botón que la abrió — se confirma que sí navegó por una
      // sección propia de la pantalla ("Partidas"), no solo por texto
      // compartido.
      expect(find.text(l10n.compraPartidasSeccionTitulo), findsOneWidget);
      expect(find.text(l10n.compraBotonAgregarPartida), findsOneWidget);
    },
  );

  testWidgets(
    'Sin sesión, el login real bloquea la navegación y no queda portón local (IF-5)',
    (tester) async {
      // A propósito NO usa `_pumpApp`: esta prueba exige el `redirect`
      // real de login/bootstrap, así que monta con la base en memoria
      // real (sin Usuarios) y sin sobrescribir `sesionControllerProvider`.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Etapa 3B — excepción deliberada: la base va SIN Usuarios porque
      // eso es justamente lo que esta prueba verifica (el bootstrap sólo
      // existe mientras `contarUsuarios() == 0`). Sembrar una cuenta
      // aquí apagaría el escenario bajo prueba.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: RisegOneApp(router: createAppRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // IF-5 — SIN SESIÓN, CUALQUIER RUTA CAE EN EL LOGIN REAL.
      //
      // Antes esta prueba recorría «base sin usuarios → bootstrap del primer
      // Maestro → login local → shell». Los dos primeros tramos se retiraron con
      // la autenticación local: el primer Maestro lo da de alta el
      // aprovisionamiento de plataforma y la contraseña vive en el backend.
      //
      // Lo que SIGUE siendo cierto —y es la garantía que importaba— es que el
      // portón no se puede rodear: sin sesión no se construye ni un fragmento del
      // shell, y no queda ninguna pantalla local por la que colarse.
      expect(find.byKey(const Key('login_screen')), findsOneWidget);
      expect(find.byKey(const Key('app_shell')), findsNothing);
      expect(find.byKey(const Key('bootstrap_maestro_screen')), findsNothing);

      // El login pide correo y contraseña, y nada de esto abre el shell solo.
      expect(find.byKey(const Key('login_campo_usuario')), findsOneWidget);
      expect(find.byKey(const Key('login_campo_password')), findsOneWidget);
      expect(find.byKey(const Key('login_olvide_contrasena')), findsOneWidget);

      // NO se pulsa «Entrar» aquí: hacerlo llamaría al backend, y esta prueba
      // monta la aplicación sin configuración de servidor a propósito. Que el
      // login exige backend está probado en las pruebas de core/auth; lo que se
      // fija aquí es que sin sesión no hay forma de ver el shell.
      expect(find.byKey(const Key('login_boton_entrar')), findsOneWidget);

    },
  );


  testWidgets(
    'Permisos dinámicos: sidebar filtrado, ruta directa bloqueada y gate de Configuración',
    (tester) async {
      // IF-5 — la sesión se FIJA en vez de obtenerse por el login local, que se
      // retiró. Lo que esta prueba verifica no cambió ni un ápice: que el sidebar
      // muestre sólo los módulos con permiso, que una ruta directa a un módulo sin
      // permiso caiga en acceso denegado, y que `/configuracion` tenga su gate
      // propio. Esa granularidad es la que el cutover tenía que conservar.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      const beto = SesionUsuario(
        usuarioId: 'beto',
        nombre: 'Beto RH',
        nombreUsuario: 'beto@riseg.mx',
        esMaestro: false,
        permisos: {'personal.ver'},
      );

      const carla = SesionUsuario(
        usuarioId: 'carla',
        nombre: 'Carla Admin',
        nombreUsuario: 'carla@riseg.mx',
        esMaestro: false,
        permisos: {'usuarios.administrar'},
      );

      // La fila local tiene que existir: la atribución de lo que se escriba
      // apunta a ella por clave ajena. Es lo que hace la proyección en producción.
      await sembrarSesionEnBase(db, beto);
      await sembrarSesionEnBase(db, carla);

      Future<GoRouter> montarComo(SesionUsuario sesion) async {
        // Árbol limpio entre montajes: reemplazar el ProviderScope sobre el mismo
        // elemento no rehace un provider `keepAlive` ya inicializado, así que la
        // sesión del montaje anterior sobreviviría al cambio de override.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        final router = createAppRouter();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              sesionControllerProvider.overrideWith(() => _SesionFijada(sesion)),
            ],
            child: RisegOneApp(router: router),
          ),
        );
        await tester.pumpAndSettle();
        return router;
      }

      // --- Beto: sólo personal.ver ---
      var router = await montarComo(beto);

      expect(find.byKey(const Key('app_shell')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_personal')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_finanzas')), findsNothing);
      expect(find.byKey(const Key('nav_item_configuracion')), findsNothing);
      // Dashboard nunca tiene permiso propio — siempre visible.
      expect(find.byKey(const Key('nav_item_dashboard')), findsOneWidget);

      // Ruta directa a un módulo sin permiso: bloqueada, nunca construye ni
      // muestra su contenido.
      router.go('/finanzas');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceso_denegado_screen')), findsOneWidget);

      // Configuración también bloqueada — Beto no tiene `usuarios.administrar`.
      router.go('/configuracion');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceso_denegado_screen')), findsOneWidget);

      // El módulo que sí tiene permiso funciona normalmente.
      router.go('/personal');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceso_denegado_screen')), findsNothing);
      expect(find.byKey(const Key('empleados_boton_registrar')), findsOneWidget);

      // --- Carla: sólo usuarios.administrar ---
      router = await montarComo(carla);

      expect(find.byKey(const Key('nav_item_configuracion')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_personal')), findsNothing);

      router.go('/configuracion');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceso_denegado_screen')), findsNothing);
      expect(find.byKey(const Key('usuarios_boton_crear')), findsOneWidget);

      router.go('/personal');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceso_denegado_screen')), findsOneWidget);
    },
  );
}

/// Sesión fija para las pruebas de gate. Sólo sobrescribe `build()`: su
/// `revalidar()` heredado no sale a la red porque la sesión no nació de la cadena
/// SaaS — ver `_nacidaDelContexto` en `SesionController`.
class _SesionFijada extends SesionController {
  _SesionFijada(this._sesion);
  final SesionUsuario _sesion;

  @override
  SesionUsuario? build() => _sesion;
}
