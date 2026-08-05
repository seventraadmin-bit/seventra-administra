// Pruebas de la pantalla de expediente de Servicio — edición de datos
// generales, y las acciones de estatus (Activar deshabilitado sin
// Dirección operativa, Suspender, Terminar con fecha efectiva).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';

Future<({String servicioId, String clienteId})> _crearServicio(AppDatabase db) async {
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final clienteRepo = ClienteRepositoryImpl(db);
  final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
  final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
  final crearServicio = CrearServicioUseCase(ServicioRepositoryImpl(db), generarCodigo, validator);

  final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
  final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
  final creado = await crearServicio.ejecutar(
    clienteId: clienteId,
    borrador: ServicioBorrador(
      nombre: 'Vigilancia Sportium Toluca',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      fechaInicio: DateTime(2026, 1, 1),
    ),
  );
  return (servicioId: (creado as GuardarServicioExitoso).servicio.id, clienteId: clienteId);
}

Future<EntidadFiscalData> _crearEntidadFiscal(AppDatabase db, String clienteId) async {
  final clienteRepo = ClienteRepositoryImpl(db);
  final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
  final validator = EntidadFiscalValidator(clienteRepo, entidadFiscalRepo);
  final crear = CrearEntidadFiscalUseCase(entidadFiscalRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), validator);
  final creada = await crear.ejecutar(
    clienteId: clienteId,
    borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AA1'),
  );
  return (creada as GuardarEntidadFiscalExitoso).entidadFiscal;
}

Future<ContactoData> _crearContacto(AppDatabase db, String clienteId) {
  return ClienteRepositoryImpl(
    db,
  ).agregarContacto(ContactoCompanion.insert(clienteId: clienteId, nombre: 'Juan Pérez', tipo: 'comercial'));
}

Future<SucursalData> _crearSucursal(AppDatabase db) async {
  final crear = CrearSucursalUseCase(SucursalRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
  final r = await crear.ejecutar(nombre: 'Sucursal Centro', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
  return r.when(ok: (s) => s, failure: (_) => throw StateError('no debería fallar'));
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, String servicioId) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ServicioExpedienteScreen(servicioId: servicioId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late String servicioId;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final creado = await _crearServicio(db);
    servicioId = creado.servicioId;
    clienteId = creado.clienteId;
  });

  tearDown(() => db.close());

  testWidgets('muestra el Servicio recién creado, cotizado, sin Dirección operativa', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text('Vigilancia Sportium Toluca'), findsWidgets);
    expect(find.text(l10n.servicioEstatusCotizado), findsOneWidget);
  });

  testWidgets('Activar está deshabilitado y muestra la indicación de falta de Dirección', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final botonActivar = tester.widget<OutlinedButton>(
      find.descendant(of: find.byKey(const Key('servicio_boton_activar')), matching: find.byType(OutlinedButton)),
    );
    expect(botonActivar.onPressed, isNull);
    expect(find.text(l10n.servicioBotonActivarAyudaSinDireccion), findsOneWidget);
  });

  testWidgets('editar nombre y observaciones', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('servicio_expediente_boton_editar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Vigilancia Sportium Renombrada');
    await tester.tap(find.byKey(const Key('servicio_expediente_boton_guardar')));
    await tester.pumpAndSettle();

    expect(find.text('Vigilancia Sportium Renombrada'), findsWidgets);
    expect(find.text(l10n.servicioGuardadoExito), findsOneWidget);
  });

  testWidgets('suspender un Servicio cotizado no requiere Dirección operativa', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('servicio_boton_suspender')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text(l10n.servicioBotonSuspender).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioEstatusSuspendido), findsOneWidget);
    expect(find.text(l10n.servicioCambiarEstatusExito), findsOneWidget);
  });

  testWidgets('terminar sin fecha previa exige la fecha efectiva dentro de la misma acción', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('servicio_boton_terminar')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget, reason: 'pide la fecha efectiva, no la asigna sola');

    final campoFecha = find.byType(TextFormField).first;
    await tester.tap(campoFecha);
    await tester.pumpAndSettle();
    final dialogoSelector = find.byType(Dialog).last;
    await tester.tap(find.descendant(of: dialogoSelector, matching: find.byType(TextButton)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioTerminarBotonConfirmar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioEstatusTerminado), findsOneWidget);
  });

  testWidgets('Vinculaciones sin asignaciones muestra "Sin asignar" y el Cliente de solo lectura', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text('Sportium'), findsOneWidget, reason: 'Cliente de solo lectura, sin icono de acción');
    expect(
      find.descendant(of: find.byKey(const Key('servicio_vinculacion_cliente')), matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(find.text(l10n.servicioVinculacionSinAsignar), findsNWidgets(4));
  });

  testWidgets('asignar una Entidad fiscal del mismo Cliente vía el diálogo selector', (tester) async {
    await _crearEntidadFiscal(db, clienteId);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('servicio_vinculacion_entidad_fiscal')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sportium SA de CV').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text('Sportium SA de CV'), findsOneWidget);
    expect(find.text(l10n.servicioAsignarEntidadFiscalExito), findsOneWidget);
  });

  testWidgets('quitar una Entidad fiscal ya asignada', (tester) async {
    final entidad = await _crearEntidadFiscal(db, clienteId);
    await ServicioRepositoryImpl(db).asignarEntidadFiscal(servicioId: servicioId, entidadFiscalId: entidad.id);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    final iconos = find.descendant(
      of: find.byKey(const Key('servicio_vinculacion_entidad_fiscal')),
      matching: find.byType(IconButton),
    );
    expect(iconos, findsNWidgets(2), reason: 'editar + quitar, una vez asignada');
    await tester.tap(iconos.last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioQuitarEntidadFiscalExito), findsOneWidget);
    expect(find.text('Sportium SA de CV'), findsNothing);
  });

  testWidgets('asignar un Responsable del Cliente (Contacto activo)', (tester) async {
    await _crearContacto(db, clienteId);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('servicio_vinculacion_responsable_cliente')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juan Pérez').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text(l10n.servicioAsignarResponsableClienteExito), findsOneWidget);
  });

  testWidgets('asignar una Sucursal administrativa', (tester) async {
    await _crearSucursal(db);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('servicio_vinculacion_sucursal_administrativa')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sucursal Centro').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text('Sucursal Centro'), findsOneWidget);
    expect(find.text(l10n.servicioAsignarSucursalAdministrativaExito), findsOneWidget);
  });

  testWidgets('editar el Responsable interno como texto libre', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('servicio_vinculacion_responsable_interno')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Ana López');
    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text('Ana López'), findsOneWidget);
    expect(find.text(l10n.servicioResponsableInternoGuardadoExito), findsOneWidget);
  });

  testWidgets('agregar una Dirección operativa completa habilita el botón Activar', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('servicio_boton_agregar_direccion_operativa')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Av. Toluca');
    await tester.enterText(find.byType(TextFormField).at(1), '50');
    await tester.enterText(find.byType(TextFormField).at(3), 'Centro');
    await tester.enterText(find.byType(TextFormField).at(4), 'Toluca');
    await tester.enterText(find.byType(TextFormField).at(6), 'Estado de México');
    await tester.enterText(find.byType(TextFormField).at(7), '50000');

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioDireccionOperativaGuardadoExito), findsOneWidget);
    expect(find.text(l10n.servicioBotonActivarAyudaSinDireccion), findsNothing);

    final botonActivar = tester.widget<OutlinedButton>(
      find.descendant(of: find.byKey(const Key('servicio_boton_activar')), matching: find.byType(OutlinedButton)),
    );
    expect(botonActivar.onPressed, isNotNull);
  });
}
