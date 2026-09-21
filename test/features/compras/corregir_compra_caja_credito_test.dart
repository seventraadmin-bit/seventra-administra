// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC),
// Secciones 8/9/10: escenario integral contra BD real. Prueba
// explícitamente el ejemplo textual del usuario (BBVA $20,000/Klar
// $10,000/Konfío disp. $8,000/Clara disp. $12,000 → Compra $1,500 en
// BBVA → corrige BBVA→Clara→Konfío→Klar) confirmando en cada paso que
// el gasto operativo reconocido (`ObtenerResumenFinancieroUseCase`)
// NUNCA cambia solo por mover el origen financiero — ni se duplica
// («nunca $3,000») ni desaparece («nunca $0») — y que Caja y bancos /
// Crédito disponible reflejan exactamente el origen vigente en cada
// paso. Cierra con la cancelación después de múltiples correcciones
// (Sección 10): debe revertir el efecto VIGENTE, dejando neto cero.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_resumen_financiero_usecase.dart';
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
  late CancelarCompraUseCase cancelarCompra;
  late ObtenerResumenFinancieroUseCase resumenFinanciero;
  late ObtenerPosicionDeCajaUseCase posicionDeCaja;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final articuloRepo = ArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final ingresoRepo = IngresoRepositoryImpl(db);
    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    corregirCompra = CorregirCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
    resumenFinanciero = ObtenerResumenFinancieroUseCase(ingresoRepo, egresoRepo, compraRepo);
    posicionDeCaja = ObtenerPosicionDeCajaUseCase(cuentaFinancieraRepo);

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

  Future<CuentaFinancieraData> crearCuenta(String nombre, int saldoInicial) {
    return cuentaFinancieraRepo.crear(
      codigo: 'CTA-$nombre',
      nombre: nombre,
      tipo: TipoCuentaFinanciera.banco.name,
      saldoInicial: saldoInicial,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    );
  }

  Future<DeudaData> crearTarjeta(String nombre, {required int limiteCredito, required int saldoInicial}) async {
    final resultado = await RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
      nombre: nombre,
      tipo: TipoDeuda.tarjetaCredito.name,
      saldoInicial: saldoInicial,
      fechaSaldoInicial: saldoInicial == 0 ? null : DateTime(2026, 1, 1),
      tarjetaLimiteCredito: limiteCredito,
    );
    return (resultado as RegistrarDeudaExitoso).deuda;
  }

  test(
    'Escenario integral (Secciones 8/9): BBVA \$20,000/Klar \$10,000/Konfío disp. \$8,000/Clara disp. \$12,000 -> '
    'Compra \$1,500 en BBVA -> corrige BBVA->Clara->Konfío->Klar — el gasto operativo NUNCA cambia (nunca \$3,000, '
    'nunca \$0), Caja y Crédito disponible reflejan exactamente el origen vigente en cada paso',
    () async {
      final bbva = await crearCuenta('BBVA', 2000000);
      // Klar: sin límite de crédito capturado en el escenario del
      // usuario (no aporta "disponible") — se modela con saldo 0 y sin
      // límite, se usa solo al final como Cuenta financiera con $10,000.
      final klarCuenta = await crearCuenta('Klar', 1000000);
      final konfio = await crearTarjeta('Konfío', limiteCredito: 999999999, saldoInicial: 999999999 - 800000);
      final clara = await crearTarjeta('Clara', limiteCredito: 999999999, saldoInicial: 999999999 - 1200000);

      // `totalEgresos` es deliberadamente el total CRUDO de `Egreso`
      // reales (Etapa 3: ver el doc comment de `ResumenFinanciero`) —
      // el gasto operativo reconocido total (lo que "nunca debe
      // cambiar" en este escenario) es `totalEgresos + totalComprasPorTdc`.
      Future<void> esperarGastoOperativo(int esperado, String etapa) async {
        final resumen = await resumenFinanciero.ejecutar();
        expect(
          resumen.totalEgresos + resumen.totalComprasPorTdc,
          esperado,
          reason: '$etapa: el gasto operativo reconocido debe ser exactamente $esperado',
        );
      }

      // Estado inicial: gasto operativo cero, nadie ha comprado nada.
      await esperarGastoOperativo(0, 'antes de comprar');

      final creada = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
        partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 150000)],
      ) as RegistrarCompraExitosa)
          .compra;

      await esperarGastoOperativo(150000, 'Compra \$1,500 en BBVA');
      var caja = await posicionDeCaja.ejecutar();
      expect(caja.saldosPorCuenta[bbva.id], 1850000, reason: 'BBVA baja a \$18,500');

      // BBVA -> Clara
      final c1 = (await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: clara.id, motivo: 'Se pagó realmente con Clara') as CorregirCompraExitosa)
          .compra;
      expect(c1.deudaId, clara.id);
      await esperarGastoOperativo(150000, 'BBVA -> Clara');
      caja = await posicionDeCaja.ejecutar();
      expect(caja.saldosPorCuenta[bbva.id], 2000000, reason: 'BBVA regresa a \$20,000 — nunca queda descontado dos veces');
      var claraTras = await deudaRepo.obtenerPorId(clara.id);
      expect(claraTras!.saldoActual, 999999999 - 1200000 + 150000, reason: 'disponible de Clara baja exactamente \$1,500 (de \$12,000 a \$10,500)');

      // Clara -> Konfío
      final c2 =
          (await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: konfio.id, motivo: 'Se pagó realmente con Konfío') as CorregirCompraExitosa)
              .compra;
      expect(c2.deudaId, konfio.id);
      await esperarGastoOperativo(150000, 'Clara -> Konfío');
      claraTras = await deudaRepo.obtenerPorId(clara.id);
      expect(claraTras!.saldoActual, 999999999 - 1200000, reason: 'Clara regresa a disponible \$12,000');
      final konfioTras1 = await deudaRepo.obtenerPorId(konfio.id);
      expect(konfioTras1!.saldoActual, 999999999 - 800000 + 150000, reason: 'disponible de Konfío baja de \$8,000 a \$6,500');

      // Konfío -> Klar (Cuenta financiera)
      final c3 = (await corregirCompra.ejecutar(compraId: creada.id, nuevaCuentaFinancieraId: klarCuenta.id, motivo: 'Se pagó realmente de contado (Klar)')
              as CorregirCompraExitosa)
          .compra;
      expect(c3.deudaId, isNull);
      expect(c3.egresoId, isNotNull);
      await esperarGastoOperativo(150000, 'Konfío -> Klar (nunca \$3,000, nunca \$0)');
      final konfioTras2 = await deudaRepo.obtenerPorId(konfio.id);
      expect(konfioTras2!.saldoActual, 999999999 - 800000, reason: 'Konfío regresa a disponible \$8,000');
      caja = await posicionDeCaja.ejecutar();
      expect(caja.saldosPorCuenta[klarCuenta.id], 1000000 - 150000, reason: 'Klar baja de \$10,000 a \$8,500');
      expect(caja.saldosPorCuenta[bbva.id], 2000000, reason: 'BBVA sigue en \$20,000 — el gasto ya no le pertenece');
    },
  );

  test(
    'Sección 10: cancelación después de múltiples correcciones Cuenta<->TDC revierte el efecto VIGENTE '
    '(no el inicial), dejando neto cero, sin tocar movimientos ajenos',
    () async {
      final bbva = await crearCuenta('BBVA', 2000000);
      final konfio = await crearTarjeta('Konfío', limiteCredito: 5000000, saldoInicial: 0);
      final clara = await crearTarjeta('Clara', limiteCredito: 5000000, saldoInicial: 0);

      final creada = (await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: bbva.id,
        partidas: [const PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Papelería', cantidad: 1, costoUnitario: 150000)],
      ) as RegistrarCompraExitosa)
          .compra;

      // BBVA -> Konfío -> ajuste al alza (mismo Konfío) -> Clara.
      await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: konfio.id, motivo: 'Se pagó con Konfío');
      await corregirCompra.ejecutar(
        compraId: creada.id,
        cambiosPartidas: [
          CorreccionPartidaCantidadCosto(compraPartidaId: (await compraRepo.listarPartidas(creada.id)).single.id, nuevoCostoUnitario: 200000),
        ],
        nuevaDeudaId: konfio.id,
        motivo: 'Se ajustó el monto real',
      );
      final antesDeMoverACl = await corregirCompra.ejecutar(compraId: creada.id, nuevaDeudaId: clara.id, motivo: 'Se pagó realmente con Clara');
      final vigente = (antesDeMoverACl as CorregirCompraExitosa).compra;
      expect(vigente.deudaId, clara.id);
      final claraAntes = await deudaRepo.obtenerPorId(clara.id);
      expect(claraAntes!.saldoActual, 200000);
      final konfioAntes = await deudaRepo.obtenerPorId(konfio.id);
      expect(konfioAntes!.saldoActual, 0, reason: 'Konfío ya quedó en neto cero desde la corrección Konfío->Clara');

      final resultadoCancelar = await cancelarCompra.ejecutar(
        compraId: creada.id,
        motivo: MotivoCancelacionCompra.errorDeCaptura,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(resultadoCancelar, isA<CancelarCompraExitosa>());

      final bbvaTras = await deudaRepo.obtenerPorId(konfio.id); // no-op read to keep symmetry with cuenta below
      expect(bbvaTras, isNotNull);
      final claraTras = await deudaRepo.obtenerPorId(clara.id);
      expect(claraTras!.saldoActual, 0, reason: 'la cancelación revierte el efecto VIGENTE (Clara), dejando neto cero');
      final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
      expect(konfioTras!.saldoActual, 0, reason: 'Konfío no se toca de nuevo — ya estaba en cero, la cancelación no debe tocar movimientos ajenos');
      final caja = await posicionDeCaja.ejecutar();
      expect(caja.saldosPorCuenta[bbva.id], 2000000, reason: 'BBVA nunca se tocó desde que la Compra se movió a tarjeta');
      final resumen = await resumenFinanciero.ejecutar();
      expect(
        resumen.totalEgresos + resumen.totalComprasPorTdc,
        0,
        reason: 'una Compra cancelada no aporta gasto operativo, sin importar cuántas veces cambió de origen antes',
      );
    },
  );
}
