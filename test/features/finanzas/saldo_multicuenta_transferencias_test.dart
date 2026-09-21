// Política de saldo, pagos multicuenta y transferencias (schemaVersion 91).
//
// Nace de un sobregiro real: un pago de Nómina de $9,800 se guardó desde
// una cuenta con $4,698.67 y la dejó en -$5,101.33. Hoy no existía
// NINGUNA validación de saldo en el sistema.
//
// Todo pasa por el embudo real (`EgresoRepositoryImpl`), nunca por un
// mock que se lo salte: probar la política sin el embudo probaría otra
// cosa.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/transferencia_cuenta_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/transferencia_cuenta_table.dart';
import 'package:riseg_one/features/finanzas/domain/fuente_egreso.dart';
import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/transferir_entre_cuentas_usecase.dart';

void main() {
  late AppDatabase db;
  late EgresoRepositoryImpl egresos;
  late CuentaFinancieraRepositoryImpl cuentas;
  late TransferenciaCuentaRepositoryImpl transferencias;
  late TransferirEntreCuentasUseCase transferir;
  late CancelarTransferenciaUseCase cancelarTransferencia;
  late CorregirTransferenciaUseCase corregirTransferencia;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    egresos = EgresoRepositoryImpl(db);
    cuentas = CuentaFinancieraRepositoryImpl(db);
    transferencias = TransferenciaCuentaRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    transferir = TransferirEntreCuentasUseCase(transferencias, generarCodigo);
    cancelarTransferencia = CancelarTransferenciaUseCase(transferencias);
    corregirTransferencia = CorregirTransferenciaUseCase(transferencias);
  });

  tearDown(() => db.close());

  var contador = 0;
  Future<CuentaFinancieraData> crearCuenta(int saldoInicial, {DateTime? corte}) async {
    contador++;
    return db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-${contador.toString().padLeft(4, '0')}',
            nombre: 'Cuenta $contador',
            tipo: 'banco',
            saldoInicial: saldoInicial,
            fechaSaldoInicial: corte ?? DateTime(2026, 1, 1),
          ),
        );
  }

  var folio = 0;
  Future<EgresoData> gastar({
    required int monto,
    String? cuentaId,
    List<FuenteEgreso>? fuentes,
    DateTime? fecha,
  }) {
    folio++;
    return egresos.crear(
      folioEgreso: 'EGR-${folio.toString().padLeft(6, '0')}',
      monto: monto,
      fecha: fecha ?? DateTime(2026, 6, 15),
      cuentaFinancieraId: cuentaId,
      fuentes: fuentes,
      formaPago: 'transferencia',
      concepto: 'Gasto de prueba',
    );
  }

  Future<int> saldo(String cuentaId) async => (await cuentas.calcularSaldos([cuentaId]))[cuentaId]!;

  Future<List<EgresoFuenteData>> fuentesDe(String egresoId) =>
      (db.select(db.egresoFuente)..where((t) => t.egresoId.equals(egresoId))).get();

  // ===============================================================
  group('Política de saldo', () {
    test('1. saldo exacto: la salida se permite y la cuenta queda en \$0.00', () async {
      final cuenta = await crearCuenta(1000000);
      await gastar(monto: 1000000, cuentaId: cuenta.id);
      expect(await saldo(cuenta.id), 0);
    });

    test('2. un centavo de más: se rechaza', () async {
      final cuenta = await crearCuenta(1000000);
      await expectLater(
        gastar(monto: 1000001, cuentaId: cuenta.id),
        throwsA(isA<SaldoInsuficienteException>()),
      );
      expect(await saldo(cuenta.id), 1000000, reason: 'nada se persistió');
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('3. cuenta en \$0: cualquier salida se rechaza', () async {
      final cuenta = await crearCuenta(0);
      await expectLater(gastar(monto: 1, cuentaId: cuenta.id), throwsA(isA<SaldoInsuficienteException>()));
    });

    test('4 y 5. una cuenta ya negativa no puede pagar, pero sí recibir', () async {
      // Se fabrica el negativo saltándose el embudo, como haría un dato
      // histórico anterior a la v91.
      final cuenta = await crearCuenta(100000);
      final egreso = await db.into(db.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: 'EGR-HISTORICO',
              monto: 500000,
              fecha: DateTime(2026, 6, 1),
              formaPago: 'transferencia',
              concepto: 'Sobregiro histórico',
              cuentaFinancieraId: Value(cuenta.id),
            ),
          );
      await db.into(db.egresoFuente).insert(
            EgresoFuenteCompanion.insert(egresoId: egreso.id, cuentaFinancieraId: cuenta.id, importe: 500000),
          );
      expect(await saldo(cuenta.id), -400000, reason: 'la historia se conserva tal cual');

      await expectLater(gastar(monto: 1, cuentaId: cuenta.id), throwsA(isA<SaldoInsuficienteException>()));

      // Entrar sí puede.
      await IngresoRepositoryImpl(db).crear(
        folioIngreso: 'ING-000001',
        monto: 900000,
        fecha: DateTime(2026, 6, 20),
        formaPago: 'transferencia',
        concepto: 'Depósito',
        cuentaFinancieraId: cuenta.id,
      );
      expect(await saldo(cuenta.id), 500000);
    });

    test('38. una salida con fecha anterior al saldo inicial se rechaza', () async {
      final cuenta = await crearCuenta(1000000, corte: DateTime(2026, 6, 1));
      await expectLater(
        gastar(monto: 1000, cuentaId: cuenta.id, fecha: DateTime(2026, 5, 31)),
        throwsA(
          isA<SaldoInsuficienteException>().having(
            (e) => e.veredicto,
            'veredicto',
            isA<FechaAnteriorAlSaldoInicial>(),
          ),
        ),
      );
      // El mismo día del corte sí pasa.
      await gastar(monto: 1000, cuentaId: cuenta.id, fecha: DateTime(2026, 6, 1));
      expect(await saldo(cuenta.id), 999000);
    });
  });

  // ===============================================================
  group('Fuentes de un Egreso', () {
    test('35. un Egreso de una sola cuenta crea exactamente una fuente', () async {
      final cuenta = await crearCuenta(1000000);
      final egreso = await gastar(monto: 250000, cuentaId: cuenta.id);
      final fuentes = await fuentesDe(egreso.id);
      expect(fuentes, hasLength(1));
      expect(fuentes.single.cuentaFinancieraId, cuenta.id);
      expect(fuentes.single.importe, 250000);
    });

    test('6 y 36. multicuenta: un solo Egreso y N fuentes que suman exacto', () async {
      final a = await crearCuenta(469867);
      final b = await crearCuenta(6382777);
      final egreso = await gastar(
        monto: 980000,
        fuentes: [
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 469867),
          FuenteEgreso(cuentaFinancieraId: b.id, importe: 510133),
        ],
      );

      expect(await db.select(db.egreso).get(), hasLength(1));
      expect(await fuentesDe(egreso.id), hasLength(2));
      expect(await saldo(a.id), 0, reason: 'con centavos exactos queda en cero, no falla');
      expect(await saldo(b.id), 6382777 - 510133);
    });

    test('7. la suma menor al total se rechaza', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000000);
      await expectLater(
        gastar(monto: 980000, fuentes: [
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 400000),
          FuenteEgreso(cuentaFinancieraId: b.id, importe: 500000),
        ]),
        throwsA(isA<DistribucionInvalidaException>()),
      );
      expect(await db.select(db.egreso).get(), isEmpty);
    });

    test('8. la suma mayor al total se rechaza', () async {
      final a = await crearCuenta(1000000);
      await expectLater(
        gastar(monto: 100000, fuentes: [FuenteEgreso(cuentaFinancieraId: a.id, importe: 100001)]),
        throwsA(isA<DistribucionInvalidaException>()),
      );
    });

    test('9. la misma cuenta repetida se rechaza', () async {
      final a = await crearCuenta(1000000);
      await expectLater(
        gastar(monto: 200000, fuentes: [
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
        ]),
        throwsA(isA<DistribucionInvalidaException>()),
      );
    });

    test('17. un importe de fuente en cero o negativo se rechaza', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000000);
      await expectLater(
        gastar(monto: 100000, fuentes: [
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
          FuenteEgreso(cuentaFinancieraId: b.id, importe: 0),
        ]),
        throwsA(isA<DistribucionInvalidaException>()),
      );
    });

    test('10 y 11. si UNA cuenta no alcanza, no se persiste NADA', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000);
      await expectLater(
        gastar(monto: 1100000, fuentes: [
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 1000000),
          FuenteEgreso(cuentaFinancieraId: b.id, importe: 100000),
        ]),
        throwsA(isA<SaldoInsuficienteException>()),
      );
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'rollback completo');
      expect(await db.select(db.egresoFuente).get(), isEmpty, reason: 'ni la primera fuente sobrevive');
      expect(await saldo(a.id), 1000000);
      expect(await saldo(b.id), 1000);
    });

    test('12 y 37. cancelar deja de afectar el saldo sin crear Ingresos', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000000);
      final egreso = await gastar(monto: 300000, fuentes: [
        FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
        FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
      ]);
      expect(await saldo(a.id), 900000);
      expect(await saldo(b.id), 800000);

      await egresos.cancelar(egresoId: egreso.id, motivo: 'Error de captura');

      expect(await saldo(a.id), 1000000, reason: 'A recupera exactamente lo suyo');
      expect(await saldo(b.id), 1000000, reason: 'B recupera exactamente lo suyo');
      expect(await db.select(db.ingreso).get(), isEmpty, reason: 'jamás un Ingreso compensatorio');
      expect(await fuentesDe(egreso.id), hasLength(2), reason: 'las fuentes se conservan como historia');
    });
  });

  // ===============================================================
  group('Correcciones: nunca se cuentan a sí mismas', () {
    test('13 y 45. misma cuenta, MENOR importe', () async {
      final a = await crearCuenta(1000000);
      final egreso = await gastar(monto: 1000000, cuentaId: a.id);
      expect(await saldo(a.id), 0, reason: 'la cuenta quedó sin margen');

      // Sin auto-exclusión esto fallaría: el saldo es 0 y la nueva
      // fuente pide $3,000.
      await egresos.corregirMonto(egresoId: egreso.id, nuevoMonto: 300000, motivo: 'Importe mal capturado');

      expect(await saldo(a.id), 700000);
      expect((await fuentesDe(egreso.id)).single.importe, 300000);
    });

    test('13b. misma cuenta, MAYOR importe dentro de lo disponible', () async {
      final a = await crearCuenta(1000000);
      final egreso = await gastar(monto: 300000, cuentaId: a.id);
      await egresos.corregirMonto(egresoId: egreso.id, nuevoMonto: 1000000, motivo: 'Faltaba');
      expect(await saldo(a.id), 0);
    });

    test('13c. misma cuenta, mayor importe del que hay: se rechaza y no se toca nada', () async {
      final a = await crearCuenta(1000000);
      final egreso = await gastar(monto: 300000, cuentaId: a.id);
      await expectLater(
        egresos.corregirMonto(egresoId: egreso.id, nuevoMonto: 1000001, motivo: 'Faltaba'),
        throwsA(isA<SaldoInsuficienteException>()),
      );
      expect(await saldo(a.id), 700000);
      expect((await fuentesDe(egreso.id)).single.importe, 300000);
    });

    test('A → B', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000000);
      final egreso = await gastar(monto: 400000, cuentaId: a.id);

      await egresos.corregir(
        egresoId: egreso.id,
        fuentes: [FuenteEgreso(cuentaFinancieraId: b.id, importe: 400000)],
        cuentaFinancieraId: b.id,
        motivo: 'Salió de B',
      );

      expect(await saldo(a.id), 1000000);
      expect(await saldo(b.id), 600000);
      expect((await fuentesDe(egreso.id)).single.cuentaFinancieraId, b.id);
    });

    test('A+B → A, y A → A+B, conservando el importe total', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000000);
      final egreso = await gastar(monto: 500000, fuentes: [
        FuenteEgreso(cuentaFinancieraId: a.id, importe: 200000),
        FuenteEgreso(cuentaFinancieraId: b.id, importe: 300000),
      ]);

      // A+B → A
      await egresos.corregir(
        egresoId: egreso.id,
        fuentes: [FuenteEgreso(cuentaFinancieraId: a.id, importe: 500000)],
        motivo: 'Todo salió de A',
      );
      expect(await saldo(a.id), 500000);
      expect(await saldo(b.id), 1000000);
      expect((await egresos.obtenerPorId(egreso.id))!.monto, 500000, reason: 'el importe total no cambia');

      // A → A+B
      await egresos.corregir(
        egresoId: egreso.id,
        fuentes: [
          FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
          FuenteEgreso(cuentaFinancieraId: b.id, importe: 400000),
        ],
        motivo: 'Se repartió',
      );
      expect(await saldo(a.id), 900000);
      expect(await saldo(b.id), 600000);
      expect(await fuentesDe(egreso.id), hasLength(2));
    });

    test('una corrección que falla no deja el Egreso a medias', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000);
      final egreso = await gastar(monto: 400000, cuentaId: a.id);

      await expectLater(
        egresos.corregir(
          egresoId: egreso.id,
          fuentes: [
            FuenteEgreso(cuentaFinancieraId: a.id, importe: 300000),
            FuenteEgreso(cuentaFinancieraId: b.id, importe: 100000),
          ],
          motivo: 'Reparto imposible',
        ),
        throwsA(isA<SaldoInsuficienteException>()),
      );

      expect(await saldo(a.id), 600000, reason: 'el Egreso original sigue intacto en A');
      expect(await saldo(b.id), 1000);
      expect((await fuentesDe(egreso.id)).single.importe, 400000);
    });
  });

  // ===============================================================
  group('Transferencias entre cuentas propias', () {
    test('14, 23 y 24. A→B mueve ambas y deja Caja y bancos igual', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(500000);
      final posicion = ObtenerPosicionDeCajaUseCase(cuentas);
      final totalAntes = (await posicion.ejecutar()).saldoDisponible;

      final resultado = await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 500000,
        fecha: DateTime(2026, 6, 15),
        concepto: 'Traspaso',
      );

      expect(resultado, isA<TransferirEntreCuentasExitoso>());
      expect(await saldo(a.id), 500000);
      expect(await saldo(b.id), 1000000);
      expect((await posicion.ejecutar()).saldoDisponible, totalAntes,
          reason: 'el dinero cambió de cuenta, no entró ni salió');
    });

    test('21 y 22. no crea Ingreso ni Egreso', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 300000,
        fecha: DateTime(2026, 6, 15),
      );
      expect(await db.select(db.ingreso).get(), isEmpty);
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.egresoFuente).get(), isEmpty);
    });

    test('15. sin saldo: se rechaza con los tres números', () async {
      final a = await crearCuenta(400000);
      final b = await crearCuenta(0);
      final resultado = await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 500000,
        fecha: DateTime(2026, 6, 15),
      );

      expect(resultado, isA<TransferirEntreCuentasSaldoInsuficiente>());
      final detalle = (resultado as TransferirEntreCuentasSaldoInsuficiente).detalle;
      expect(detalle.disponible, 400000);
      expect(detalle.requerido, 500000);
      expect(detalle.faltante, 100000);
      expect(await db.select(db.transferenciaCuenta).get(), isEmpty);
    });

    test('16. origen igual a destino: se rechaza', () async {
      final a = await crearCuenta(1000000);
      expect(
        await transferir.ejecutar(
          cuentaOrigenId: a.id,
          cuentaDestinoId: a.id,
          importe: 100000,
          fecha: DateTime(2026, 6, 15),
        ),
        isA<TransferirEntreCuentasMismaCuenta>(),
      );
    });

    test('17b. importe cero o negativo: se rechaza', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      for (final importe in [0, -1]) {
        expect(
          await transferir.ejecutar(
            cuentaOrigenId: a.id,
            cuentaDestinoId: b.id,
            importe: importe,
            fecha: DateTime(2026, 6, 15),
          ),
          isA<TransferirEntreCuentasImporteInvalido>(),
        );
      }
    });

    test('39 y 40. fecha anterior al corte de origen o de destino: se rechaza', () async {
      final a = await crearCuenta(1000000, corte: DateTime(2026, 6, 1));
      final b = await crearCuenta(0, corte: DateTime(2026, 7, 1));

      expect(
        await transferir.ejecutar(
          cuentaOrigenId: a.id,
          cuentaDestinoId: b.id,
          importe: 100000,
          fecha: DateTime(2026, 5, 20),
        ),
        isA<TransferirEntreCuentasFechaAnteriorAlSaldoInicial>(),
        reason: 'anterior al corte del ORIGEN',
      );

      expect(
        await transferir.ejecutar(
          cuentaOrigenId: a.id,
          cuentaDestinoId: b.id,
          importe: 100000,
          fecha: DateTime(2026, 6, 15),
        ),
        isA<TransferirEntreCuentasFechaAnteriorAlSaldoInicial>(),
        reason: 'anterior al corte del DESTINO',
      );

      expect(await db.select(db.transferenciaCuenta).get(), isEmpty);
    });

    test('19. cancelar restaura ambas cuentas', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      final creada = (await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 400000,
        fecha: DateTime(2026, 6, 15),
      ) as TransferirEntreCuentasExitoso)
          .transferencia;
      expect(await saldo(a.id), 600000);
      expect(await saldo(b.id), 400000);

      await cancelarTransferencia.ejecutar(transferenciaId: creada.id, motivo: 'Duplicada');

      expect(await saldo(a.id), 1000000);
      expect(await saldo(b.id), 0);
      expect(await db.select(db.transferenciaCuenta).get(), hasLength(1), reason: 'se conserva como historia');
      expect(await db.select(db.ingreso).get(), isEmpty);
    });

    test('corregir el importe no se cuenta a sí misma', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      final creada = (await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 1000000,
        fecha: DateTime(2026, 6, 15),
      ) as TransferirEntreCuentasExitoso)
          .transferencia;
      expect(await saldo(a.id), 0);

      // Subirla sería imposible; bajarla debe poder.
      expect(
        await corregirTransferencia.ejecutar(
          transferenciaId: creada.id,
          importe: 400000,
          motivo: 'Importe mal capturado',
        ),
        isA<TransferirEntreCuentasExitoso>(),
      );
      expect(await saldo(a.id), 600000);
      expect(await saldo(b.id), 400000);

      final eventos = await transferencias.listarEventos(creada.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['creada', 'corregida']));
    });

    test('una transferencia cancelada ya no se corrige', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      final creada = (await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 100000,
        fecha: DateTime(2026, 6, 15),
      ) as TransferirEntreCuentasExitoso)
          .transferencia;
      await cancelarTransferencia.ejecutar(transferenciaId: creada.id, motivo: 'Duplicada');

      expect(
        await corregirTransferencia.ejecutar(transferenciaId: creada.id, importe: 50000, motivo: 'x'),
        isA<TransferirEntreCuentasErrorInesperado>(),
      );
    });

    test('20. transferir no toca ingresos ni egresos, así que el resultado operativo no cambia', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      await IngresoRepositoryImpl(db).crear(
        folioIngreso: 'ING-000001',
        monto: 500000,
        fecha: DateTime(2026, 6, 1),
        formaPago: 'transferencia',
        concepto: 'Venta',
        cuentaFinancieraId: a.id,
      );
      await gastar(monto: 200000, cuentaId: a.id, fecha: DateTime(2026, 6, 2));

      Future<(int, int)> resultadoOperativo() async {
        final ing = (await db.select(db.ingreso).get())
            .where((i) => i.estatus == 'registrado')
            .fold<int>(0, (s, i) => s + i.monto);
        final egr = (await db.select(db.egreso).get())
            .where((e) => e.estatus == 'registrado')
            .fold<int>(0, (s, e) => s + e.monto);
        return (ing, egr);
      }

      final antes = await resultadoOperativo();
      await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 900000,
        fecha: DateTime(2026, 6, 15),
      );
      expect(await resultadoOperativo(), antes);
    });

    test('la cancelación libera saldo para una salida posterior', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      final creada = (await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 1000000,
        fecha: DateTime(2026, 6, 15),
      ) as TransferirEntreCuentasExitoso)
          .transferencia;

      await expectLater(gastar(monto: 1, cuentaId: a.id), throwsA(isA<SaldoInsuficienteException>()));
      await cancelarTransferencia.ejecutar(transferenciaId: creada.id, motivo: 'Revertida');
      await gastar(monto: 1000000, cuentaId: a.id);
      expect(await saldo(a.id), 0);
    });

    test('una transferencia recibida permite pagar desde el destino', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      await expectLater(gastar(monto: 100000, cuentaId: b.id), throwsA(isA<SaldoInsuficienteException>()));

      await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 100000,
        fecha: DateTime(2026, 6, 15),
      );
      await gastar(monto: 100000, cuentaId: b.id);
      expect(await saldo(b.id), 0);
    });

    test('el estatus de la transferencia arranca en registrada', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(0);
      final creada = (await transferir.ejecutar(
        cuentaOrigenId: a.id,
        cuentaDestinoId: b.id,
        importe: 1000,
        fecha: DateTime(2026, 6, 15),
      ) as TransferirEntreCuentasExitoso)
          .transferencia;
      expect(creada.estatus, EstatusTransferenciaCuenta.registrada.name);
      expect(creada.folioTransferencia, startsWith('TRF-'));
    });
  });

  // ===============================================================
  group('No doble conteo y rendimiento', () {
    test('34. un Egreso con columna legacy Y fuente cuenta UNA sola vez', () async {
      final cuenta = await crearCuenta(1000000);
      final egreso = await gastar(monto: 400000, cuentaId: cuenta.id);

      // La columna legacy quedó escrita...
      expect(egreso.cuentaFinancieraId, cuenta.id);
      // ...y la fuente también. El saldo baja 400,000, no 800,000.
      expect((await fuentesDe(egreso.id)).single.importe, 400000);
      expect(await saldo(cuenta.id), 600000);
    });

    test('con varias fuentes la columna legacy queda null: ninguna cuenta sola representa el Egreso', () async {
      final a = await crearCuenta(1000000);
      final b = await crearCuenta(1000000);
      final egreso = await gastar(monto: 300000, fuentes: [
        FuenteEgreso(cuentaFinancieraId: a.id, importe: 100000),
        FuenteEgreso(cuentaFinancieraId: b.id, importe: 200000),
      ]);
      final leido = await egresos.obtenerPorId(egreso.id);
      expect(leido!.cuentaFinancieraId, isNull);
    });

    test('31. calcularSaldos sigue siendo de consultas fijas con muchas cuentas', () async {
      final ids = <String>[];
      for (var i = 0; i < 25; i++) {
        final c = await crearCuenta(100000);
        ids.add(c.id);
        await gastar(monto: 1000, cuentaId: c.id);
      }
      final saldos = await cuentas.calcularSaldos(ids);
      expect(saldos, hasLength(25));
      expect(saldos.values.every((s) => s == 99000), isTrue);
      // 4 consultas: cuentas + ingresos + fuentes(join) + transferencias.
      // Ver `calcularSaldosCanonico`.
    });
  });

  // ===============================================================
  // Los dos orígenes que viven en Finanzas: el gasto manual y la
  // corrección Maestro del origen financiero de un Egreso.
  // ===============================================================
  group('Política de saldo (v91) — Egreso manual', () {
    late RegistrarEgresoUseCase registrarEgreso;

    setUp(() {
      registrarEgreso = RegistrarEgresoUseCase(
        egresos,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        DeudaRepositoryImpl(db, egresos),
      );
    });

    test('A) con saldo suficiente: el gasto se registra', () async {
      final cuenta = await crearCuenta(500000);
      final resultado = await registrarEgreso.ejecutar(
        monto: 500000,
        fecha: DateTime(2026, 6, 15),
        concepto: 'Gasto manual',
        formaPago: 'transferencia',
        origen: OrigenFinancieroCuenta(cuenta.id),
      );
      expect(resultado, isA<RegistrarEgresoExitoso>());
      expect(await saldo(cuenta.id), 0);
    });

    test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
      final cuenta = await crearCuenta(499999);
      await expectLater(
        registrarEgreso.ejecutar(
          monto: 500000,
          fecha: DateTime(2026, 6, 15),
          concepto: 'Gasto manual',
          formaPago: 'transferencia',
          origen: OrigenFinancieroCuenta(cuenta.id),
        ),
        throwsA(isA<SaldoInsuficienteException>()),
      );

      expect(await db.select(db.egreso).get(), isEmpty, reason: 'ni el Egreso');
      expect(await db.select(db.egresoFuente).get(), isEmpty, reason: 'ni su fuente');
      expect(await db.select(db.movimientoDeuda).get(), isEmpty, reason: 'ni un movimiento de deuda');
      expect(await saldo(cuenta.id), 499999);
    });
  });

}
