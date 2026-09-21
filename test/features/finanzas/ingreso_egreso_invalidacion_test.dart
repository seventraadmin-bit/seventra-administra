// Etapa "Ingresos y Egresos: corrección, cancelación, origen automático
// y trazabilidad integral", Sección 21: `registrarManual`/`corregir`/
// `cancelar` (Ingresos) y `registrar`/`corregir`/`cancelar` (Egresos)
// invalidan EXACTAMENTE Resumen financiero, Planeación financiera y
// Dashboard — nunca Pagos, que no cambia con ninguna de estas
// operaciones. Se cuenta cuántas veces cada provider se reconstruye
// (`container.listen`), no solo el valor final — mismo criterio que
// `cuenta_por_cobrar_invalidacion_test.dart` (Etapa 7).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
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

Future<void> _asentar(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  while (container.read(resumenFinancieroControllerProvider).cargando ||
      container.read(planeacionFinancieraControllerProvider).cargando ||
      container.read(dashboardControllerProvider).cargando) {
    await Future<void>.delayed(Duration.zero);
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
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => db.close());

  test(
    'Ingresos: registrarManual/corregir/cancelar invalidan EXACTAMENTE Resumen/Planeación/Dashboard, nunca Pagos',
    () async {
      var resumenCount = 0, planeacionCount = 0, dashboardCount = 0, pagosCount = 0;
      container.listen(resumenFinancieroControllerProvider, (_, _) {});
      container.listen(planeacionFinancieraControllerProvider, (_, _) {});
      container.listen(dashboardControllerProvider, (_, _) {});
      container.listen(pagosControllerProvider, (_, _) {});
      await _asentar(container);
      while (container.read(pagosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }

      final controller = container.read(ingresosControllerProvider.notifier);

      container.listen(resumenFinancieroControllerProvider, (_, _) => resumenCount++);
      container.listen(planeacionFinancieraControllerProvider, (_, _) => planeacionCount++);
      container.listen(dashboardControllerProvider, (_, _) => dashboardCount++);
      container.listen(pagosControllerProvider, (_, _) => pagosCount++);

      final registrado = await controller.registrarManual(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final ingresoId = (registrado as RegistrarIngresoManualExitoso).ingreso.id;
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'registrarManual() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'registrarManual() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'registrarManual() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'registrarManual() nunca debe tocar Pagos');

      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.corregir(ingresoId: ingresoId, monto: 200000, motivo: 'Corrección de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'corregir() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'corregir() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'corregir() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'corregir() nunca debe tocar Pagos');

      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.cancelar(ingresoId: ingresoId, motivo: 'Cancelación de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'cancelar() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'cancelar() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'cancelar() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'cancelar() nunca debe tocar Pagos');
    },
  );

  test(
    'Egresos: registrar/corregir/cancelar invalidan EXACTAMENTE Resumen/Planeación/Dashboard, nunca Pagos',
    () async {
      var resumenCount = 0, planeacionCount = 0, dashboardCount = 0, pagosCount = 0;
      container.listen(resumenFinancieroControllerProvider, (_, _) {});
      container.listen(planeacionFinancieraControllerProvider, (_, _) {});
      container.listen(dashboardControllerProvider, (_, _) {});
      container.listen(pagosControllerProvider, (_, _) {});
      await _asentar(container);
      while (container.read(pagosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }

      final controller = container.read(egresosControllerProvider.notifier);

      container.listen(resumenFinancieroControllerProvider, (_, _) => resumenCount++);
      container.listen(planeacionFinancieraControllerProvider, (_, _) => planeacionCount++);
      container.listen(dashboardControllerProvider, (_, _) => dashboardCount++);
      container.listen(pagosControllerProvider, (_, _) => pagosCount++);

      final registrado = await controller.registrar(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final egresoId = (registrado as RegistrarEgresoExitoso).egreso.id;
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'registrar() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'registrar() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'registrar() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'registrar() nunca debe tocar Pagos');

      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.corregir(egresoId: egresoId, monto: 200000, motivo: 'Corrección de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'corregir() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'corregir() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'corregir() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'corregir() nunca debe tocar Pagos');

      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.cancelar(egresoId: egresoId, motivo: 'Cancelación de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'cancelar() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'cancelar() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'cancelar() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'cancelar() nunca debe tocar Pagos');
    },
  );
}
