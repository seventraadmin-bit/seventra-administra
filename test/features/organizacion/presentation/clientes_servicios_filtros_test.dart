// Etapa 16 — pasada visual de Comercial. Filtros nuevos de Clientes
// (Estado / con-sin Servicios) y de Servicios (Cliente / Tipo /
// Estatus), más las columnas derivadas (Servicios/Personal por
// Cliente; Personal/Turno por Servicio) — todas agregadas en memoria
// sobre listados ya cargados en una sola consulta cada uno, nunca
// N+1.

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
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_state.dart';
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

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, Widget pantalla) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/lista',
    routes: [
      GoRoute(path: '/lista', builder: (context, state) => Scaffold(body: pantalla)),
      GoRoute(path: '/comercial/clientes/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
      GoRoute(path: '/comercial/servicios/:id', builder: (context, state) => const Scaffold(body: SizedBox.shrink())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
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

void main() {
  late AppDatabase db;

  tearDown(() => db.close());

  group('Clientes — filtros Estado y Servicios', () {
    late String activoConServicioId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final clienteRepo = ClienteRepositoryImpl(db);
      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

      await crearCliente.ejecutar(nombreComercial: 'Prospecto Sin Servicios');

      final activo = await crearCliente.ejecutar(nombreComercial: 'Activo Con Servicio');
      activoConServicioId = activo.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      await clienteRepo.cambiarEstatus(id: activoConServicioId, nuevo: EstatusCliente.activo);

      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
      final crearServicio = CrearServicioUseCase(
        servicioRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
      );
      final resultado = await crearServicio.ejecutar(
        clienteId: activoConServicioId,
        borrador: ServicioBorrador(nombre: 'Vigilancia Activo', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
      final servicioId = (resultado as GuardarServicioExitoso).servicio.id;

      // Activar de verdad (requiere Dirección operativa real) para que
      // "Servicios activos"/el filtro "Con servicios" cuenten este
      // Servicio — nunca se infla el conteo con un Servicio 'cotizado'.
      await servicioRepo.guardarDireccionOperativa(
        servicioId,
        const DireccionInput(
          calle: 'Av. Juárez',
          numeroExterior: '1',
          colonia: 'Centro',
          municipioAlcaldia: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
        ),
      );
      await servicioRepo.cambiarEstatus(id: servicioId, nuevo: EstatusServicio.activo);
    });

    testWidgets('filtro "Con servicios" deja solo al Cliente con Servicio', (tester) async {
      await _pumpScreen(tester, db, const ClientesListScreen());

      expect(find.text('Prospecto Sin Servicios'), findsOneWidget);
      expect(find.text('Activo Con Servicio'), findsOneWidget);

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      // Dropdowns visibles en orden: Estado (`RisegSelect<String?>`),
      // luego Servicios (`RisegSelect<FiltroServiciosCliente>`) — cada
      // uno con su propio tipo genérico, sin ambigüedad entre ambos.
      await tester.tap(find.byType(DropdownButtonFormField<FiltroServiciosCliente>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.clientesFiltroConServicios).last);
      await tester.pumpAndSettle();

      expect(find.text('Prospecto Sin Servicios'), findsNothing);
      expect(find.text('Activo Con Servicio'), findsOneWidget);
    });

    testWidgets('filtro Estado deja solo a los Clientes activos', (tester) async {
      await _pumpScreen(tester, db, const ClientesListScreen());

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.clienteEstatusActivo).last);
      await tester.pumpAndSettle();

      expect(find.text('Prospecto Sin Servicios'), findsNothing);
      expect(find.text('Activo Con Servicio'), findsOneWidget);
    });

    testWidgets('columna Servicios cuenta solo Servicios con estatus activo', (tester) async {
      await _pumpScreen(tester, db, const ClientesListScreen());
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.clientesCantidadServicios(0)), findsOneWidget);
      expect(find.text(l10n.clientesCantidadServicios(1)), findsOneWidget);
    });
  });

  group('Servicios — filtros Cliente/Tipo/Estatus y columna Personal', () {
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final clienteRepo = ClienteRepositoryImpl(db);
      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
      final crearServicio = CrearServicioUseCase(
        servicioRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
      );

      final sportium = await crearCliente.ejecutar(nombreComercial: 'Sportium');
      final sportiumId = sportium.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      await crearServicio.ejecutar(
        clienteId: sportiumId,
        borrador: ServicioBorrador(nombre: 'Sportium Toluca', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );

      final construcciones = await crearCliente.ejecutar(nombreComercial: 'Construcciones Habitacionales');
      final construccionesId = construcciones.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      await crearServicio.ejecutar(
        clienteId: construccionesId,
        borrador: ServicioBorrador(nombre: 'Mirabilia', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
    });

    testWidgets('filtro Cliente deja solo los Servicios de ese Cliente', (tester) async {
      await _pumpScreen(tester, db, const ServiciosListScreen());

      expect(find.text('Sportium Toluca'), findsOneWidget);
      expect(find.text('Mirabilia'), findsOneWidget);

      // Dropdowns visibles en orden: Cliente, Tipo, Estatus — los tres
      // `RisegSelect<String?>`, así que el de Cliente es el primero.
      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sportium').last);
      await tester.pumpAndSettle();

      expect(find.text('Sportium Toluca'), findsOneWidget);
      expect(find.text('Mirabilia'), findsNothing);
    });

    testWidgets('columna Personal se calcula sin crash cuando ningún Servicio tiene personal asignado', (tester) async {
      await _pumpScreen(tester, db, const ServiciosListScreen());

      // Ninguno de los dos Servicios tiene una asignación vigente —
      // ambas filas deben mostrar '0', nunca un error ni un espacio en
      // blanco por una consulta fallida.
      expect(find.text('0'), findsNWidgets(2));
    });
  });

  group('Clientes/Servicios — división Vigentes/Finalizados (pedido explícito)', () {
    testWidgets('Clientes: por defecto solo se ven los Vigentes; el chip Finalizados muestra terminado/descartado', (tester) async {
      db = AppDatabase(NativeDatabase.memory());
      final clienteRepo = ClienteRepositoryImpl(db);
      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

      final activo = await crearCliente.ejecutar(nombreComercial: 'Cliente Vigente');
      final activoId = activo.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      await clienteRepo.cambiarEstatus(id: activoId, nuevo: EstatusCliente.activo);

      final terminado = await crearCliente.ejecutar(nombreComercial: 'Cliente Terminado');
      final terminadoId = terminado.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      await clienteRepo.cambiarEstatus(id: terminadoId, nuevo: EstatusCliente.activo);
      await clienteRepo.cambiarEstatus(id: terminadoId, nuevo: EstatusCliente.terminado);

      final descartado = await crearCliente.ejecutar(nombreComercial: 'Cliente Descartado');
      final descartadoId = descartado.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      await clienteRepo.cambiarEstatus(id: descartadoId, nuevo: EstatusCliente.descartado);

      await _pumpScreen(tester, db, const ClientesListScreen());

      expect(find.text('Cliente Vigente'), findsOneWidget);
      expect(find.text('Cliente Terminado'), findsNothing, reason: 'la vista por defecto es Vigentes');
      expect(find.text('Cliente Descartado'), findsNothing, reason: 'la vista por defecto es Vigentes');

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await tester.tap(find.text(l10n.clientesGrupoFinalizados));
      await tester.pumpAndSettle();

      expect(find.text('Cliente Vigente'), findsNothing);
      expect(find.text('Cliente Terminado'), findsOneWidget);
      expect(find.text('Cliente Descartado'), findsOneWidget, reason: 'un prospecto descartado también es una relación ya cerrada');

      await tester.tap(find.text(l10n.clientesGrupoVigentes));
      await tester.pumpAndSettle();
      expect(find.text('Cliente Vigente'), findsOneWidget);
      expect(find.text('Cliente Terminado'), findsNothing);
    });

    testWidgets('Servicios: por defecto solo se ven los Vigentes; el chip Finalizados muestra los terminados', (tester) async {
      db = AppDatabase(NativeDatabase.memory());
      final clienteRepo = ClienteRepositoryImpl(db);
      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final asignacionRepo = AsignacionServicioRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
      final crearServicio = CrearServicioUseCase(
        servicioRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
      );

      final cliente = await crearCliente.ejecutar(nombreComercial: 'Mirabilia');
      final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

      await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(nombre: 'Servicio Vigente', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );

      final finalizado = await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(nombre: 'Servicio Terminado', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
      final finalizadoId = (finalizado as GuardarServicioExitoso).servicio.id;
      await servicioRepo.cambiarEstatus(id: finalizadoId, nuevo: EstatusServicio.terminado, fechaTermino: DateTime(2026, 8, 31));

      await _pumpScreen(tester, db, const ServiciosListScreen());

      expect(find.text('Servicio Vigente'), findsOneWidget);
      expect(find.text('Servicio Terminado'), findsNothing, reason: 'la vista por defecto es Vigentes');

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await tester.tap(find.text(l10n.serviciosGrupoFinalizados));
      await tester.pumpAndSettle();

      expect(find.text('Servicio Vigente'), findsNothing);
      expect(find.text('Servicio Terminado'), findsOneWidget);
    });
  });
}
