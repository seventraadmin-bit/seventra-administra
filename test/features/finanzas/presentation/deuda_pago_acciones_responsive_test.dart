// Etapa 9 — punto 21 del pedido: los diálogos nuevos ("Corregir pago" y
// "Cancelar pago") y el expediente con historial largo, a
// 1536/1366/1024/700/500 × claro/oscuro. Mismo criterio de evidencia
// que el resto de RISEG ONE: sin herramienta de captura, la prueba es
// "cero overflow / cero excepción" (`tester.takeException()`).
//
// Cubre a propósito los dos tipos de Deuda (préstamo y TDC), importes
// grandes, un nombre de cuenta largo y un historial con muchos
// movimientos — que es donde una tabla de historial se desborda.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deuda_expediente_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/widgets/cancelar_pago_deuda_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/widgets/corregir_pago_deuda_dialog.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
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

const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;
  late DeudaData prestamo;
  late DeudaData tarjeta;
  late MovimientoDeudaData pagoPrestamo;
  late MovimientoDeudaData pagoTarjeta;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_deuda_pago_responsive_test_');
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

    // Nombre de cuenta deliberadamente largo + importes grandes.
    final cuenta = await container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: 'CTA-0003',
          nombre: 'BBVA Empresarial — cuenta concentradora de nómina y proveedores',
          tipo: 'banco',
          saldoInicial: 9800000000,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );

    final registrarDeuda = container.read(registrarDeudaUseCaseProvider);
    prestamo = ((await registrarDeuda.ejecutar(
      nombre: 'SANDRA PRESTAMO PERSONAL — financiamiento de capital de trabajo',
      tipo: 'prestamo',
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: 8000000000,
      saldoInicial: 8000000000,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    )) as RegistrarDeudaExitoso)
        .deuda;
    tarjeta = ((await registrarDeuda.ejecutar(
      nombre: 'TDC Konfío Empresarial — línea revolvente principal',
      tipo: 'tarjetaCredito',
      saldoInicial: 3326608,
      fechaSaldoInicial: DateTime(2026, 1, 1),
      tarjetaLimiteCredito: 400000000,
      tarjetaDiaCorte: 17,
      tarjetaDiasDespuesCorte: 20,
      tarjetaReglaFechaPago: ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name,
    )) as RegistrarDeudaExitoso)
        .deuda;

    // Historial largo: 12 pagos sobre el préstamo.
    final registrarPago = container.read(registrarPagoDeudaUseCaseProvider);
    for (var mes = 1; mes <= 12; mes++) {
      await registrarPago.ejecutar(
        deudaId: prestamo.id,
        fecha: DateTime(2026, mes, 5),
        importe: 12345678,
        formaPago: 'transferencia',
        cuentaFinancieraId: cuenta.id,
        observaciones: 'Abono mensual correspondiente al periodo $mes de la reestructura acordada con el acreedor',
      );
    }
    await registrarPago.ejecutar(
      deudaId: tarjeta.id,
      fecha: DateTime(2026, 3, 5),
      importe: 500000,
      formaPago: 'transferencia',
      cuentaFinancieraId: cuenta.id,
    );

    final repo = container.read(deudaRepositoryProvider);
    pagoPrestamo = (await repo.listarMovimientos(prestamo.id))
        .lastWhere((m) => m.tipo == TipoMovimientoDeuda.pago.name);
    pagoTarjeta = (await repo.listarMovimientos(tarjeta.id))
        .lastWhere((m) => m.tipo == TipoMovimientoDeuda.pago.name);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size tamano,
    required bool oscuro,
    required Widget Function(BuildContext, WidgetRef) builder,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/pantalla',
      routes: [
        GoRoute(
          path: '/pantalla',
          builder: (context, state) => Consumer(builder: (context, ref, _) => builder(context, ref)),
        ),
        GoRoute(path: '/finanzas/deudas-y-credito/:id', builder: (_, __) => const Scaffold(body: SizedBox.shrink())),
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
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirDialogo(
    WidgetTester tester, {
    required Size tamano,
    required bool oscuro,
    required Future<void> Function(BuildContext, WidgetRef) abrir,
  }) async {
    await pump(
      tester,
      tamano: tamano,
      oscuro: oscuro,
      builder: (context, ref) => Scaffold(
        body: Center(child: ElevatedButton(onPressed: () => abrir(context, ref), child: const Text('abrir'))),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  for (final entrada in _anchos.entries) {
    final etiqueta = entrada.key;
    final tamano = entrada.value;

    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('Expediente de préstamo con historial largo ($etiqueta, $tema): cero overflow', (tester) async {
        await pump(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          builder: (_, __) => DeudaExpedienteScreen(deudaId: prestamo.id),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Expediente de TDC ($etiqueta, $tema): cero overflow', (tester) async {
        await pump(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          builder: (_, __) => DeudaExpedienteScreen(deudaId: tarjeta.id),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Corregir pago ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoCorregirPagoDeuda(
            context,
            ref,
            deuda: prestamo,
            pago: pagoPrestamo,
            importeNeto: pagoPrestamo.importe,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Corregir pago'), findsWidgets);
      });

      testWidgets('Cancelar pago de TDC ($etiqueta, $tema): cero overflow', (tester) async {
        await abrirDialogo(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          abrir: (context, ref) => mostrarDialogoCancelarPagoDeuda(
            context,
            ref,
            pago: pagoTarjeta,
            importeNeto: pagoTarjeta.importe,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Cancelar pago'), findsWidgets);
      });
    }
  }

  testWidgets('un motivo largo no desborda el diálogo de cancelación a 500px', (tester) async {
    await abrirDialogo(
      tester,
      tamano: const Size(500, 900),
      oscuro: false,
      abrir: (context, ref) => mostrarDialogoCancelarPagoDeuda(
        context,
        ref,
        pago: pagoTarjeta,
        importeNeto: pagoTarjeta.importe,
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      'El pago se capturó por duplicado durante la conciliación bancaria de marzo, '
      'después de que el estado de cuenta llegara con dos cargos idénticos que el banco '
      'terminó aclarando como un solo movimiento real',
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
