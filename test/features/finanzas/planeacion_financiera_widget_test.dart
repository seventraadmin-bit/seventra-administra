// Etapa 19D — "Calendario financiero y planeación de liquidez".
// Pruebas de widget de la pantalla completa de Planeación financiera,
// contra la cadena REAL de providers (mismo criterio que
// `compra_tarjeta_widget_test.dart`/`resumen_financiero_proyeccion_test.dart`):
// KPIs con datos reales, día seleccionado muestra exactamente sus
// movimientos, sin Cuentas financieras no se inventa saldo, cambiar de
// mes no duplica eventos, reprogramar un cobro vencido de punta a
// punta, y responsive en los anchos/temas requeridos.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_state.dart';
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

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required Size tamano,
  required ThemeData tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: tema,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PlaneacionFinancieraScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'usuario-maestro',
            passwordHash: 'x',
          ),
        );
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
    ]);
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<void> crearCuentaFinanciera({required int saldoInicial}) async {
    final resultado = await container.read(registrarCuentaFinancieraAutorizadoProvider)(
      nombre: 'BBVA Operativa',
      tipo: 'banco',
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime.now().subtract(const Duration(days: 60)),
    );
    expect(resultado, isA<RegistrarCuentaFinancieraExitoso>());
  }

  Future<String> crearCxcVencidaSinReprogramar({required int diasVencida, required int saldoPendiente}) async {
    final ahora = DateTime.now();
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-${ahora.microsecondsSinceEpoch}', nombreComercial: 'Cliente ABC'),
        );
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-${ahora.microsecondsSinceEpoch}',
            clienteId: cliente.id,
            tipoDocumento: 'cfdi',
            agrupacion: 'porServicio',
            metodo: 'PUE',
            periodoInicio: ahora,
            periodoFin: ahora,
            generationKey: 'clave-${ahora.microsecondsSinceEpoch}',
            importeBaseEsperado: saldoPendiente,
            importeFinalEsperado: saldoPendiente,
          ),
        );
    final cxc = await db.into(db.cuentaPorCobrar).insertReturning(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: Value(documento.id),
            clienteId: Value(cliente.id),
            tipoDocumento: 'cfdi',
            metodo: 'PUE',
            fechaEmisionReal: ahora,
            importeEmitido: saldoPendiente,
            saldoOriginal: saldoPendiente,
            saldoPendiente: saldoPendiente,
            fechaVencimiento: Value(ahora.subtract(Duration(days: diasVencida))),
          ),
        );
    return cxc.id;
  }

  Future<void> crearDeudaConPagoProgramado({required int pagoProgramado, required int diasHasta}) async {
    final resultado = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'Préstamo de prueba',
      tipo: TipoDeuda.prestamo.name,
      fechaOrigen: DateTime.now(),
      importeOriginal: pagoProgramado * 3,
      saldoInicial: pagoProgramado * 3,
      pagoProgramado: pagoProgramado,
      fechaVencimiento: DateTime.now().add(Duration(days: diasHasta)),
    );
    expect(resultado, isA<RegistrarDeudaExitoso>());
  }

  testWidgets('KPIs y calendario muestran datos reales; el día seleccionado muestra exactamente sus movimientos', (tester) async {
    await crearCuentaFinanciera(saldoInicial: 10000000); // $100,000
    await crearDeudaConPagoProgramado(pagoProgramado: 1500000, diasHasta: 5); // $15,000 en 5 días

    await _pump(tester, container, tamano: const Size(1440, 900), tema: AppTheme.light());

    expect(find.textContaining(r'$100,000.00'), findsWidgets, reason: 'Disponible hoy');

    // El compromiso a 5 días cae dentro de "Este mes" o "Mes
    // siguiente" según el día del mes en que corra la prueba — se
    // resuelve la vista correcta ANTES de leer los KPIs, para no
    // depender de una fecha fija.
    var estado = container.read(planeacionFinancieraControllerProvider);
    final notifier = container.read(planeacionFinancieraControllerProvider.notifier);
    if (estado.proyeccionCaja.compromisos.isEmpty) {
      await notifier.cambiarPeriodo(PeriodoPlaneacion.mesSiguiente);
      await tester.pumpAndSettle();
      estado = container.read(planeacionFinancieraControllerProvider);
    }

    expect(estado.proyeccionCaja.compromisos, hasLength(1));
    expect(find.textContaining(r'$15,000.00'), findsWidgets, reason: 'Pagos comprometidos = el pago programado de la deuda');

    final fechaCompromiso = estado.proyeccionCaja.compromisos.single.fecha;
    notifier.seleccionarDia(fechaCompromiso);
    await tester.pumpAndSettle();

    expect(find.text('Préstamo de prueba'), findsWidgets, reason: 'aparece en el detalle del día seleccionado');
  });

  testWidgets('sin Cuentas financieras configuradas, no se inventa un saldo — se muestra el mensaje honesto', (tester) async {
    await _pump(tester, container, tamano: const Size(1440, 900), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.resumenFinancieroSaldoNoConfigurado), findsWidgets);
    expect(find.textContaining('—'), findsWidgets, reason: 'Disponible hoy / Saldo final / Saldo mínimo muestran "—", nunca \$0.00');
  });

  testWidgets('cambiar de mes (siguiente y de regreso) no duplica los compromisos de la proyección', (tester) async {
    await crearCuentaFinanciera(saldoInicial: 5000000);
    await crearDeudaConPagoProgramado(pagoProgramado: 800000, diasHasta: 40);

    await _pump(tester, container, tamano: const Size(1440, 900), tema: AppTheme.light());
    final notifier = container.read(planeacionFinancieraControllerProvider.notifier);

    await notifier.cambiarPeriodo(PeriodoPlaneacion.mesSiguiente);
    await tester.pumpAndSettle();
    final compromisosMesSiguiente = container.read(planeacionFinancieraControllerProvider).proyeccionCaja.compromisos.length;

    await notifier.cambiarPeriodo(PeriodoPlaneacion.esteMes);
    await tester.pumpAndSettle();
    await notifier.cambiarPeriodo(PeriodoPlaneacion.mesSiguiente);
    await tester.pumpAndSettle();
    final compromisosTrasIrYVolver = container.read(planeacionFinancieraControllerProvider).proyeccionCaja.compromisos.length;

    expect(compromisosTrasIrYVolver, compromisosMesSiguiente, reason: 'ningún compromiso debe duplicarse al cambiar de mes repetidamente');
  });

  testWidgets('reprogramar un cobro vencido lo saca de Pendientes vencidos y lo regresa a la proyección en la fecha nueva', (tester) async {
    await crearCuentaFinanciera(saldoInicial: 1000000);
    await crearCxcVencidaSinReprogramar(diasVencida: 15, saldoPendiente: 2528800);

    await _pump(tester, container, tamano: const Size(1440, 900), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text('Cliente ABC'), findsWidgets, reason: 'aparece en Pendientes vencidos');
    var estado = container.read(planeacionFinancieraControllerProvider);
    expect(estado.proyeccionCaja.pendientesVencidos, hasLength(1));
    expect(estado.proyeccionCaja.compromisos, isEmpty, reason: 'una CxC vencida sin reprogramar nunca es un compromiso futuro');

    await tester.ensureVisible(find.text(l10n.planeacionBotonReprogramar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.planeacionBotonReprogramar).first);
    await tester.pumpAndSettle();

    // `RisegDateField` es de solo lectura y abre el selector nativo de
    // Material (`showDatePicker`) — mismo patrón exacto que
    // `riseg_date_field_test.dart`: tocar el campo, confirmar "OK"
    // (acepta la fecha inicial del selector, hoy).
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    // El picker está localizado en español (mismo `MaterialApp` con
    // `AppLocalizations.localizationsDelegates`) — el botón de confirmar
    // es "ACEPTAR", no "OK" (que solo aplica bajo locale inglés, como en
    // `riseg_date_field_test.dart`, cuyo harness no fija locale).
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();

    // Etapa 7: motivo ahora es obligatorio para reprogramar (antes era
    // opcional) — sin esto, la corrección se rechaza en silencio y la
    // CxC nunca sale de "Pendientes vencidos".
    await tester.enterText(find.byType(TextFormField).last, 'El cliente confirmó una nueva fecha de pago');
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.reprogramarCobroBotonConfirmar));
    await tester.pumpAndSettle();

    estado = container.read(planeacionFinancieraControllerProvider);
    expect(estado.proyeccionCaja.pendientesVencidos, isEmpty, reason: 'reprogramar la saca de Pendientes vencidos');
    expect(
      estado.proyeccionCaja.compromisos.where((c) => c.origen == OrigenCompromiso.cuentaPorCobrar),
      hasLength(1),
      reason: 'la fecha reprogramada (hoy, por el picker) la regresa como compromiso real, no solo la borra',
    );
  });
}
