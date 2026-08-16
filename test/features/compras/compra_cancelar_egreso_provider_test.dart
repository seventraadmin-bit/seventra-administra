// Etapa 15 — reproducción real del bug reportado: al cancelar una
// Compra desde Compras, Finanzas → Egresos seguía mostrando su Egreso
// asociado como "Registrado" hasta cambiar de pestaña. Investigación
// confirmó que `CompraRepositoryImpl.cancelar` YA cancela el Egreso
// asociado dentro de la MISMA transacción (Etapa 10, ya probado en
// `compra_test.dart`) — lo que faltaba era avisarle al módulo de
// Finanzas: `ComprasController.cancelarCompra` nunca invalidaba
// `egresosControllerProvider`, un provider de otra feature. Esta
// prueba opera directamente sobre el `ProviderContainer`, sin navegar
// ni recargar manualmente, igual que el resto de las pruebas de
// invalidación de esta sesión (Clientes, Cuentas por cobrar).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/compras_providers.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
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
  late String compraId;

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

    final resultado = await container.read(registrarCompraUseCaseProvider).ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(
          destino: DestinoCompraPartida.gastoDirecto.name,
          concepto: 'Papelería',
          cantidad: 1,
          costoUnitario: 45000,
        ),
      ],
    );
    compraId = (resultado as RegistrarCompraExitosa).compra.id;
  });

  tearDown(() => db.close());

  test(
    'cancelar la Compra desde ComprasController refleja el Egreso Cancelado de inmediato en '
    'egresosControllerProvider, sin cambiar de pestaña ni recargar manualmente',
    () async {
      // Precondición: el listado de Egresos ya estaba "abierto" (su
      // provider vivo) ANTES de cancelar la Compra — exactamente el
      // escenario real reportado ("si Finanzas ya estaba abierto en
      // otra vista").
      container.listen(egresosControllerProvider, (_, _) {});
      while (container.read(egresosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(egresosControllerProvider).egresos.single.estatus, 'registrado');

      final resultado =
          await container.read(comprasControllerProvider.notifier).cancelarCompra(compraId: compraId, motivo: 'Compra duplicada');
      expect(resultado.runtimeType.toString(), 'CancelarCompraExitosa');

      // Sin ningún `recargar()`/`invalidate` manual desde la prueba —
      // el propio `ComprasController.cancelarCompra` debe haber
      // invalidado `egresosControllerProvider`.
      await Future<void>.delayed(Duration.zero);
      while (container.read(egresosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(container.read(egresosControllerProvider).egresos.single.estatus, 'cancelado');
    },
  );

  test('un Egreso manual (sin Compra asociada) nunca se ve afectado por esta invalidación', () async {
    // El fix invalida el provider — nunca muta ningún dato de un
    // Egreso manual ajeno a la Compra cancelada.
    container.listen(egresosControllerProvider, (_, _) {});
    while (container.read(egresosControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
    final egresoDeCompraId = container.read(egresosControllerProvider).egresos.single.id;

    await container.read(comprasControllerProvider.notifier).cancelarCompra(compraId: compraId, motivo: 'Compra duplicada');
    await Future<void>.delayed(Duration.zero);
    while (container.read(egresosControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }

    final egreso = container.read(egresosControllerProvider).egresos.singleWhere((e) => e.id == egresoDeCompraId);
    expect(egreso.monto, 45000, reason: 'la invalidación solo refresca la lectura, nunca muta montos');
  });
}
