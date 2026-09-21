// Etapa 16, evolución visual final de Personal — cubre el resumen
// superior de "Nóminas": solo se muestra cuando existe una Nómina
// `cerrada` real (nunca un "total estimado" para un periodo Borrador
// sin cerrar todavía), y que el listado no produce overflow en los
// breakpoints soportados ni en modo oscuro.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_list_screen.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

const _anchos = [
  Size(1536, 864),
  Size(1366, 768),
  Size(1024, 768),
  Size(700, 900),
  Size(500, 900),
];

void main() {
  late AppDatabase db;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);

    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina =
        GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(codigoSecuencia));
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
  });

  tearDown(() => db.close());

  Future<void> crearEmpleadoDePrueba() {
    return db.into(db.empleado).insert(
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
            sueldoMensualAdministrativo: const Value(1500000),
          ),
        );
  }

  Future<void> pumpScreen(WidgetTester tester, {required Size tamano, ThemeData? tema}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/personal/nomina',
      routes: [
        GoRoute(path: '/personal/nomina', builder: (context, state) => const Scaffold(body: NominasListScreen())),
        GoRoute(path: '/personal/nomina/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
        ],
        child: MaterialApp.router(
          theme: tema ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Resumen superior — solo con una Nómina cerrada real', () {
    testWidgets('Nómina Borrador (sin cerrar): nunca se muestra un "total a pagar" inventado', (tester) async {
      await crearEmpleadoDePrueba();
      await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      await pumpScreen(tester, tamano: const Size(1366, 768));

      expect(tester.takeException(), isNull);
      expect(find.text('Próxima nómina'), findsNothing);
      expect(find.text('Total a pagar'), findsNothing);
    });

    testWidgets('Nómina cerrada: el resumen aparece con el total real ya calculado', (tester) async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);

      await pumpScreen(tester, tamano: const Size(1366, 768));

      expect(tester.takeException(), isNull);
      expect(find.text('Próxima nómina'), findsOneWidget);
      expect(find.text('Personal incluido'), findsOneWidget);
      expect(find.text('Total a pagar'), findsOneWidget);
      expect(find.text('1 empleados'), findsOneWidget);
    });
  });

  group('Listado — responsive sin overflow', () {
    setUp(() async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    });

    for (final tamano in _anchos) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await pumpScreen(tester, tamano: tamano);

        expect(tester.takeException(), isNull, reason: 'nunca debe aparecer RenderFlex overflow en el listado de Nóminas');
        expect(find.byIcon(Icons.chevron_right), findsWidgets, reason: 'acción discreta de fila navegable, igual que Plantilla activa');
      });
    }

    testWidgets('modo oscuro, ancho angosto (700×900): cero overflow', (tester) async {
      await pumpScreen(tester, tamano: const Size(700, 900), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });

    testWidgets('modo oscuro, ancho amplio (1536×864): cero overflow', (tester) async {
      await pumpScreen(tester, tamano: const Size(1536, 864), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });
}
