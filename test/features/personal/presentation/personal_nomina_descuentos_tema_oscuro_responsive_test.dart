// Etapa 17 — pasada UX/UI de Personal. Smoke de tema oscuro +
// breakpoints (1366×768 y ~500px) para las 3 pantallas de expediente
// tocadas que no tenían ninguna prueba propia: Expediente de Empleado
// (cabecera nueva + menú ⋯), Expediente de Nómina (cabecera + menú ⋯ +
// resumen) y Expediente de Descuento programado (enlace nuevo al
// Empleado). Mismo criterio que el resto de RISEG ONE: sin
// herramienta de captura de pantalla, la evidencia es "cero overflow /
// cero excepción", nunca una comparación de píxeles.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuento_programado_detalle_screen.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nomina_detalle_screen.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleado_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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
  Directory tempDir, {
  required Widget child,
  required Size tamano,
  required ThemeData tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/pantalla',
    routes: [
      // `Scaffold` aquí simula el shell real (`PersonalShellScreen`)
      // que ya envuelve `DescuentoProgramadoDetalleScreen` en
      // producción — esa pantalla no trae su propio `Scaffold`
      // (confirmado por el error real "No Material widget found" al
      // pumpearla sin uno). `NominaDetalleScreen`/`EmpleadoExpedienteScreen`
      // ya traen el suyo propio; anidar un segundo `Scaffold` es
      // inofensivo para ellas.
      GoRoute(path: '/pantalla', builder: (context, state) => Scaffold(body: child)),
      GoRoute(path: '/personal/empleados/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
      GoRoute(path: '/personal/descuentos', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
      GoRoute(path: '/comercial/servicios/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
      child: MaterialApp.router(
        theme: tema,
        // Solo `theme` + `ThemeMode.light` — así el `ThemeData` que se
        // renderiza es exactamente `tema` sin importar si semánticamente
        // es claro u oscuro (bug real encontrado: fijar `themeMode:
        // ThemeMode.dark` aquí hacía que AMBAS iteraciones del loop
        // (claro/oscuro) se renderizaran siempre en oscuro).
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _anchos = [Size(1366, 768), Size(500, 900)];

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_personal_tema_oscuro_test_');
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<String> crearEmpleadoDePrueba() async {
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
            sueldoMensualAdministrativo: const Value(1500000),
          ),
        );
    return empleado.id;
  }

  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};
  for (final entradaTema in temas.entries) {
    final etiquetaTema = entradaTema.key;
    final tema = entradaTema.value;

    for (final tamano in _anchos) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}, $etiquetaTema';

      testWidgets('Expediente de Empleado ($etiqueta): cero overflow', (tester) async {
        final empleadoId = await crearEmpleadoDePrueba();
        await _pump(
          tester,
          db,
          tempDir,
          child: EmpleadoExpedienteScreen(empleadoId: empleadoId),
          tamano: tamano,
          tema: tema,
        );

        expect(tester.takeException(), isNull);
        // "Juan Pérez" aparece dos veces (AppBar + cabecera del
        // expediente) — ambas legítimas, nunca duplicado de datos.
        expect(find.text('Juan Pérez'), findsWidgets);
        // Maestro-only: el menú ⋯ de acciones secundarias/destructivas
        // debe existir (nunca un botón rojo permanente en la cabecera).
        expect(find.byKey(const Key('empleado_expediente_menu_acciones')), findsOneWidget);
      });

      testWidgets('Expediente de Nómina ($etiqueta): cero overflow', (tester) async {
        final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
        final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
        final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
        final catalogoRepo = CatalogoRepositoryImpl(db);
        final puestoRepo = PuestoRepositoryImpl(db);
        final codigoSecuencia = CodigoSecuenciaService(db);
        final nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
        final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
        final generarNomina = GenerarNominaUseCase(
          nominaRepo,
          empleadoRepo,
          puestoRepo,
          catalogoRepo,
          resolverSueldo,
          GenerarCodigoUseCase(codigoSecuencia),
        );

        await crearEmpleadoDePrueba();
        final generado =
            (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;

        await _pump(
          tester,
          db,
          tempDir,
          child: NominaDetalleScreen(nominaId: generado.nomina.id),
          tamano: tamano,
          tema: tema,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Empleados'), findsOneWidget);
        // "Percepciones" aparece dos veces (tarjeta de resumen +
        // encabezado de columna de la tabla) — ambas legítimas, mismo
        // significado real, nunca una segunda cifra distinta.
        expect(find.text('Percepciones'), findsWidgets);
        expect(find.text('Total pagado'), findsOneWidget);
        // Maestro-only: eliminar físicamente vive en el menú ⋯, nunca
        // como botón rojo permanente.
        expect(find.byKey(const Key('nomina_detalle_menu_acciones')), findsOneWidget);
      });

      testWidgets('Expediente de Descuento programado ($etiqueta): cero overflow', (tester) async {
        final empleadoId = await crearEmpleadoDePrueba();
        final repo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
        final useCase = RegistrarDescuentoProgramadoUseCase(
          repo,
          EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
          GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        );
        final resultado = await useCase.ejecutar(
          empleadoId: empleadoId,
          tipo: 'prestamo',
          fechaRegistro: DateTime(2026, 1, 1),
          importeOriginal: 300000,
          numeroCuotas: 3,
          fechaPrimeraCuota: DateTime(2026, 1, 20),
        ) as RegistrarDescuentoProgramadoExitoso;

        await _pump(
          tester,
          db,
          tempDir,
          child: DescuentoProgramadoDetalleScreen(descuentoProgramadoId: resultado.descuento.id),
          tamano: tamano,
          tema: tema,
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('descuento_programado_boton_ver_empleado')), findsOneWidget);
        expect(find.textContaining('Juan Pérez'), findsOneWidget);
      });
    }
  }
}
