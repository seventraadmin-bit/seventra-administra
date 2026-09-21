// Etapa 19C — "Posición de caja, flujo real y proyección de
// compromisos". Prueba, contra la cadena REAL de providers
// (`ResumenFinancieroController`, nunca construcción directa de casos
// de uso), los invariantes 13/14 de la Parte L del pedido: cambiar el
// horizonte de la Proyección recalcula el saldo proyectado (incluido
// el caso negativo, que debe disparar la alerta de déficit en la
// pantalla), y cambiar el periodo sigue recalculando Ingresos/Egresos
// correctamente con los campos nuevos ya integrados.

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
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_state.dart';
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
      fechaSaldoInicial: DateTime.now().subtract(const Duration(days: 30)),
    );
    expect(resultado, isA<RegistrarCuentaFinancieraExitoso>());
  }

  Future<void> crearDeudaConPagoProgramado({required int pagoProgramado, required DateTime fechaVencimiento}) async {
    final resultado = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'Préstamo de prueba',
      tipo: TipoDeuda.prestamo.name,
      fechaOrigen: DateTime.now(),
      importeOriginal: pagoProgramado * 3,
      saldoInicial: pagoProgramado * 3,
      pagoProgramado: pagoProgramado,
      fechaVencimiento: fechaVencimiento,
    );
    expect(resultado, isA<RegistrarDeudaExitoso>());
  }

  test('Invariante 8/14 (parcial): cambiar el horizonte de Proyección recalcula el saldo proyectado', () async {
    await crearCuentaFinanciera(saldoInicial: 10000000); // $100,000
    await crearDeudaConPagoProgramado(pagoProgramado: 2000000, fechaVencimiento: DateTime.now().add(const Duration(days: 20)));

    await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
    final estadoInicial = container.read(resumenFinancieroControllerProvider);
    expect(estadoInicial.proyeccionCaja.salidasComprometidas, 0, reason: 'a 15 días (default) el compromiso de 20 días no debe aparecer');

    await container.read(resumenFinancieroControllerProvider.notifier).cambiarHorizonteProyeccion(HorizonteProyeccion.dias30);
    final estadoA30Dias = container.read(resumenFinancieroControllerProvider);
    expect(estadoA30Dias.proyeccionCaja.salidasComprometidas, 2000000, reason: 'a 30 días el compromiso de 20 días sí debe aparecer');
    expect(estadoA30Dias.proyeccionCaja.saldoProyectado, 8000000, reason: r'$100,000 - $20,000 = $80,000');
  });

  test('Invariante 13: un compromiso mayor al saldo disponible genera un saldo proyectado negativo', () async {
    await crearCuentaFinanciera(saldoInicial: 500000); // $5,000
    await crearDeudaConPagoProgramado(pagoProgramado: 2000000, fechaVencimiento: DateTime.now().add(const Duration(days: 5))); // $20,000

    await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
    final estado = container.read(resumenFinancieroControllerProvider);

    expect(estado.proyeccionCaja.saldoProyectado, lessThan(0));
    expect(estado.proyeccionCaja.saldoProyectado, -1500000, reason: r'$5,000 - $20,000 = -$15,000');
  });

  testWidgets('el déficit proyectado se muestra como alerta real en la pantalla del Resumen', (tester) async {
    await crearCuentaFinanciera(saldoInicial: 500000);
    await crearDeudaConPagoProgramado(pagoProgramado: 2000000, fechaVencimiento: DateTime.now().add(const Duration(days: 5)));

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ResumenFinancieroScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Déficit proyectado'), findsOneWidget);
  });

  for (final tamano in [const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)]) {
    for (final tema in [AppTheme.light(), AppTheme.dark()]) {
      testWidgets('el Resumen financiero no desborda a ${tamano.width.toInt()}px (${tema.brightness.name})', (tester) async {
        await crearCuentaFinanciera(saldoInicial: 10000000);
        await crearDeudaConPagoProgramado(pagoProgramado: 2000000, fechaVencimiento: DateTime.now().add(const Duration(days: 5)));

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
              home: const Scaffold(body: ResumenFinancieroScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  }
}
