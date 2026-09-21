// Etapa 15 — reproducción real del bug reportado: cancelar un Pago
// desde Finanzas → Pagos (`PagosController.cancelar`, distinto de la
// ruta ya corregida desde el diálogo de detalle de CxC) reabre
// correctamente el saldo de la Cuenta por cobrar en la base de datos,
// pero `cuentasPorCobrarControllerProvider` nunca se invalidaba —
// el listado de Cuentas por cobrar seguía mostrando "Pagada" hasta
// cambiar de pestaña. Corregido en `PagosController.cancelar`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show generarCodigoUseCaseProvider;
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
  late String pagoId;
  late String cuentaId;

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

    final clienteRepo = ClienteRepositoryImpl(db);
    final crearCliente = CrearClienteUseCase(clienteRepo, container.read(generarCodigoUseCaseProvider));
    final cliente = (await crearCliente.ejecutar(nombreComercial: 'TIKAL')).when(
      ok: (c) => c,
      failure: (f) => throw StateError(f.message),
    );

    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-P900',
            clienteId: cliente.id,
            tipoDocumento: 'reciboDePago',
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GK-DOC-P900',
            importeBaseEsperado: 3400000,
            importeFinalEsperado: 3400000,
            estatus: const Value('procesadoAceptado'),
          ),
        );
    final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: Value(documento.id),
            clienteId: Value(cliente.id),
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 1, 5),
            importeEmitido: 3400000,
            saldoOriginal: 3400000,
            saldoPendiente: 3400000,
          ),
        );
    cuentaId = cuenta.id;

    final pagoRepo = container.read(pagoRepositoryProvider);
    final pago = await pagoRepo.crear(
      folioPago: 'PAG-000003',
      clienteId: cliente.id,
      montoTotal: 3400000,
      fechaPago: DateTime(2026, 8, 10),
      formaPago: 'transferencia',
    );
    await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: cuentaId, monto: 3400000);
    pagoId = pago.id;
  });

  tearDown(() => db.close());

  Future<void> esperarCargaCuentas() async {
    container.listen(cuentasPorCobrarControllerProvider, (_, _) {});
    while (container.read(cuentasPorCobrarControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'cancelar el Pago desde PagosController refleja de inmediato el saldo reabierto en '
    'cuentasPorCobrarControllerProvider, sin cambiar de pestaña ni recargar manualmente',
    () async {
      // Precondición: el listado de Cuentas por cobrar ya estaba
      // "abierto" (su provider vivo) ANTES de cancelar el Pago.
      await esperarCargaCuentas();
      expect(container.read(cuentasPorCobrarControllerProvider).cuentas.single.estatus, 'pagada');
      expect(container.read(cuentasPorCobrarControllerProvider).cuentas.single.saldoPendiente, 0);

      final resultado = await container.read(pagosControllerProvider.notifier).cancelar(
            pagoId: pagoId,
            motivo: 'Duplicado por error',
          );
      expect(resultado.runtimeType.toString(), 'CancelarPagoExitoso');

      // Sin ningún `recargar()`/`invalidate` manual desde la prueba —
      // el propio `PagosController.cancelar` debe haber invalidado
      // `cuentasPorCobrarControllerProvider`.
      await Future<void>.delayed(Duration.zero);
      await esperarCargaCuentas();

      final cuenta = container.read(cuentasPorCobrarControllerProvider).cuentas.singleWhere((c) => c.id == cuentaId);
      expect(cuenta.estatus, 'pendiente');
      expect(cuenta.saldoPendiente, 3400000);
    },
  );
}
