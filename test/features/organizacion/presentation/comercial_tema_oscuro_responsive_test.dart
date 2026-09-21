// Etapa 16 — pasada visual de Comercial. Smoke de tema oscuro +
// breakpoints representativos (1366×768 y ~500px) para las 5 pantallas
// tocadas en esta pasada: Clientes, expediente de Cliente, Servicios,
// expediente de Servicio y Agenda. Mismo criterio que el resto de
// RISEG ONE: sin herramienta de captura de pantalla, la evidencia es
// "cero overflow / cero excepción" (`tester.takeException()`), nunca
// una comparación de píxeles.

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
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_list_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
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

Future<void> _pumpOscuro(
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
      GoRoute(path: '/comercial/agenda', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
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
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _anchosRepresentativos = [Size(1366, 768), Size(500, 900)];

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late String clienteId;
  late String servicioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_comercial_tema_oscuro_test_');

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

  for (final tamano in _anchosRepresentativos) {
    final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}';

    testWidgets('Clientes ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const ClientesListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
      expect(find.text('Sportium'), findsWidgets);
    });

    testWidgets('Servicios ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const ServiciosListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
      expect(find.text('Vigilancia Sportium Toluca'), findsOneWidget);
    });

    testWidgets('Expediente de Cliente ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: ClienteExpedienteScreen(clienteId: clienteId), tamano: tamano);
      expect(tester.takeException(), isNull);
      expect(find.text('Vigilancia Sportium Toluca'), findsOneWidget);
    });

    testWidgets('Expediente de Servicio ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: ServicioExpedienteScreen(servicioId: servicioId), tamano: tamano);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Sportium ·'), findsOneWidget);
    });

    testWidgets('Agenda ($etiqueta, oscuro): cero overflow', (tester) async {
      await _pumpOscuro(tester, db, tempDir, child: const AgendaListScreen(), tamano: tamano);
      expect(tester.takeException(), isNull);
    });
  }
}
