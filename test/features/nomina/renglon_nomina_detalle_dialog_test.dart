// Etapa 15 — rediseño del detalle de Nómina como calculadora auditable.
// Pruebas de widget para la sección Asistencia (selector "Capturar
// por": Días laborados / Faltas, siempre uno derivado del otro — nunca
// un estado inconsistente donde ambos se capturan independientemente)
// y para "Cancelar no persiste cambios" (Parte 9 del pedido de
// Marlon).

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/widgets/renglon_nomina_detalle_dialog.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

/// Maestro: el escenario POSITIVO por omisión.
const _sesionMaestra = SesionUsuario(
  usuarioId: 'usuario-prueba',
  nombre: 'Usuario de prueba',
  nombreUsuario: 'prueba',
  esMaestro: true,
  permisos: {},
);

class _SesionDePrueba extends SesionController {
  _SesionDePrueba(this._sesion);
  final SesionUsuario _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

/// Etapa 4 — sin `nomina.corregir` (y sin ser Maestro): una Nómina
/// cerrada/pagada debe seguir siendo estrictamente de solo lectura.
/// Es el escenario NEGATIVO del archivo.
const _sesionSinCorregir = SesionUsuario(
  usuarioId: 'usuario-prueba',
  nombre: 'Usuario de prueba',
  nombreUsuario: 'prueba',
  esMaestro: false,
  permisos: {'nomina.ver', 'nomina.modificar'},
);

Finder _campoTexto(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == label),
      matching: find.byType(TextFormField),
    );

String _textoDe(WidgetTester tester, Finder campoTexto) => tester.widget<TextFormField>(campoTexto).controller!.text;

Finder _botonSegmento(String label) => find.byWidgetPredicate((w) => w is RisegButton && w.label == label);

void main() {
  late AppDatabase db;
  late String nominaEmpleadoId;
  late String nominaId;
  late NominaRepositoryImpl nominaRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    nominaRepo = NominaRepositoryImpl(db, AsignacionRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final generarNomina =
        GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

    await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Ana Karen',
            apellidoPaterno: 'Gómez',
            apellidoMaterno: const Value('Frogoso'),
            sexo: 'femenino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'GOFA900101MDFXXX01',
            rfc: 'GOFA9001019AB',
            nss: '10000000001',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: const Value(1100000),
          ),
        );

    final generado = (await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    nominaId = generado.nomina.id;
    nominaEmpleadoId = (await nominaRepo.listarEmpleados(generado.nomina.id)).single.id;

  });

  tearDown(() => db.close());

  Future<void> abrirDialogo(
    WidgetTester tester, {
    Size tamano = const Size(1440, 1400),
    bool nominaCerrada = false,
    // Etapa 3B: la autorización se revalida contra la base, así que el
    // escenario se SIEMBRA aquí y no en el `setUp` — este archivo usa
    // el mismo `usuarioId` para el caso Maestro y para el caso sin
    // `nomina.corregir`, y sembrar uno solo volvería positiva la prueba
    // negativa.
    SesionUsuario sesion = _sesionMaestra,
  }) async {
    await sembrarSesionEnBase(db, sesion);
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(() => _SesionDePrueba(sesion)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                key: const Key('abrir'),
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => RenglonNominaDetalleDialog(nominaEmpleadoId: nominaEmpleadoId, nominaCerrada: nominaCerrada),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();
  }

  testWidgets('capturar Días laborados = 9 (de 15 pagables) deriva Faltas = 6 automáticamente', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    await tester.tap(_botonSegmento(l10n.renglonNominaDetalleAsistenciaTabDiasLaborados));
    await tester.pumpAndSettle();

    await tester.enterText(_campoTexto(l10n.renglonNominaDetalleCampoDiasLaborados), '9');
    await tester.pumpAndSettle();

    expect(_textoDe(tester, _campoTexto(l10n.renglonNominaDetalleCampoFaltas)), '6');
  });

  testWidgets('capturar Faltas = 6 deriva Días laborados = 9 automáticamente (modo por defecto)', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    await tester.enterText(_campoTexto(l10n.renglonNominaDetalleCampoFaltas), '6');
    await tester.pumpAndSettle();

    expect(_textoDe(tester, _campoTexto(l10n.renglonNominaDetalleCampoDiasLaborados)), '9');
  });

  testWidgets('nunca permite laborados + faltas > días del periodo: capturar 99 faltas se acota a 15 (el techo de diasPagables)', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    await tester.enterText(_campoTexto(l10n.renglonNominaDetalleCampoFaltas), '99');
    await tester.pumpAndSettle();

    expect(
      _textoDe(tester, _campoTexto(l10n.renglonNominaDetalleCampoDiasLaborados)),
      '0',
      reason: 'faltas se acota a diasPagables (15), dejando 0 días laborados — nunca negativo',
    );
  });

  testWidgets('cancelar (cerrar con la X) tras editar un campo no persiste ningún cambio', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await abrirDialogo(tester);

    await tester.enterText(_campoTexto(l10n.renglonNominaDetalleCampoBono), '500.00');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Reabrir y confirmar que el bono persistido sigue en $0 — la
    // edición en memoria nunca llegó al repositorio.
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();

    expect(_textoDe(tester, _campoTexto(l10n.renglonNominaDetalleCampoBono)), '0.00');
  });

  testWidgets(
    'Nómina cerrada/pagada, usuario SIN nomina.corregir: sin selector de asistencia editable, '
    'sin botón "Guardar cambios" — solo lectura',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await abrirDialogo(tester, nominaCerrada: true, sesion: _sesionSinCorregir);

      expect(find.text(l10n.renglonNominaDetalleBotonGuardarCambios), findsNothing);
      expect(_botonSegmento(l10n.renglonNominaDetalleAsistenciaTabFaltas), findsNothing, reason: 'el selector Capturar por no aparece en modo lectura');
      expect(find.text(l10n.renglonNominaDetalleCampoMotivoCorreccion), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  group('Etapa 4 — corrección de una Nómina cerrada (usuario CON nomina.corregir)', () {
    testWidgets('muestra el aviso, el motivo y el botón "Guardar cambios" — editable', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await nominaRepo.cerrar(nominaId: nominaId, actorUsuarioId: 'usuario-prueba');
      await abrirDialogo(tester, nominaCerrada: true);

      expect(find.text(l10n.renglonNominaDetalleBotonGuardarCambios), findsOneWidget);
      expect(_campoTexto(l10n.renglonNominaDetalleCampoMotivoCorreccion), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('guardar sin motivo se rechaza — el domain lo exige, no solo la UI', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await nominaRepo.cerrar(nominaId: nominaId, actorUsuarioId: 'usuario-prueba');
      await abrirDialogo(tester, nominaCerrada: true);

      await tester.tap(find.text(l10n.renglonNominaDetalleBotonGuardarCambios));
      await tester.pumpAndSettle();

      expect(find.text(l10n.renglonNominaDetalleErrorMotivoRequerido), findsOneWidget);
    });

    testWidgets('con motivo capturado, guardar corrige el renglón y refleja el nuevo valor', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await nominaRepo.cerrar(nominaId: nominaId, actorUsuarioId: 'usuario-prueba');
      await abrirDialogo(tester, nominaCerrada: true);

      await tester.enterText(_campoTexto(l10n.renglonNominaDetalleCampoBono), '500.00');
      await tester.enterText(_campoTexto(l10n.renglonNominaDetalleCampoMotivoCorreccion), 'Se olvidó capturar el bono real');
      await tester.tap(find.text(l10n.renglonNominaDetalleBotonGuardarCambios));
      await tester.pumpAndSettle();

      expect(find.text(l10n.renglonNominaDetalleCambiosExito), findsOneWidget);
      expect(_textoDe(tester, _campoTexto(l10n.renglonNominaDetalleCampoBono)), '500.00');
    });
  });

  group('Responsive — cero RenderFlex overflow (Parte 17 del pedido)', () {
    testWidgets('1920×1080', (tester) async {
      await abrirDialogo(tester, tamano: const Size(1920, 1080));
      expect(tester.takeException(), isNull);
    });

    testWidgets('1366×768', (tester) async {
      await abrirDialogo(tester, tamano: const Size(1366, 768));
      expect(tester.takeException(), isNull);
    });

    testWidgets('~1000px de ancho (borde de AppBreakpoints.medium, dos columnas vs. apiladas)', (tester) async {
      await abrirDialogo(tester, tamano: const Size(1000, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho mínimo razonable soportado (~480px, todo apilado en una columna)', (tester) async {
      await abrirDialogo(tester, tamano: const Size(480, 1400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho mínimo razonable soportado, modo solo lectura (Nómina cerrada, sin nomina.corregir)', (tester) async {
      await abrirDialogo(tester, tamano: const Size(480, 1400), nominaCerrada: true, sesion: _sesionSinCorregir);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho mínimo razonable soportado, modo corrección (Nómina cerrada, con nomina.corregir)', (tester) async {
      await abrirDialogo(tester, tamano: const Size(480, 1400), nominaCerrada: true);
      expect(tester.takeException(), isNull);
    });
  });

  group('Navegación cruzada Nómina → Empleado (Etapa 17)', () {
    testWidgets('"Ver expediente del Empleado" cierra el diálogo y navega al expediente real', (tester) async {
      final router = GoRouter(
        initialLocation: '/nomina',
        routes: [
          GoRoute(
            path: '/nomina',
            builder: (context, state) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => RenglonNominaDetalleDialog(nominaEmpleadoId: nominaEmpleadoId, nominaCerrada: false),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/personal/empleados/:id',
            builder: (context, state) => Scaffold(body: Text('empleado-${state.pathParameters['id']}')),
          ),
        ],
      );

      await sembrarSesionEnBase(db, _sesionMaestra);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            sesionControllerProvider.overrideWith(() => _SesionDePrueba(_sesionMaestra)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await tester.tap(find.text(l10n.renglonNominaDetalleBotonVerEmpleado));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('empleado-'), findsOneWidget);
      expect(find.byType(RenglonNominaDetalleDialog), findsNothing, reason: 'el diálogo debe cerrarse antes de navegar');
    });
  });
}
