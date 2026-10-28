// Etapa 19 — "Deudas y crédito empresarial". Pruebas de widget: el
// diálogo real "Registrar deuda" actualiza el listado sin recargar
// manualmente (mismo patrón que la Etapa 15 encontró real para
// Inventario), el expediente de una tarjeta de crédito muestra la
// vista compacta con utilización derivada, "Registrar pago" real
// actualiza saldo/estatus in situ, y ambas pantallas no desbordan en
// los 4 anchos estándar × claro/oscuro.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deuda_expediente_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

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

Finder botonConEtiqueta(String etiqueta) => find.widgetWithText(RisegButton, etiqueta);

Future<void> pump(
  WidgetTester tester,
  AppDatabase db, {
  required Size tamano,
  required ThemeData tema,
  String rutaInicial = '/finanzas/deudas-y-credito',
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: rutaInicial,
    routes: [
      GoRoute(path: '/finanzas/deudas-y-credito', builder: (context, state) => const Scaffold(body: DeudasCreditoListScreen())),
      GoRoute(
        path: '/finanzas/deudas-y-credito/:id',
        builder: (context, state) => DeudaExpedienteScreen(deudaId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/finanzas/egresos', builder: (context, state) => const Scaffold(body: EgresosListScreen())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: MaterialApp.router(
        theme: tema,
        themeMode: ThemeMode.light,
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // La sesión de prueba (Maestro) reporta `usuarioId: 'usuario-maestro'`
    // como `actorUsuarioId` en cada escritura real — sin esta fila,
    // `MovimientoDeuda.actorUsuarioId` (FK a Usuario) rechaza la
    // inserción en cuanto el flujo pasa por el provider autorizado real.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'usuario-maestro',
            passwordHash: 'x',
          ),
        );
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  testWidgets(
    'diálogo real "Registrar deuda" agrega la fila al listado y actualiza el KPI de inmediato, sin recargar manualmente',
    (tester) async {
      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light());
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.deudasCreditoListadoVacioTitulo), findsOneWidget);

      await tester.tap(find.byKey(const Key('deudas_credito_boton_registrar')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoNombre), matching: find.byType(TextFormField)),
        'TDC BBVA',
      );
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoImporteOriginal),
          matching: find.byType(TextFormField),
        ),
        '36000',
      );

      await tester.tap(botonConEtiqueta(l10n.deudasCreditoBotonRegistrar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.registrarDeudaExito), findsOneWidget);
      expect(find.text('TDC BBVA'), findsOneWidget);
      expect(find.textContaining(r'$36,000.00'), findsWidgets, reason: 'Deuda total actual y Saldo actual deben reflejar el alta real');
    },
  );

  testWidgets(
    'expediente de una tarjeta de crédito muestra la vista compacta con utilización, y "Registrar pago" real reduce el saldo in situ',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final registrar = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
      final creada = (await registrar.ejecutar(
        nombre: 'TDC BBVA',
        tipo: 'tarjetaCredito',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 3600000,
        saldoInicial: 3600000,
        tarjetaUltimosDigitos: '4215',
        tarjetaLimiteCredito: 5000000,
        tarjetaDiaCorte: 12,
        tarjetaDiaPago: 2,
      ) as RegistrarDeudaExitoso)
          .deuda;

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/${creada.id}');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.textContaining('•••• 4215'), findsOneWidget);
      expect(find.text(l10n.deudaTarjetaPorcentajeUtilizacion), findsOneWidget, reason: 'la fila superior de KPIs de la TDC debe incluir % de utilización');
      expect(find.text('72%'), findsOneWidget, reason: '36,000 de 50,000 de límite = 72%');

      await tester.tap(botonConEtiqueta(l10n.deudasCreditoBotonRegistrarPago));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarPagoDeudaCampoImporte),
          matching: find.byType(TextFormField),
        ),
        '15000',
      );
      await tester.tap(botonConEtiqueta(l10n.registrarPagoDeudaBotonConfirmar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.registrarPagoDeudaExito), findsOneWidget);
      expect(find.textContaining(r'$21,000.00'), findsWidgets, reason: 'el saldo actual debe reflejar el pago real sin recargar manualmente');
      expect(find.textContaining(r'$15,000.00'), findsWidgets, reason: 'Pagado debe reflejar el pago real, derivado de MovimientoDeuda');
      expect(find.textContaining(l10n.movimientoDeudaPago), findsWidgets, reason: 'el pago debe aparecer en el historial de movimientos');
    },
  );

  testWidgets(
    'CORRECCIÓN: navegar Listado → expediente → pagar → volver (pop real) refleja el saldo/pagado nuevos SIN recarga manual',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      await registrar.ejecutar(
        nombre: 'TDC BBVA',
        tipo: 'tarjetaCredito',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 5000000,
        saldoInicial: 5000000,
      );

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light());
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.textContaining(r'$50,000.00'), findsWidgets, reason: 'saldo/KPI iniciales antes del pago');

      // Entrar al expediente vía la misma navegación real que usa la
      // fila de la tabla (`context.push`, nunca `go` — la pantalla de
      // origen no se destruye, así que su provider sigue en caché).
      await tester.tap(find.text('TDC BBVA'));
      await tester.pumpAndSettle();

      await tester.tap(botonConEtiqueta(l10n.deudasCreditoBotonRegistrarPago));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarPagoDeudaCampoImporte),
          matching: find.byType(TextFormField),
        ),
        '10000',
      );
      await tester.tap(botonConEtiqueta(l10n.registrarPagoDeudaBotonConfirmar).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.registrarPagoDeudaExito), findsOneWidget);

      // Volver al listado con el botón de regreso real del AppBar —
      // nunca reconstruir la pantalla a mano.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(r'$40,000.00'),
        findsWidgets,
        reason: 'BUG REAL corregido: el listado debe reflejar el saldo nuevo al volver, sin recargar manualmente',
      );
      expect(find.textContaining(r'$10,000.00'), findsWidgets, reason: 'columna Pagado debe reflejar el pago real');
    },
  );

  testWidgets(
    'CORRECCIÓN: tras registrar un pago, Finanzas > Egresos muestra el Egreso con origen "Deuda" (nunca "Manual")',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final creada = (await registrar.ejecutar(
        nombre: 'TDC BBVA',
        tipo: 'tarjetaCredito',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 5000000,
        saldoInicial: 5000000,
      ) as RegistrarDeudaExitoso)
          .deuda;

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/${creada.id}');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(botonConEtiqueta(l10n.deudasCreditoBotonRegistrarPago));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarPagoDeudaCampoImporte),
          matching: find.byType(TextFormField),
        ),
        '10000',
      );
      await tester.tap(botonConEtiqueta(l10n.registrarPagoDeudaBotonConfirmar).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.registrarPagoDeudaExito), findsOneWidget);

      // Navegar directo a Egresos (misma pestaña de Finanzas) — nunca
      // reiniciar la app ni recargar manualmente.
      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/finanzas/egresos');
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RisegStatusBadge && w.label == l10n.egresosOrigenDeuda),
        findsOneWidget,
        reason: 'BUG REAL corregido: el pago de deuda debe aparecer con origen "Deuda"',
      );
      expect(
        find.byWidgetPredicate((w) => w is RisegStatusBadge && w.label == l10n.egresosOrigenManual),
        findsNothing,
        reason: 'nunca debe clasificarse como "Manual"',
      );
      expect(find.textContaining(creada.folio), findsWidgets, reason: 'el concepto del Egreso debe identificar la Deuda');
    },
  );

  testWidgets(
    'editar deuda: cambiar acreedor/fecha de vencimiento/observaciones se refleja de inmediato en expediente y listado',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final creada = (await registrar.ejecutar(
        nombre: 'Préstamo Jessica',
        tipo: 'prestamo',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 9000000,
        saldoInicial: 9000000,
      ) as RegistrarDeudaExitoso)
          .deuda;

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/${creada.id}');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(botonConEtiqueta(l10n.editarDeudaBotonConfirmar));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoAcreedor), matching: find.byType(TextFormField)),
        'Jessica Ramírez',
      );
      await tester.tap(botonConEtiqueta(l10n.editarDeudaBotonConfirmar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.editarDeudaExito), findsOneWidget);
      expect(find.textContaining('Jessica Ramírez'), findsOneWidget, reason: 'el expediente debe reflejar la edición de inmediato');

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/finanzas/deudas-y-credito');
      await tester.pumpAndSettle();

      expect(find.textContaining('Jessica Ramírez'), findsOneWidget, reason: 'BUG REAL corregido: el listado también debe reflejar la edición');
    },
  );

  testWidgets(
    'editar TDC: desmarcar "ciclo vigente ya cubierto" limpia tarjetaVencimientoCubiertoHasta',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final creada = (await registrar.ejecutar(
        nombre: 'TDC Konfío',
        tipo: 'tarjetaCredito',
        saldoInicial: 0,
        tarjetaLimiteCredito: 5000000,
        tarjetaReglaFechaPago: 'diaFijo',
        tarjetaDiaPago: 15,
        tarjetaVencimientoCubiertoHasta: DateTime(2026, 1, 15),
      ) as RegistrarDeudaExitoso)
          .deuda;
      expect(creada.tarjetaVencimientoCubiertoHasta, isNotNull);

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/${creada.id}');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(botonConEtiqueta(l10n.editarDeudaBotonConfirmar));
      await tester.pumpAndSettle();

      final checkboxCicloCubierto = find.widgetWithText(CheckboxListTile, l10n.registrarDeudaCampoCicloCubierto);
      await tester.ensureVisible(checkboxCicloCubierto);
      expect(tester.widget<CheckboxListTile>(checkboxCicloCubierto).value, isTrue, reason: 'debe reflejar el estado ya guardado');
      await tester.tap(checkboxCicloCubierto);
      await tester.pumpAndSettle();

      await tester.tap(botonConEtiqueta(l10n.editarDeudaBotonConfirmar).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.editarDeudaExito), findsOneWidget);

      final tarjetaTrasEditar = await (db.select(db.deuda)..where((t) => t.id.equals(creada.id))).getSingle();
      expect(tarjetaTrasEditar.tarjetaVencimientoCubiertoHasta, isNull, reason: 'desmarcar debe limpiar el campo, nunca dejarlo con el valor viejo');
    },
  );

  testWidgets(
    'registrar un pago mayor al saldo actual: el diálogo muestra el error, NO crea Egreso ni MovimientoDeuda, y el saldo no cambia',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final creada = (await registrar.ejecutar(
        nombre: 'TDC BBVA',
        tipo: 'tarjetaCredito',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 1000000,
        saldoInicial: 1000000,
      ) as RegistrarDeudaExitoso)
          .deuda;

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/${creada.id}');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(botonConEtiqueta(l10n.deudasCreditoBotonRegistrarPago));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarPagoDeudaCampoImporte),
          matching: find.byType(TextFormField),
        ),
        '10001',
      );
      await tester.tap(botonConEtiqueta(l10n.registrarPagoDeudaBotonConfirmar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.registrarPagoDeudaErrorSobrepasaSaldo(formatoCentavosDeuda(1000000))), findsOneWidget);
      expect(find.text(l10n.registrarPagoDeudaExito), findsNothing, reason: 'no debe mostrarse un éxito falso');

      final movimientos = await deudaRepo.listarMovimientos(creada.id);
      expect(movimientos, hasLength(1), reason: 'solo altaInicial — ningún pago fantasma');
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'ningún Egreso debe crearse cuando el pago se rechaza');
      final deudaSinCambios = await deudaRepo.obtenerPorId(creada.id);
      expect(deudaSinCambios!.saldoActual, 1000000);
    },
  );

  testWidgets(
    'CORRECCIÓN: columna "Próximo pago" — una TDC con regla real (días después del corte) muestra la fecha '
    'calculada, nunca "Sin vencimiento"; una TDC sin configurar muestra "Sin configurar"; un préstamo sigue '
    'usando su fechaVencimiento tal cual',
    (tester) async {
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      await registrar.ejecutar(
        nombre: 'Konfío Empresarial',
        tipo: 'tarjetaCredito',
        saldoInicial: 3326608,
        fechaSaldoInicial: DateTime(2026, 9, 5),
        tarjetaLimiteCredito: 4000000,
        tarjetaDiaCorte: 17,
        tarjetaReglaFechaPago: 'diasDespuesDeCorte',
        tarjetaDiasDespuesCorte: 20,
      );
      await registrar.ejecutar(
        nombre: 'TDC sin configurar',
        tipo: 'tarjetaCredito',
        saldoInicial: 0,
        tarjetaLimiteCredito: 2000000,
      );
      await registrar.ejecutar(
        nombre: 'Préstamo Jessica',
        tipo: 'prestamo',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 9000000,
        saldoInicial: 8000000,
        fechaVencimiento: DateTime(2026, 6, 1),
      );

      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light());
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // Calculado con la MISMA regla/parámetros que la tarjeta real, en
      // vez de una fecha fija — la pantalla usa `DateTime.now()`, así
      // que el resultado esperado debe recalcularse relativo a "hoy" en
      // el momento en que la prueba realmente corre.
      final fechaEsperadaTdc = proximaFechaDiasDespuesDeCorte(diaCorte: 17, diasDespuesCorte: 20, hoy: DateTime.now());
      final formatoFecha = DateFormat('dd/MM/yyyy');

      expect(find.text(l10n.deudasCreditoColumnaVencimiento), findsOneWidget, reason: 'el encabezado ahora es "Próximo pago"');
      expect(
        find.text('01/06/2026'),
        findsOneWidget,
        reason: 'un préstamo sigue mostrando su fechaVencimiento real, sin cambios',
      );
      expect(
        find.text(formatoFecha.format(fechaEsperadaTdc)),
        findsOneWidget,
        reason: 'BUG REAL corregido: antes mostraba "Sin vencimiento" — ahora calcula la próxima fecha límite real (corte 17 + 20 días)',
      );
      expect(
        find.text(l10n.deudasCreditoSinConfigurar),
        findsOneWidget,
        reason: 'una TDC con configuración realmente incompleta muestra "Sin configurar", nunca "Sin vencimiento"',
      );
      expect(find.text(l10n.deudasCreditoSinVencimiento), findsNothing, reason: '"Sin vencimiento" ya no debe aparecer para ninguna TDC');
    },
  );

  testWidgets(
    'diálogo real "Registrar deuda": marcar "ciclo vigente ya cubierto" guarda tarjetaVencimientoCubiertoHasta '
    '(nunca genera Egreso/MovimientoDeuda por sí solo)',
    (tester) async {
      await pump(tester, db, tamano: const Size(1440, 2400), tema: AppTheme.light());
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.byKey(const Key('deudas_credito_boton_registrar')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoNombre), matching: find.byType(TextFormField)),
        'Konfío Empresarial',
      );

      final selectorTipo = find.byWidgetPredicate((w) => w is RisegSelect<TipoDeuda> && w.value == TipoDeuda.prestamo);
      await tester.tap(selectorTipo);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.deudaTipoTarjetaCredito).last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoDiaCorte), matching: find.byType(TextFormField)),
        '17',
      );
      final selectorRegla = find.byWidgetPredicate((w) => w is RisegSelect<ReglaFechaLimitePagoTarjeta>);
      await tester.tap(selectorRegla);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.registrarDeudaReglaDiasDespuesCorte).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoDiasDespuesCorte),
          matching: find.byType(TextFormField),
        ),
        '20',
      );

      final checkboxCicloCubierto = find.widgetWithText(CheckboxListTile, l10n.registrarDeudaCampoCicloCubierto);
      await tester.ensureVisible(checkboxCicloCubierto);
      await tester.tap(checkboxCicloCubierto);
      await tester.pumpAndSettle();

      await tester.tap(botonConEtiqueta(l10n.deudasCreditoBotonRegistrar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.registrarDeudaExito), findsOneWidget);

      final deudas = await (db.select(db.deuda)..where((t) => t.nombre.equals('Konfío Empresarial'))).get();
      final creada = deudas.single;
      expect(creada.tarjetaVencimientoCubiertoHasta, isNotNull,
          reason: 'marcar el checkbox debe calcular y guardar la fecha conciliada, nunca dejarla en null');

      final movimientos = await (db.select(db.movimientoDeuda)..where((t) => t.deudaId.equals(creada.id))).get();
      expect(movimientos, isEmpty, reason: 'saldoInicial 0 — y la reconciliación del ciclo en sí nunca genera MovimientoDeuda ni Egreso');
      final egresos = await db.select(db.egreso).get();
      expect(egresos, isEmpty);
    },
  );

  const anchos = [Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)];
  final temas = {'claro': AppTheme.light(), 'oscuro': AppTheme.dark()};

  for (final entradaTema in temas.entries) {
    for (final tamano in anchos) {
      final etiqueta = '${tamano.width.toInt()}×${tamano.height.toInt()}, ${entradaTema.key}';

      testWidgets('Deudas y crédito — listado ($etiqueta): cero overflow', (tester) async {
        final egresoRepo = EgresoRepositoryImpl(db);
        final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
        final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
        await registrar.ejecutar(
          nombre: 'TDC BBVA',
          tipo: 'tarjetaCredito',
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 3600000,
          saldoInicial: 3600000,
          tarjetaUltimosDigitos: '4215',
          tarjetaLimiteCredito: 5000000,
        );
        await registrar.ejecutar(
          nombre: 'Préstamo Jessica',
          tipo: 'prestamo',
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 9000000,
          saldoInicial: 8000000,
          fechaVencimiento: DateTime(2026, 6, 1),
        );

        await pump(tester, db, tamano: tamano, tema: entradaTema.value);

        expect(tester.takeException(), isNull);
      });

      testWidgets('Deudas y crédito — expediente de tarjeta ($etiqueta): cero overflow', (tester) async {
        final egresoRepo = EgresoRepositoryImpl(db);
        final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
        final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
        final creada = (await registrar.ejecutar(
          nombre: 'TDC BBVA',
          tipo: 'tarjetaCredito',
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 3600000,
          saldoInicial: 3600000,
          tarjetaUltimosDigitos: '4215',
          tarjetaLimiteCredito: 5000000,
          tarjetaDiaCorte: 12,
          tarjetaDiaPago: 2,
          tarjetaPagoMinimo: 200000,
          referencia: 'Cuenta 001',
          tasaInteres: 24.5,
        ) as RegistrarDeudaExitoso)
            .deuda;

        await pump(tester, db, tamano: tamano, tema: entradaTema.value, rutaInicial: '/finanzas/deudas-y-credito/${creada.id}');

        expect(tester.takeException(), isNull);
      });

      testWidgets('Diálogo "Registrar deuda" — tipo Tarjeta de crédito ($etiqueta): cero overflow', (tester) async {
        await pump(tester, db, tamano: tamano, tema: entradaTema.value);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        await tester.tap(find.byKey(const Key('deudas_credito_boton_registrar')));
        await tester.pumpAndSettle();

        final selectorTipo = find.byWidgetPredicate((w) => w is RisegSelect<TipoDeuda> && w.value == TipoDeuda.prestamo);
        await tester.ensureVisible(selectorTipo);
        await tester.pumpAndSettle();
        await tester.tap(selectorTipo);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.deudaTipoTarjetaCredito).last);
        await tester.pumpAndSettle();

        // Todos los campos nuevos de la sección de tarjeta deben
        // renderizar sin desbordar, en ambas variantes de la regla.
        expect(find.text(l10n.registrarDeudaCampoSaldoInicial), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoFechaSaldoInicial), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoReglaFechaPago), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoDiaPago), findsOneWidget, reason: 'regla por defecto: día fijo');
        expect(tester.takeException(), isNull);

        final selectorRegla = find.byWidgetPredicate((w) => w is RisegSelect<ReglaFechaLimitePagoTarjeta>);
        await tester.ensureVisible(selectorRegla);
        await tester.pumpAndSettle();
        await tester.tap(selectorRegla);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.registrarDeudaReglaDiasDespuesCorte).last);
        await tester.pumpAndSettle();

        expect(find.text(l10n.registrarDeudaCampoDiasDespuesCorte), findsOneWidget, reason: 'cambiar a la otra regla debe mostrar su propio campo');
        expect(
          find.text(l10n.registrarDeudaCampoCicloCubierto),
          findsOneWidget,
          reason: 'Etapa "ciclo de TDC" — el checkbox de reconciliación de apertura debe renderizar sin desbordar en cualquier ancho',
        );
        expect(
          find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoImporteOriginal),
          findsNothing,
          reason: 'una TDC nunca muestra Importe original',
        );
        expect(
          find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoPagoMinimo),
          findsNothing,
          reason: 'Pago mínimo ya no es parte del alta de una TDC',
        );
        expect(tester.takeException(), isNull);

        // Tasa variable (caso real Konfío Empresarial) + CAT — todos
        // los campos nuevos deben renderizar sin desbordar.
        final selectorTipoTasa = find.byWidgetPredicate((w) => w is RisegSelect<TipoTasaTarjeta?> && w.value == null);
        await tester.ensureVisible(selectorTipoTasa);
        await tester.pumpAndSettle();
        await tester.tap(selectorTipoTasa);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.registrarDeudaTipoTasaVariable).last);
        await tester.pumpAndSettle();

        expect(find.text(l10n.registrarDeudaCampoTasaReferencia), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoTasaDiferencial), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoTasaMasIva), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoTasaDescripcion), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoCat), findsOneWidget);
        expect(find.text(l10n.registrarDeudaCampoCatIncluyeIva), findsOneWidget);
        expect(
          find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarDeudaCampoTasaOrdinariaAnual),
          findsNothing,
          reason: 'con regla variable, el campo de tasa fija no debe mostrarse',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
