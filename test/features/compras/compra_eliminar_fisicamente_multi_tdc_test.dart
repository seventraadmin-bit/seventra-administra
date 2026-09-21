// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC),
// Sección 11: antes de esta etapa, `eliminarFisicamente`/
// `eliminarCargoCompraFisicamente` asumían "una Compra financiada por
// tarjeta solo pudo tocar UNA tarjeta en toda su historia" — una
// suposición real hasta que esta etapa permitió transiciones D/E/F.
// Con historial multi-tarjeta (D: TDC→TDC) el saldo restaurado en la
// eliminación solo se aplicaba a la PRIMERA tarjeta, corrompiendo el
// saldo de la segunda; con historial "huérfano" (F: TDC→Cuenta, donde
// `Compra.deudaId` ya es `null` pero quedan `MovimientoDeuda` viejos)
// la limpieza se saltaba por completo y el `DELETE FROM compra`
// fallaba contra la FK `restrict` de `MovimientoDeuda.compraId`. Este
// archivo prueba, contra BD real, que ambos casos ahora se resuelven
// correctamente — nunca relajando la FK, nunca con CASCADE.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/eliminar_compra_fisicamente_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late DeudaRepositoryImpl deudaRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CorregirCompraUseCase corregirCompra;
  late EliminarCompraFisicamenteUseCase eliminarCompra;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo);
    eliminarCompra = EliminarCompraFisicamenteUseCase(compraRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<DeudaData> crearTarjeta(String nombre) async {
    final resultado = await RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
      nombre: nombre,
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: 0,
      tarjetaLimiteCredito: 5000000,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  Future<CuentaFinancieraData> crearCuenta() {
    return cuentaFinancieraRepo.crear(
      codigo: 'CTA-000001',
      nombre: 'BBVA',
      tipo: TipoCuentaFinanciera.banco.name,
      saldoInicial: 5000000,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
  }

  test(
    'Compra con historial en DOS tarjetas (transición D, TDC X -> TDC Y): eliminar físicamente restaura '
    'el saldo de AMBAS tarjetas — no solo la primera',
    () async {
      final tarjetaX = await crearTarjeta('Konfío');
      final tarjetaY = await crearTarjeta('Clara');
      final creada = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjetaX.id,
        partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 300000)],
      ) as RegistrarCompraExitosa)
          .compra;

      final corregida = (await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: tarjetaY.id, motivo: 'Se pagó realmente con Clara')
              as CorregirCompraExitosa)
          .compra;
      expect(corregida.deudaId, tarjetaY.id);

      final r = await eliminarCompra.ejecutar(
        compraId: creada.id,
        motivo: MotivoEliminacionFisicaCompra.registroDePrueba,
        actorUsuarioId: 'usuario-maestro',
      );

      expect(r, isA<EliminarCompraFisicamenteExitoso>());
      expect(await compraRepo.obtenerPorId(creada.id), isNull);
      final tarjetaXTras = await deudaRepo.obtenerPorId(tarjetaX.id);
      final tarjetaYTras = await deudaRepo.obtenerPorId(tarjetaY.id);
      expect(tarjetaXTras!.saldoActual, 0, reason: 'la primera tarjeta que tocó la Compra también se restaura');
      expect(tarjetaYTras!.saldoActual, 0, reason: 'la segunda tarjeta también se restaura — el bug real solo corregía la primera');
      final movimientosRestantes = await (db.select(db.movimientoDeuda)..where((t) => t.compraId.equals(creada.id))).get();
      expect(movimientosRestantes, isEmpty, reason: 'ningún MovimientoDeuda huérfano queda apuntando a la Compra ya borrada');
    },
  );

  test(
    'Compra corregida de TDC a Cuenta (transición F): eliminar físicamente limpia el cargo huérfano de la '
    'tarjeta original sin fallar por la FK restrict de MovimientoDeuda.compraId',
    () async {
      final tarjeta = await crearTarjeta('Konfío');
      final cuenta = await crearCuenta();
      final creada = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjeta.id,
        partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 220000)],
      ) as RegistrarCompraExitosa)
          .compra;

      final corregida = (await corregirCompra.ejecutar(compraId: creada.id, nuevaCuentaFinancieraId: cuenta.id, motivo: 'En realidad se pagó de contado')
              as CorregirCompraExitosa)
          .compra;
      expect(corregida.deudaId, isNull, reason: 'el origen VIGENTE ya es Cuenta — sin esto el guard viejo se saltaba la limpieza por completo');
      final movimientosOrfanosAntes = await (db.select(db.movimientoDeuda)..where((t) => t.compraId.equals(creada.id))).get();
      expect(movimientosOrfanosAntes, isNotEmpty, reason: 'el cargo original en la tarjeta sigue existiendo — es la evidencia que el guard viejo ignoraba');

      final r = await eliminarCompra.ejecutar(
        compraId: creada.id,
        motivo: MotivoEliminacionFisicaCompra.registroDePrueba,
        actorUsuarioId: 'usuario-maestro',
      );

      expect(r, isA<EliminarCompraFisicamenteExitoso>(), reason: 'nunca debe fallar con un error crudo de FK');
      expect(await compraRepo.obtenerPorId(creada.id), isNull);
      final tarjetaTras = await deudaRepo.obtenerPorId(tarjeta.id);
      expect(tarjetaTras!.saldoActual, 0, reason: 'el cargo huérfano también se revierte, aunque la Compra ya no apunte a esta tarjeta');
      final movimientosRestantes = await (db.select(db.movimientoDeuda)..where((t) => t.compraId.equals(creada.id))).get();
      expect(movimientosRestantes, isEmpty);
    },
  );

  test(
    'Bloqueo multi-tarjeta: si CUALQUIERA de las tarjetas tocadas por la historia de la Compra tiene un '
    'movimiento posterior ajeno, la eliminación física completa se bloquea',
    () async {
      final tarjetaX = await crearTarjeta('Konfío');
      final tarjetaY = await crearTarjeta('Clara');
      final creada = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjetaX.id,
        partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 300000)],
      ) as RegistrarCompraExitosa)
          .compra;
      await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: tarjetaY.id, motivo: 'Se pagó realmente con Clara');

      // Un cargo AJENO posterior en la tarjeta que ya se abandonó
      // (tarjetaX), de una Compra totalmente distinta — el movimiento
      // propio de la Compra bajo prueba ya no es el más reciente de
      // esa tarjeta, así que debe bloquear.
      await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 20),
        formaPago: FormaPago.tarjeta.name,
        deudaId: tarjetaX.id,
        partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Otra compra', cantidad: 1, costoUnitario: 10000)],
      );

      final resumen = await compraRepo.obtenerResumenEliminacionFisica(creada.id);
      expect(resumen.detalleBloqueo, isNotNull, reason: 'la tarjeta abandonada (X) también debe considerarse, no solo la vigente (Y)');

      final r = await eliminarCompra.ejecutar(
        compraId: creada.id,
        motivo: MotivoEliminacionFisicaCompra.registroDePrueba,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(r, isA<EliminarCompraFisicamenteTieneDependencias>());
      expect(await compraRepo.obtenerPorId(creada.id), isNotNull, reason: 'nada se toca cuando el bloqueo aplica');
    },
  );
}
