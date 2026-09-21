// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" —
// protege el punto 2 del pedido: `formaPago` puede conservarse como
// etiqueta descriptiva/fiscal, pero NUNCA es la fuente de verdad
// financiera. Elegir "tarjeta" ahí no identifica cuál tarjeta y, por
// sí solo, no debe generar ningún cargo a ninguna Deuda.
//
// Reemplaza a `registrar_egreso_no_permite_tdc_test.dart`, que protegía
// la regla de producto anterior ("Registrar egreso manual nunca admite
// TDC; los gastos con TDC entran por Compra o Tiempo Extra"). Esa regla
// fue revertida explícitamente por Marlon a partir del caso real de una
// carga de gasolina pagada con la TDC Konfío: no es Compra ni cobertura
// de Tiempo Extra, así que no tenía ningún flujo donde caber. Lo que
// aquel test protegía y sigue siendo cierto —que la etiqueta `formaPago`
// no mueve dinero por su cuenta— es exactamente lo que se conserva aquí.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';

void main() {
  late AppDatabase db;
  late RegistrarEgresoUseCase registrarEgreso;
  late RegistrarDeudaUseCase registrarDeuda;
  late DeudaRepository deudaRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    registrarEgreso = RegistrarEgresoUseCase(egresoRepo, generarCodigo, deudaRepo);
    registrarDeuda = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
  });

  tearDown(() => db.close());

  Future<DeudaData> crearTarjeta({int limite = 4000000, int saldoInicial = 0}) async {
    final resultado = await registrarDeuda.ejecutar(
      nombre: 'TDC Konfío Empresarial',
      tipo: 'tarjetaCredito',
      saldoInicial: saldoInicial,
      tarjetaLimiteCredito: limite,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  test(
    "formaPago == 'tarjeta' sin un origen de TDC real NO genera ningún cargo a Deuda "
    '(la etiqueta describe, nunca financia)',
    () async {
      final tarjeta = await crearTarjeta();

      final resultado = await registrarEgreso.ejecutar(
        monto: 35000,
        fecha: DateTime(2026, 9, 3),
        formaPago: 'tarjeta',
        concepto: 'Gasto con etiqueta tarjeta pero sin origen financiero elegido',
      );

      expect(resultado, isA<RegistrarEgresoExitoso>());
      final egreso = (resultado as RegistrarEgresoExitoso).egreso;
      expect(egreso.estatus, 'registrado');
      expect(egreso.deudaId, isNull, reason: 'ninguna tarjeta quedó vinculada: no se eligió origen');
      expect(egreso.cuentaFinancieraId, isNull);

      final movimientos = await db.select(db.movimientoDeuda).get();
      expect(
        movimientos.where((m) => m.tipo == 'cargoCompra'),
        isEmpty,
        reason: 'cero cargos — `formaPago` no identifica ninguna tarjeta ni mueve saldo por su cuenta',
      );
      final despues = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(despues!.saldoActual, 0, reason: 'la TDC existente quedó exactamente igual');
    },
  );

  test(
    "el origen SÍ financia, sin importar la etiqueta: formaPago == 'efectivo' con origen de TDC "
    'genera el cargo igual (la etiqueta nunca contradice al origen)',
    () async {
      final tarjeta = await crearTarjeta();

      final resultado = await registrarEgreso.ejecutar(
        monto: 135998,
        fecha: DateTime(2026, 9, 3),
        formaPago: 'efectivo',
        concepto: 'gasolina',
        origen: OrigenFinancieroTarjeta(tarjeta.id),
      );

      expect(resultado, isA<RegistrarEgresoExitoso>());
      expect((resultado as RegistrarEgresoExitoso).egreso.deudaId, tarjeta.id);

      final despues = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(despues!.saldoActual, 135998, reason: 'el cargo lo decide el origen estructurado, nunca `formaPago`');
    },
  );
}
