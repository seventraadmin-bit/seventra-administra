// Etapa 16 — evolución visual del Design System. Verifica que Clientes
// y Servicios (2 de las 3 pantallas piloto) no producen overflow en los
// breakpoints soportados por RISEG ONE (1366×768, 1024×768, ~700px y
// ~500px), con datos reales: un Cliente CON logo, uno SIN logo
// (fallback de iniciales), un Servicio CON Dirección operativa
// (ubicación real) y uno SIN ella (nunca inventada).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_logo_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicios_list_screen.dart';
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

Future<void> _pumpScreen(
  WidgetTester tester,
  AppDatabase db,
  Directory tempDir, {
  required Widget child,
  required Size tamano,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/pantalla',
    routes: [
      GoRoute(path: '/pantalla', builder: (context, state) => Scaffold(body: child)),
      GoRoute(path: '/comercial/clientes/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
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
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _anchos = [
  Size(1366, 768),
  Size(1024, 768),
  Size(700, 900),
  Size(500, 900),
];

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_clientes_servicios_visual_test_');
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  group('Clientes — responsive sin overflow (con y sin logo)', () {
    setUp(() async {
      final clienteRepo = ClienteRepositoryImpl(db);
      final registrarLogo = RegistrarLogoClienteUseCase(clienteRepo, AttachmentRepository(db), AttachmentStorage(tempDir.path));

      await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sin Logo Corporativo'));

      final conLogo = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Sportium Cuautitlán'));
      final archivoLogo = '${tempDir.path}/logo.png';
      File(archivoLogo).writeAsStringSync('contenido logo');
      await registrarLogo.ejecutar(
        clienteId: conLogo.id,
        sourceFilePath: archivoLogo,
        originalFileName: 'logo.png',
        mimeType: 'image/png',
      );
    });

    for (final tamano in _anchos) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await _pumpScreen(tester, db, tempDir, child: const ClientesListScreen(), tamano: tamano);

        expect(tester.takeException(), isNull, reason: 'nunca debe aparecer RenderFlex overflow en Clientes');
        expect(find.text('Sin Logo Corporativo'), findsOneWidget);
        expect(find.text('Sportium Cuautitlán'), findsOneWidget);
      });
    }
  });

  group('Servicios — responsive sin overflow (con y sin ubicación real)', () {
    setUp(() async {
      final clienteRepo = ClienteRepositoryImpl(db);
      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final crearServicio = CrearServicioUseCase(
        servicioRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        ServicioValidator(clienteRepo, catalogoRepo),
      );

      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));

      final conUbicacion = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(nombre: 'Sportium Toluca', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
      final servicioConUbicacion = (conUbicacion as GuardarServicioExitoso).servicio;
      await servicioRepo.guardarDireccionOperativa(
        servicioConUbicacion.id,
        const DireccionInput(
          calle: 'Av. Morelos',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
        ),
      );

      await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(nombre: 'Sportium Interlomas', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
    });

    for (final tamano in _anchos) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow', (tester) async {
        await _pumpScreen(tester, db, tempDir, child: const ServiciosListScreen(), tamano: tamano);

        expect(tester.takeException(), isNull, reason: 'nunca debe aparecer RenderFlex overflow en Servicios');
        expect(find.text('Toluca, Estado de México'), findsOneWidget);
        expect(find.text('Ubicación no registrada'), findsOneWidget, reason: 'sin Dirección operativa, nunca se inventa una ubicación');
      });
    }
  });
}
