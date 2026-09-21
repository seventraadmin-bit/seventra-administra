// Auditoría integral 19A-19D — "Auditar transacciones" (Parte 5 del
// pedido). Verifica, para una operación financiera representativa
// compuesta por más de una escritura, que un fallo a mitad de la
// transacción no deja ningún rastro parcial ("todo se guarda o nada se
// guarda").
//
// El resto de las operaciones listadas en el pedido (Compra normal/TDC/
// corrección/eliminación física, pago CxC, cancelación de aplicación de
// pago, pago Nómina, pago Deuda) usan exactamente el mismo mecanismo —
// `AppDatabase.transaction()` de Drift, confirmado por lectura directa
// de cada repositorio (`CompraRepositoryImpl.crear/corregir/cancelar/
// eliminarFisicamente`, `PagoRepositoryImpl.crearAplicado/cancelar/
// _cancelarAplicacionInterna`, `PagoNominaRepositoryImpl.crear`,
// `DeudaRepositoryImpl.registrarPago`), así que esta prueba sirve de
// caso representativo del mismo patrón estructural, no de cada
// operación por separado.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'PagoRepositoryImpl.crearAplicado: un fallo en el 2° paso (aplicar a una CxC inexistente) '
    'revierte también el 1° INSERT (Pago) — nada queda a medias',
    () async {
      final pagoRepo = PagoRepositoryImpl(db);

      // `cuentaPorCobrarId` deliberadamente inexistente: `_crear` (Pago)
      // se ejecuta primero y con éxito; `_aplicar` falla después (fila
      // no encontrada o violación de FK) — ambos ocurren dentro de la
      // MISMA transacción (`crearAplicado`), así que es el caso real
      // para probar que un fallo en el 2° paso revierte el 1°.
      await expectLater(
        () => pagoRepo.crearAplicado(
          folioPago: 'PAG-ATOMICIDAD-01',
          clienteId: 'cliente-inexistente',
          montoTotal: 100000,
          fechaPago: DateTime(2026, 1, 1),
          formaPago: 'transferencia',
          cuentaPorCobrarId: 'cxc-que-no-existe',
        ),
        throwsA(anything),
      );

      final pagos = await db.select(db.pago).get();
      final aplicaciones = await db.select(db.aplicacionPago).get();
      expect(pagos, isEmpty, reason: 'el INSERT de Pago (1er paso) debe revertirse cuando aplicar a la CxC (2° paso) falla');
      expect(aplicaciones, isEmpty, reason: 'ninguna AplicacionPago parcial debe sobrevivir a la excepción');
    },
  );

  test(
    'DeudaRepositoryImpl.crear: la Deuda respeta su propio CHECK (saldo_actual >= 0) — '
    'un saldoInicial negativo nunca deja una Deuda inconsistente a medias',
    () async {
      final deudaRepo = DeudaRepositoryImpl(db, EgresoRepositoryImpl(db));

      await expectLater(
        () => deudaRepo.crear(
          folio: 'DEU-ATOMICIDAD-01',
          nombre: 'Deuda de prueba (transacción forzada a fallar)',
          tipo: TipoDeuda.prestamo.name,
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 1000000,
          saldoInicial: -1, // viola CHECK (saldo_actual >= 0) de la propia tabla Deuda
        ),
        throwsA(anything),
      );

      final deudas = await db.select(db.deuda).get();
      final movimientos = await db.select(db.movimientoDeuda).get();
      expect(deudas, isEmpty, reason: 'la Deuda inválida no debe quedar creada');
      expect(movimientos, isEmpty, reason: 'sin Deuda válida, tampoco debe existir su movimiento de apertura');
    },
  );
}
