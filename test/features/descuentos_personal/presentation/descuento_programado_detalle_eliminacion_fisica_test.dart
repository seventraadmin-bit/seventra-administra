// Pedido explícito (screenshot): en el expediente de un descuento
// programado ya cancelado, el Maestro debe poder eliminarlo por
// pruebas; también debe existir una flecha de regreso, igual que en
// el expediente de Nómina.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuento_programado_detalle_screen.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_list_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

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

class _SesionNoMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'descuentos.ver', 'descuentos.crear', 'descuentos.corregir', 'descuentos.cancelar'},
    );
  }
}

Future<GoRouter> _pumpConRouter(WidgetTester tester, AppDatabase db, {required bool esMaestro}) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/personal/descuentos',
    routes: [
      GoRoute(
        path: '/personal/descuentos',
        builder: (context, state) => const Scaffold(body: DescuentosPersonalListScreen()),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => DescuentoProgramadoDetalleScreen(descuentoProgramadoId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: '/personal/empleados/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(esMaestro ? _SesionMaestroDePrueba.new : _SesionNoMaestroDePrueba.new),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late AppDatabase db;

  Future<String> crearDescuentoCanceladoDePrueba() async {
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    final registrar = RegistrarDescuentoProgramadoUseCase(descuentoRepo, empleadoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final cancelarSaldo = CancelarSaldoDescuentoProgramadoUseCase(descuentoRepo);

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    final resultado = await registrar.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 60000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 2, 5),
    ) as RegistrarDescuentoProgramadoExitoso;

    await cancelarSaldo.ejecutar(descuentoProgramadoId: resultado.descuento.id, motivo: 'Error de captura');
    return resultado.descuento.id;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // El Maestro de prueba necesita un `Usuario` real: `EliminacionFisicaEvento
    // .actorUsuarioId` es una FK real (`ON DELETE SET NULL`, nunca texto libre).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-maestro'), nombre: 'Maestro de prueba', nombreUsuario: 'maestro', passwordHash: 'x'),
        );
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-normal', nombre: 'Usuario de prueba', nombreUsuario: 'normal', esMaestro: false, permisos: {'descuentos.ver', 'descuentos.crear', 'descuentos.corregir', 'descuentos.cancelar'}, ));
  });

  tearDown(() => db.close());

  testWidgets('el Maestro ve la flecha de regreso y la opción de eliminar físicamente en un descuento cancelado', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    final descuentoId = await crearDescuentoCanceladoDePrueba();
    await _pumpConRouter(tester, db, esMaestro: true);

    await tester.tap(find.byKey(const Key('descuentos_personal_grupo_cancelados')));
    await tester.pumpAndSettle();

    expect(find.text('Saldo cancelado'), findsOneWidget);
    await tester.tap(find.textContaining('Juan').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.byType(DescuentoProgramadoDetalleScreen), findsOneWidget);
    // Flecha de regreso — mismo criterio que `NominaDetalleScreen`:
    // `Scaffold(appBar: AppBar(...))` la provee automáticamente cuando
    // el `Navigator` de la rama tiene algo que retroceder.
    expect(find.byTooltip('Atrás'), findsOneWidget);
    expect(find.byKey(const Key('descuento_programado_detalle_menu_acciones')), findsOneWidget);

    await tester.tap(find.byKey(const Key('descuento_programado_detalle_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('descuento_programado_boton_eliminar_fisicamente')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'Registro de prueba');
    await tester.tap(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar));
    await tester.pumpAndSettle();

    // Regresó al listado, y el descuento eliminado ya no aparece.
    expect(find.byType(DescuentosPersonalListScreen), findsOneWidget);
    expect(find.byType(DescuentoProgramadoDetalleScreen), findsNothing);
    expect(find.text('Saldo cancelado'), findsNothing);

    expect(await DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)).obtenerPorId(descuentoId), isNull);
  });

  testWidgets('un usuario no-Maestro no ve la opción de eliminar físicamente', (tester) async {
    await crearDescuentoCanceladoDePrueba();
    await _pumpConRouter(tester, db, esMaestro: false);

    await tester.tap(find.byKey(const Key('descuentos_personal_grupo_cancelados')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Juan').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.byType(DescuentoProgramadoDetalleScreen), findsOneWidget);
    expect(find.byTooltip('Atrás'), findsOneWidget);
    expect(find.byKey(const Key('descuento_programado_detalle_menu_acciones')), findsNothing);
  });
}
