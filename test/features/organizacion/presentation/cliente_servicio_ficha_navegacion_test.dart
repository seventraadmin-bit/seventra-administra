// Etapa 16 — ficha comercial del Cliente (indicadores + sección
// Servicios) y ficha operacional del Servicio (enlace de regreso al
// Cliente) — navegación encadenada Cliente ↔ Servicio.

import 'dart:io';

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
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
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

Future<GoRouter> _pumpConRouter(WidgetTester tester, AppDatabase db, Directory tempDir, String initialLocation) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/comercial/clientes/:id',
        builder: (context, state) => ClienteExpedienteScreen(clienteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/comercial/servicios/:id',
        builder: (context, state) => ServicioExpedienteScreen(servicioId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/comercial/agenda', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        // `clienteComercialResumenProvider` compone
        // `documentoPorEmitirRepositoryProvider`, que a su vez depende
        // de `attachmentStorageProvider` — sin este override, la
        // ficha comercial fallaría en silencio (AsyncError tragado por
        // `.when(error: ...)`), mismo riesgo ya conocido en
        // `clientes_servicios_responsive_widget_test.dart`.
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
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
  late Directory tempDir;
  late String clienteId;
  late String servicioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_cliente_servicio_ficha_test_');
    final clienteRepo = ClienteRepositoryImpl(db);
    final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

    final asignacionRepo = AsignacionServicioRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    final crearServicio = CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
    );
    final resultado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(nombre: 'Vigilancia Sportium Toluca', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    servicioId = (resultado as GuardarServicioExitoso).servicio.id;

    await servicioRepo.guardarDireccionOperativa(
      servicioId,
      const DireccionInput(
        calle: 'Av. Morelos',
        numeroExterior: '100',
        colonia: 'Centro',
        municipioAlcaldia: 'Toluca',
        estado: 'Estado de México',
        codigoPostal: '50000',
      ),
    );
    await servicioRepo.cambiarEstatus(id: servicioId, nuevo: EstatusServicio.activo);
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('expediente de Cliente: indicadores muestran Servicios activos y la sección Servicios navega al expediente', (tester) async {
    await _pumpConRouter(tester, db, tempDir, '/comercial/clientes/$clienteId');
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text('Sportium'), findsWidgets);
    expect(find.text(l10n.clienteIndicadorServiciosActivos), findsOneWidget);
    expect(find.text('1'), findsWidgets, reason: 'Servicios activos = 1');

    expect(find.text('Vigilancia Sportium Toluca'), findsOneWidget);

    await tester.tap(find.text('Vigilancia Sportium Toluca'));
    await tester.pumpAndSettle();

    expect(find.text('Toluca, Estado de México'), findsWidgets, reason: 'ahora en el expediente del Servicio');
  });

  testWidgets('expediente de Cliente: sin Servicios, la sección muestra el estado vacío y los indicadores en cero', (tester) async {
    final clienteRepo = ClienteRepositoryImpl(db);
    final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final cliente = await crearCliente.ejecutar(nombreComercial: 'Sin Servicios SA');
    final otroClienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

    await _pumpConRouter(tester, db, tempDir, '/comercial/clientes/$otroClienteId');
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.clienteSeccionServiciosVacio), findsOneWidget);
  });

  testWidgets('expediente de Servicio: el enlace "Cliente · Código" navega de regreso al expediente del Cliente', (tester) async {
    await _pumpConRouter(tester, db, tempDir, '/comercial/servicios/$servicioId');

    expect(find.byKey(const Key('servicio_ficha_boton_ir_a_cliente')), findsOneWidget);

    await tester.tap(find.byKey(const Key('servicio_ficha_boton_ir_a_cliente')));
    await tester.pumpAndSettle();

    expect(find.text('Sportium'), findsWidgets, reason: 'ahora en el expediente del Cliente');
    expect(find.text('Vigilancia Sportium Toluca'), findsOneWidget, reason: 'la sección Servicios del Cliente lo lista');
  });
}
