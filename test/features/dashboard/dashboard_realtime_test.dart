// Etapa 15 — reproducción real del hallazgo reportado: Dashboard
// montado (mismo mecanismo que preserva las ramas del shell,
// `StatefulShellRoute.indexedStack` — ver `dashboardControllerProvider`,
// `AutoDisposeNotifierProvider` sin `family`) permanecía con los
// valores anteriores después de registrar un Egreso en otro módulo,
// hasta que el usuario cambiaba de pestaña. Corregido agregando
// `ref.invalidate(dashboardControllerProvider)` en cada mutador real
// (Ingresos/Egresos/Compras/Nómina/cancelaciones/eliminaciones
// físicas) — esta prueba ejercita el caso de Egresos de punta a punta
// contra el mismo `ProviderContainer` que ya está "escuchando" el
// Dashboard, sin ningún `recargar()`/`invalidate` manual desde la
// prueba misma.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
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
    // `EgresoEvento.actorUsuarioId` es una FK real hacia `Usuario` —
    // debe existir de antemano o el registro falla con
    // `RegistrarEgresoErrorInesperado` (mismo hallazgo real ya
    // documentado en las pruebas de eliminación física).
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

  Future<void> esperarCargaDashboard() async {
    container.listen(dashboardControllerProvider, (_, _) {});
    while (container.read(dashboardControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'Dashboard ya montado (provider vivo) refleja de inmediato un Egreso registrado en otro módulo, '
    'sin cambiar de pestaña ni recargar manualmente',
    () async {
      await esperarCargaDashboard();
      expect(container.read(dashboardControllerProvider).resumenGeneral?.totalEgresos, 0);

      final resultado = await container.read(egresosControllerProvider.notifier).registrar(
            monto: 150000,
            fecha: DateTime.now(),
            formaPago: 'transferencia',
            concepto: 'Prueba Dashboard tiempo real',
          );
      expect(resultado, isA<RegistrarEgresoExitoso>());

      // Sin ningún `recargar()`/`invalidate` manual desde la prueba —
      // el propio `EgresosController.registrar` debe haber invalidado
      // `dashboardControllerProvider`.
      await esperarCargaDashboard();

      expect(container.read(dashboardControllerProvider).resumenGeneral?.totalEgresos, 150000);
    },
  );

  test(
    'Dashboard ya montado refleja de inmediato la cancelación de ese Egreso, sin recargar manualmente',
    () async {
      await esperarCargaDashboard();

      final registrado = await container.read(egresosControllerProvider.notifier).registrar(
            monto: 150000,
            fecha: DateTime.now(),
            formaPago: 'transferencia',
            concepto: 'Prueba Dashboard tiempo real',
          );
      final egresoId = (registrado as RegistrarEgresoExitoso).egreso.id;
      await esperarCargaDashboard();
      expect(container.read(dashboardControllerProvider).resumenGeneral?.totalEgresos, 150000);

      final cancelado = await container.read(egresosControllerProvider.notifier).cancelar(
            egresoId: egresoId,
            motivo: 'Prueba de cancelación',
          );
      expect(cancelado, isA<CancelarEgresoExitoso>());

      await esperarCargaDashboard();
      expect(container.read(dashboardControllerProvider).resumenGeneral?.totalEgresos, 0);
    },
  );
}
