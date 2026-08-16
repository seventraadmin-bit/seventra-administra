// Reproducción y cobertura del crash real reportado por Marlon (Etapa
// 15, Parte B): al dar de alta una Configuración de cobro nueva
// (SPORTIUM COYOACÁN, Servicio sin ninguna Configuración de cobro
// previa) y capturar la regla de la etapa Emisión, la sección "Flujo
// posterior a la emisión" lanzaba "Null check operator used on a null
// value" — causa raíz: `describirEtapaCobro` (usada también para
// describir en vivo una etapa TODAVÍA en captura, vía
// `EtapaEditState.aVistaPrevia`) asumía que si `tipoRegla` ya estaba
// elegido, sus campos complementarios (mesRelativo/diaDelMes/
// diaSemana/ordinalSemana) también — cierto para una etapa ya
// persistida (la validación lo garantiza antes de guardar), falso para
// una fila que el usuario apenas empezó a llenar. Corregido guardando
// cada `case` contra sus propios campos obligatorios antes de leerlos.
//
// Esta prueba cubre, contra la UI real (`ServicioExpedienteScreen`),
// exactamente los 8 escenarios pedidos por Marlon, en ancho amplio y
// reducido.

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
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
import 'package:riseg_one/core/design_system/components/riseg_date_field.dart';
import 'package:riseg_one/core/design_system/components/riseg_select.dart';
import 'package:riseg_one/core/design_system/components/riseg_text_field.dart';

import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_cobro_section.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../../generated_migrations/schema.dart';

const _anchoAmplio = 1400.0;
const _anchoReducido = 580.0;
const _alto = 2200.0;

/// `AppDatabase.schemaVersion` actual — mismo criterio y misma
/// advertencia que `_currentSchemaVersion` en `migration_test.dart`.
/// El escenario "8" de abajo congela el esquema físico en un nominal
/// viejo vía `SchemaVerifier.migrateAndValidate(db, N)` para probar que
/// datos migrados desde v48 abren sin crash en la pantalla real — pero
/// a diferencia de una prueba de migración pura, aquí se interactúa con
/// `ServicioExpedienteScreen` de verdad, y esa pantalla sí puede
/// consultar tablas agregadas por migraciones *posteriores* a la que
/// se está probando (ej. `cliente_portal`, Etapa 15/`schemaVersion` 52,
/// consultada sin condición al abrir "Corregir Configuración de
/// cobro"). Apuntar a un nominal fijo below del actual revienta en
/// cuanto eso pasa — mordió exactamente así al agregar ClientePortal.
/// Apuntar siempre aquí, nunca a un literal viejo.
const _currentSchemaVersion = 52;

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

Future<void> _fijarAncho(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, _alto);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget pantalla) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pantalla,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Elige `opcionTexto` en el `RisegSelect<T>` cuya etiqueta es
/// exactamente `etiqueta` — precisa aunque haya varios `RisegSelect<T>`
/// del mismo `T` en pantalla (ej. Frecuencia y Entidad fiscal, ambos
/// `String`), porque escopa por el widget con esa etiqueta, no por
/// tipo a secas.
Future<void> _elegirSelect<T>(WidgetTester tester, String etiqueta, String opcionTexto) async {
  final campo = find.widgetWithText(RisegSelect<T>, etiqueta);
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: campo, matching: find.byType(DropdownButtonFormField<T>)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcionTexto).last);
  await tester.pumpAndSettle();
}

/// Igual que [_elegirSelect] pero escopado dentro de un contenedor
/// (una fila de etapa concreta) — necesario en cuanto hay más de una
/// etapa expandida a la vez, cada una con su propio `RisegSelect<TipoReglaEvento>`.
Future<void> _elegirSelectDentroDe<T>(WidgetTester tester, Finder contenedor, String etiqueta, String opcionTexto) async {
  final campo = find.descendant(of: contenedor, matching: find.widgetWithText(RisegSelect<T>, etiqueta));
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: campo, matching: find.byType(DropdownButtonFormField<T>)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcionTexto).last);
  await tester.pumpAndSettle();
}

Future<void> _tipearCampo(WidgetTester tester, String etiqueta, String valor) async {
  final campo = find.widgetWithText(RisegTextField, etiqueta);
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: campo, matching: find.byType(TextFormField)), valor);
  await tester.pumpAndSettle();
}

Future<void> _tipearCampoDentroDe(WidgetTester tester, Finder contenedor, String etiqueta, String valor) async {
  final campo = find.descendant(of: contenedor, matching: find.widgetWithText(RisegTextField, etiqueta));
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: campo, matching: find.byType(TextFormField)), valor);
  await tester.pumpAndSettle();
}

/// Abre el selector de fecha y confirma con la fecha ya resaltada por
/// defecto (hoy) — a estas pruebas no les importa la fecha exacta,
/// solo que el campo quede lleno con una fecha válida.
Future<void> _elegirFechaHoy(WidgetTester tester, String etiqueta) async {
  final campo = find.widgetWithText(RisegDateField, etiqueta);
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: campo, matching: find.byType(TextFormField)));
  await tester.pumpAndSettle();
  final dialogoCalendario = find.byType(Dialog).last;
  await tester.tap(find.descendant(of: dialogoCalendario, matching: find.byType(TextButton)).last);
  await tester.pumpAndSettle();
}

/// Llena todo lo que no es "Flujo posterior a la emisión": Tipo de
/// documento, Frecuencia, Día de inicio, Agrupación y Vigente desde —
/// Recibo de pago fija Método automáticamente (Etapa 15, hallazgo
/// Tikal), así que nunca hace falta tocarlo aquí.
Future<void> _llenarCondicionesBasicas(WidgetTester tester, AppLocalizations l10n) async {
  await _elegirSelect<TipoDocumentoCobro>(tester, l10n.servicioCobroCampoTipoDocumento, l10n.servicioCobroTipoDocumentoReciboDePago);
  await _elegirSelect<String>(tester, l10n.servicioCobroCampoFrecuencia, 'Mensual');
  await _tipearCampo(tester, l10n.servicioCobroCampoDiaInicioPeriodo, '1');
  await _elegirSelect<AgrupacionCobro>(tester, l10n.servicioCobroCampoAgrupacion, l10n.servicioCobroAgrupacionPorServicio);
  await _elegirFechaHoy(tester, l10n.servicioCobroCampoFechaInicioVigencia);
}

/// Completa la regla "Día fijo del mes" de la fila de Emisión (única
/// etapa presente al abrir un alta nueva) — mismo campo que reprodujo
/// el crash: elegir el tipo de regla sin haber llenado "Mes relativo"
/// todavía.
Future<void> _completarEmisionDiaFijoDelMes(WidgetTester tester, AppLocalizations l10n) async {
  final filaEmision = find.byType(EtapaCobroFormRow).first;
  await _elegirSelectDentroDe<TipoReglaEvento>(tester, filaEmision, l10n.servicioCobroCampoTipoRegla, l10n.servicioCobroReglaDiaFijoDelMes);
  // Punto crítico del hallazgo real: justo aquí, con `tipoRegla` ya
  // elegido y `mesRelativo` todavía nulo, el bug original crasheaba.
  expect(tester.takeException(), isNull, reason: 'elegir el tipo de regla sin llenar el resto no debe crashear');
  await _elegirSelectDentroDe<MesRelativoCobro>(tester, filaEmision, l10n.servicioCobroCampoMesRelativo, l10n.servicioCobroMesRelativoActual);
  await _tipearCampoDentroDe(tester, filaEmision, l10n.servicioCobroCampoDiaDelMes, '1');
}

Future<({String servicioId, String clienteId})> _crearServicioSportiumCoyoacan(AppDatabase db) async {
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  final clienteRepo = ClienteRepositoryImpl(db);
  final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
  final catalogoRepo = CatalogoRepositoryImpl(db);

  final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
  final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
  final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

  final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
  final creado = await crearServicio.ejecutar(
    clienteId: clienteId,
    borrador: ServicioBorrador(
      nombre: 'Vigilancia Sportium Coyoacán',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      fechaInicio: DateTime(2026, 1, 1),
    ),
  );
  return (servicioId: (creado as GuardarServicioExitoso).servicio.id, clienteId: clienteId);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  for (final ancho in [_anchoAmplio, _anchoReducido]) {
    final etiquetaAncho = ancho == _anchoAmplio ? 'ancho amplio' : 'ancho reducido';

    testWidgets('1. Servicio sin configuración → abrir alta → sin crash ($etiquetaAncho)', (tester) async {
      await _fijarAncho(tester, ancho);
      final servicio = await _crearServicioSportiumCoyoacan(db);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

      final botonAgregar = find.byKey(const Key('servicio_boton_agregar_configuracion_cobro'));
      await tester.ensureVisible(botonAgregar);
      await tester.pumpAndSettle();
      await tester.tap(botonAgregar);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(EtapaCobroFormRow), findsOneWidget, reason: 'Emisión debe existir automáticamente, sola');
    });

    testWidgets('2. Solo Emisión → guardar ($etiquetaAncho)', (tester) async {
      await _fijarAncho(tester, ancho);
      final servicio = await _crearServicioSportiumCoyoacan(db);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();

      await _llenarCondicionesBasicas(tester, l10n);
      await _completarEmisionDiaFijoDelMes(tester, l10n);
      expect(tester.takeException(), isNull);

      final dialogo = find.byType(Dialog).last;
      await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.servicioVinculacionDialogoBotonGuardar)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing, reason: 'el diálogo debe cerrar tras un guardado exitoso');
      expect(find.text(l10n.servicioCobroGuardadoExito), findsOneWidget);
    });

    testWidgets('3. Emisión + Pago esperado (etapa de sistema) ($etiquetaAncho)', (tester) async {
      await _fijarAncho(tester, ancho);
      final servicio = await _crearServicioSportiumCoyoacan(db);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();

      await _llenarCondicionesBasicas(tester, l10n);
      await _completarEmisionDiaFijoDelMes(tester, l10n);
      expect(tester.takeException(), isNull);

      // "Pago esperado" es una etapa de sistema — se ofrece como botón
      // propio (Etapa 15, corrección del mismo hallazgo: antes no había
      // ninguna forma de agregarla en una Configuración nueva).
      final botonAgregarPago = find.byKey(Key('servicio_cobro_boton_agregar_etapa_sistema_${TipoEventoCobro.pagoEsperado.name}'));
      await tester.ensureVisible(botonAgregarPago);
      await tester.pumpAndSettle();
      await tester.tap(botonAgregarPago);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EtapaCobroFormRow), findsNWidgets(2));

      final filaPago = find.byType(EtapaCobroFormRow).last;
      await _elegirSelectDentroDe<TipoReglaEvento>(
        tester,
        filaPago,
        l10n.servicioCobroCampoTipoRegla,
        l10n.servicioCobroReglaDiasCalendarioDespuesDe,
      );
      expect(tester.takeException(), isNull, reason: 'mismo punto crítico: regla elegida, offset todavía sin capturar');
      await _tipearCampoDentroDe(tester, filaPago, l10n.servicioCobroCampoOffsetDiasCalendario, '10');
      await _elegirSelectDentroDe<String>(
        tester,
        filaPago,
        l10n.servicioCobroCampoEventoReferencia,
        l10n.servicioCobroOrigenCierrePeriodo,
      );
      expect(tester.takeException(), isNull);

      final dialogo = find.byType(Dialog).last;
      await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.servicioVinculacionDialogoBotonGuardar)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.servicioCobroGuardadoExito), findsOneWidget);
    });

    testWidgets('4. Emisión + etapa personalizada ($etiquetaAncho)', (tester) async {
      await _fijarAncho(tester, ancho);
      final servicio = await _crearServicioSportiumCoyoacan(db);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();

      await _llenarCondicionesBasicas(tester, l10n);
      await _completarEmisionDiaFijoDelMes(tester, l10n);

      final botonAgregarEtapa = find.byKey(const Key('servicio_cobro_boton_agregar_etapa'));
      await tester.ensureVisible(botonAgregarEtapa);
      await tester.pumpAndSettle();
      await tester.tap(botonAgregarEtapa);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EtapaCobroFormRow), findsNWidgets(2));

      final filaPersonalizada = find.byType(EtapaCobroFormRow).last;
      await _tipearCampoDentroDe(tester, filaPersonalizada, l10n.servicioCobroCampoNombreEtapa, 'Validación por correo');
      await _elegirSelectDentroDe<TipoReglaEvento>(
        tester,
        filaPersonalizada,
        l10n.servicioCobroCampoTipoRegla,
        l10n.servicioCobroReglaDiasCalendarioDespuesDe,
      );
      expect(tester.takeException(), isNull);
      await _tipearCampoDentroDe(tester, filaPersonalizada, l10n.servicioCobroCampoOffsetDiasCalendario, '0');
      await _elegirSelectDentroDe<String>(
        tester,
        filaPersonalizada,
        l10n.servicioCobroCampoEventoReferencia,
        l10n.servicioCobroOrigenCierrePeriodo,
      );
      expect(tester.takeException(), isNull);

      final dialogo = find.byType(Dialog).last;
      await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.servicioVinculacionDialogoBotonGuardar)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.servicioCobroGuardadoExito), findsOneWidget);
    });

    testWidgets('5. Abrir y cerrar sin guardar ($etiquetaAncho)', (tester) async {
      await _fijarAncho(tester, ancho);
      final servicio = await _crearServicioSportiumCoyoacan(db);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
      await tester.pumpAndSettle();

      await _completarEmisionDiaFijoDelMes(tester, l10n);
      expect(tester.takeException(), isNull);

      final dialogo = find.byType(Dialog).last;
      await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.servicioVinculacionDialogoBotonCancelar)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(l10n.servicioCobroSinConfiguracion), findsOneWidget, reason: 'cancelar no debe crear nada');
    });
  }

  testWidgets('6. Corregir configuración existente — no crash al reabrir ni al re-capturar una regla', (tester) async {
    await _fijarAncho(tester, _anchoAmplio);
    final servicio = await _crearServicioSportiumCoyoacan(db);
    await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Alta inicial completa, para tener algo que corregir.
    await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    await _llenarCondicionesBasicas(tester, l10n);
    await _completarEmisionDiaFijoDelMes(tester, l10n);
    await tester.tap(find.descendant(of: find.byType(Dialog).last, matching: find.text(l10n.servicioVinculacionDialogoBotonGuardar)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('servicio_cobro_boton_corregir')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_cobro_boton_corregir')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EtapaCobroFormRow), findsOneWidget, reason: 'prellenada con Emisión ya capturada');

    // Cambiar la regla de Emisión a una que exige otros campos —
    // mismo punto crítico, ahora sobre una etapa ya persistida.
    final filaEmision = find.byType(EtapaCobroFormRow).first;
    await tester.tap(find.descendant(of: filaEmision, matching: find.byIcon(Icons.expand_more)));
    await tester.pumpAndSettle();
    await _elegirSelectDentroDe<TipoReglaEvento>(
      tester,
      filaEmision,
      l10n.servicioCobroCampoTipoRegla,
      l10n.servicioCobroReglaNEsimoDiaSemanaDelMes,
    );
    expect(tester.takeException(), isNull, reason: 'diaSemana/ordinalSemana todavía sin capturar en este punto');

    await tester.tap(find.descendant(of: find.byType(Dialog).last, matching: find.text(l10n.servicioVinculacionDialogoBotonCancelar)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('7. Nueva vigencia desde una configuración existente — no crash', (tester) async {
    await _fijarAncho(tester, _anchoAmplio);
    final servicio = await _crearServicioSportiumCoyoacan(db);
    await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicio.servicioId));

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_boton_agregar_configuracion_cobro')));
    await tester.pumpAndSettle();
    await _llenarCondicionesBasicas(tester, l10n);
    await _completarEmisionDiaFijoDelMes(tester, l10n);
    await tester.tap(find.descendant(of: find.byType(Dialog).last, matching: find.text(l10n.servicioVinculacionDialogoBotonGuardar)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(l10n.servicioCobroBotonNuevaVigencia));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.servicioCobroBotonNuevaVigencia));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EtapaCobroFormRow), findsOneWidget, reason: 'prellenada con la vigencia actual, igual que Corregir');

    final botonAgregarPago = find.byKey(Key('servicio_cobro_boton_agregar_etapa_sistema_${TipoEventoCobro.pagoEsperado.name}'));
    await tester.ensureVisible(botonAgregarPago);
    await tester.pumpAndSettle();
    await tester.tap(botonAgregarPago);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final filaPago = find.byType(EtapaCobroFormRow).last;
    await _elegirSelectDentroDe<TipoReglaEvento>(
      tester,
      filaPago,
      l10n.servicioCobroCampoTipoRegla,
      l10n.servicioCobroReglaDiasHabilesDespuesDe,
    );
    expect(tester.takeException(), isNull, reason: 'offset todavía sin capturar en este punto — mismo hallazgo');

    await tester.tap(find.descendant(of: find.byType(Dialog).last, matching: find.text(l10n.servicioVinculacionDialogoBotonCancelar)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('8. Configuración migrada de v48 al esquema actual — el expediente real la abre sin crash', (tester) async {
    // `setUp` ya abrió una `AppDatabase` en memoria — esta prueba
    // necesita una completamente distinta (construida sobre el
    // snapshot histórico v48), así que cierra la de `setUp` antes de
    // reemplazar `db` para no dejarla abierta sin `tearDown`.
    await db.close();

    final verifier = SchemaVerifier(GeneratedHelper());
    final schemaV48 = await verifier.schemaAt(48);
    final raw = schemaV48.rawDatabase;

    raw.execute('''
      INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
      VALUES ('cliente-migrado', 'CLI-000077', 'Sportium', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
      VALUES ('tipo-servicio-migrado', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO tipo_frecuencia_cobro (id, codigo, nombre, created_at, updated_at)
      VALUES ('${SeedIds.frecuenciaCobroMensual}', 'MENSUAL', 'Mensual', 1700000000, 1700000000);
    ''');
    raw.execute('''
      INSERT INTO servicio (id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio, created_at, updated_at, ciclo_vida_registro)
      VALUES ('servicio-migrado', 'SER-000077', 'cliente-migrado', 'Vigilancia Sportium Coyoacán', 'tipo-servicio-migrado', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO configuracion_cobro (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
      VALUES ('configuracion-migrada', 'servicio-migrado', 1700000000, 1700000000, 'activo');
    ''');
    raw.execute('''
      INSERT INTO configuracion_cobro_vigencia (
        id, configuracion_cobro_id, tipo_documento, frecuencia_id, dia_inicio_periodo,
        agrupacion, metodo, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
      ) VALUES (
        'vigencia-migrada', 'configuracion-migrada', 'reciboDePago', '${SeedIds.frecuenciaCobroMensual}', 1,
        'porServicio', 'noAplica', 1700000000, 1700000000, 1700000000, 'activo'
      );
    ''');
    raw.execute('''
      INSERT INTO configuracion_cobro_regla_evento (configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, mes_relativo, dia_del_mes)
      VALUES ('vigencia-migrada', 'emision', 'diaFijoDelMes', 'actual', 21);
    ''');
    raw.execute('''
      INSERT INTO configuracion_cobro_regla_evento (configuracion_cobro_vigencia_id, tipo_evento, tipo_regla, offset_dias_habiles, evento_referencia)
      VALUES ('vigencia-migrada', 'pagoEsperado', 'diasHabilesDespuesDe', 10, 'emision');
    ''');

    db = AppDatabase(schemaV48.newConnection());
    await verifier.migrateAndValidate(db, _currentSchemaVersion);

    await _fijarAncho(tester, _anchoAmplio);
    await _pump(tester, db, const ServicioExpedienteScreen(servicioId: 'servicio-migrado'));
    expect(tester.takeException(), isNull, reason: 'el expediente debe abrir sin crash con datos reales migrados de v48');

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await tester.ensureVisible(find.byKey(const Key('servicio_cobro_boton_corregir')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('servicio_cobro_boton_corregir')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EtapaCobroFormRow), findsNWidgets(2), reason: 'las 2 reglas migradas, ya resueltas por id real');

    await tester.tap(find.descendant(of: find.byType(Dialog).last, matching: find.text(l10n.servicioVinculacionDialogoBotonCancelar)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
