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
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';

Future<({String servicioId, String clienteId})> _crearServicio(AppDatabase db) async {
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final clienteRepo = ClienteRepositoryImpl(db);
  final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
  final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
  final crearServicio = CrearServicioUseCase(ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), generarCodigo, validator);

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

Future<PuestoData> _crearPuesto(AppDatabase db) {
  return PuestoRepositoryImpl(db).crear(
    PuestoCompanion.insert(
      codigo: 'PUE-0001',
      nombre: 'Guardia',
      areaId: SeedIds.areaOperaciones,
      tipo: 'operativo',
      nivelJerarquico: 5,
    ),
  );
}

Future<String> _crearLineaComercial(AppDatabase db, String servicioId, String puestoId) async {
  final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
  final catalogoRepo = CatalogoRepositoryImpl(db);
  final puestoRepo = PuestoRepositoryImpl(db);
  final comercialRepo = ServicioComercialRepositoryImpl(db);
  final validator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, ConfiguracionCobroRepositoryImpl(db));
  final crear = CrearLineaComercialUseCase(comercialRepo, servicioRepo, validator);

  final resultado = await crear.ejecutar(
    servicioId: servicioId,
    borrador: LineaComercialBorrador(
      puestoId: puestoId,
      modalidadTurnoId: SeedIds.modalidadTurno24x24,
      cantidadElementos: 2,
      precioUnitario: 1500000,
      tratamientoIva: TratamientoIva.masIva,
      fechaInicioVigencia: DateTime(2026, 1, 1),
    ),
  );
  return (resultado as CrearLineaComercialExitoso).linea.id;
}

Future<String> _crearConfiguracionCobro(AppDatabase db, String servicioId) async {
  final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
  final catalogoRepo = CatalogoRepositoryImpl(db);
  final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
  final comercialRepo = ServicioComercialRepositoryImpl(db);
  final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
  final validator = ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo);
  final crear = CrearConfiguracionCobroUseCase(
    configuracionCobroRepo,
    servicioRepo,
    validator,
    const ConfiguracionCobroReglaEventoValidator(),
  );

  final resultado = await crear.ejecutar(
    servicioId: servicioId,
    borrador: ConfiguracionCobroBorrador(
      tipoDocumento: TipoDocumentoCobro.reciboDePago,
      frecuenciaId: SeedIds.frecuenciaCobroMensual,
      diaInicioPeriodo: 1,
      agrupacion: AgrupacionCobro.porServicio,
      metodo: MetodoPagoCobro.noAplica,
      requiereComplemento: false,
      fechaInicioVigencia: DateTime(2026, 1, 1),
    ),
  );
  return (resultado as CrearConfiguracionCobroExitoso).configuracion.id;
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
    await ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)).asignarEntidadFiscal(servicioId: servicioId, entidadFiscalId: entidad.id);
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

  testWidgets('Configuración comercial sin líneas muestra el mensaje vacío', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.servicioComercialSinLineas), findsOneWidget);
    expect(find.text(l10n.servicioComercialSubtotalTitulo), findsOneWidget);
  });

  testWidgets('agregar una línea comercial vía el diálogo muestra el subtotal', (tester) async {
    await _crearPuesto(db);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_linea_comercial')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_boton_agregar_linea_comercial')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardia').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24×24').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await tester.enterText(find.byType(TextFormField).at(1), '15000');

    await tester.tap(find.byType(DropdownButtonFormField<TratamientoIva>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioComercialTratamientoIvaMasIva).last);
    await tester.pumpAndSettle();

    final campoFechaInicio = find.byType(TextFormField).at(2);
    await tester.tap(campoFechaInicio);
    await tester.pumpAndSettle();
    var dialogoSelector = find.byType(Dialog).last;
    await tester.tap(find.descendant(of: dialogoSelector, matching: find.byType(TextButton)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialGuardadoExito), findsOneWidget);
    expect(find.text(l10n.servicioComercialSinLineas), findsNothing);
    expect(find.text(r'$30,000.00'), findsWidgets);
  });

  testWidgets('nueva vigencia reemplaza la condición vigente y actualiza el subtotal', (tester) async {
    final puesto = await _crearPuesto(db);
    await _crearLineaComercial(db, servicioId, puesto.id);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byTooltip(l10n.servicioComercialBotonNuevaVigencia));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.servicioComercialBotonNuevaVigencia));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '5');

    final campoFechaInicio = find.byType(TextFormField).at(2);
    await tester.tap(campoFechaInicio);
    await tester.pumpAndSettle();
    final dialogoSelector = find.byType(Dialog).last;
    await tester.tap(find.descendant(of: dialogoSelector, matching: find.byType(TextButton)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialNuevaVigenciaExito), findsOneWidget);
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('cerrar línea muestra la advertencia del efecto administrativo antes de confirmar', (tester) async {
    final puesto = await _crearPuesto(db);
    await _crearLineaComercial(db, servicioId, puesto.id);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byTooltip(l10n.servicioComercialBotonCerrarLinea));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.servicioComercialBotonCerrarLinea));
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialCerrarLineaAdvertencia), findsOneWidget);

    await tester.tap(find.text(l10n.servicioComercialCerrarLineaBotonConfirmar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialCerrarLineaExito), findsOneWidget);
  });

  testWidgets('ver historial muestra la vigencia vigente y permite editar anotaciones', (tester) async {
    final puesto = await _crearPuesto(db);
    await _crearLineaComercial(db, servicioId, puesto.id);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byTooltip(l10n.servicioComercialBotonHistorial));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.servicioComercialBotonHistorial));
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialEstadoVigente), findsWidgets);
    expect(find.textContaining('Guardia'), findsWidgets);

    await tester.tap(find.text(l10n.servicioComercialHistorialBotonEditarAnotaciones).last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Turno principal confirmado');
    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialAnotacionesGuardadoExito), findsOneWidget);
  });

  testWidgets('Configuración de cobro sin registro muestra el mensaje vacío', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.servicioCobroSinConfiguracion), findsOneWidget);
  });

  testWidgets('agregar una Configuración de cobro vía el diálogo (recibo, IVA no aplica)', (tester) async {
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<TipoDocumentoCobro>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioCobroTipoDocumentoReciboDePago).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mensual').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '1');

    await tester.tap(find.byType(DropdownButtonFormField<AgrupacionCobro>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioCobroAgrupacionPorServicio).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<MetodoPagoCobro>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioCobroMetodoNoAplica).last);
    await tester.pumpAndSettle();

    final campoFechaInicio = find.byType(TextFormField).at(1);
    await tester.tap(campoFechaInicio);
    await tester.pumpAndSettle();
    final dialogoSelector = find.byType(Dialog).last;
    await tester.tap(find.descendant(of: dialogoSelector, matching: find.byType(TextButton)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioCobroGuardadoExito), findsOneWidget);
    expect(find.text(l10n.servicioCobroSinConfiguracion), findsNothing);
    expect(find.text(l10n.servicioCobroTipoDocumentoReciboDePago), findsWidgets);
  });

  testWidgets('Configuración de cobro sin reglas temporales muestra el badge Incompleta', (tester) async {
    await _crearConfiguracionCobro(db, servicioId);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.servicioCobroBadgeIncompleta), findsOneWidget);
    expect(find.text(l10n.servicioCobroReglaPendiente), findsWidgets);
  });

  testWidgets('Historial de Configuración de cobro muestra la vigencia vigente y permite editar observaciones', (tester) async {
    await _crearConfiguracionCobro(db, servicioId);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.text(l10n.servicioCobroBotonHistorial));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioCobroBotonHistorial));
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioComercialEstadoVigente), findsWidgets);

    await tester.tap(find.text(l10n.servicioCobroHistorialBotonEditarObservaciones).last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Cliente confirmó condiciones por correo');
    await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioCobroObservacionesGuardadoExito), findsOneWidget);
  });

  testWidgets('Cerrar Configuración de cobro muestra la advertencia y confirma el cierre', (tester) async {
    await _crearConfiguracionCobro(db, servicioId);
    await _pumpScreen(tester, db, servicioId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.text(l10n.servicioCobroBotonCerrarConfiguracion));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioCobroBotonCerrarConfiguracion));
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioCobroCerrarAdvertencia), findsOneWidget);

    await tester.tap(find.text(l10n.servicioCobroCerrarBotonConfirmar).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.servicioCobroCerrarExito), findsOneWidget);
  });
}
