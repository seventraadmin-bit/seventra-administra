// `ContraparteCobro` — el punto único donde se decide de quién es una
// Cuenta por cobrar o un Pago (schemaVersion 87).
//
// Desde que la contraparte puede ser un Cliente o un Servicio Eventual,
// comparar sólo el id sería un error silencioso: un Cliente y un
// eventual con el mismo id serían "el mismo". Por eso la igualdad es
// por tipo + id, y por eso `AplicarPagoACuentaUseCase` compara
// contrapartes, no `clienteId`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

void main() {
  test('la igualdad es por tipo + id, nunca sólo por id', () {
    const cliente = ContraparteCobro.cliente('mismo-id');
    const eventual = ContraparteCobro.servicioEventual('mismo-id');

    expect(cliente, isNot(eventual));
    expect(cliente.hashCode, isNot(eventual.hashCode));
    expect(cliente, const ContraparteCobro.cliente('mismo-id'));
    expect(cliente, isNot(const ContraparteCobro.cliente('otro-id')));
  });

  test('contraparteDe: el Cliente gana cuando vienen los dos', () {
    // El esquema no permite ambos, pero la función tiene que ser total
    // y determinista aunque alguien la llame con datos inconsistentes.
    final ambos = contraparteDe(clienteId: 'cli-1', servicioEventualId: 'evt-1');
    expect(ambos, const ContraparteCobro.cliente('cli-1'));

    expect(contraparteDe(servicioEventualId: 'evt-1'), const ContraparteCobro.servicioEventual('evt-1'));
    expect(contraparteDe(), isNull);
  });

  test('nombreContraparte resuelve cada tipo contra su propio mapa', () {
    const nombresCliente = {'cli-1': 'Corporativo Sur'};
    const nombresEventual = {'evt-1': 'Concierto plaza'};

    expect(
      nombreContraparte(
        const ContraparteCobro.cliente('cli-1'),
        nombresCliente: nombresCliente,
        nombresServicioEventual: nombresEventual,
      ),
      'Corporativo Sur',
    );
    expect(
      nombreContraparte(
        const ContraparteCobro.servicioEventual('evt-1'),
        nombresCliente: nombresCliente,
        nombresServicioEventual: nombresEventual,
      ),
      'Concierto plaza',
    );
    // Un id que no está en su mapa no cae en el del otro tipo.
    expect(
      nombreContraparte(
        const ContraparteCobro.servicioEventual('cli-1'),
        nombresCliente: nombresCliente,
        nombresServicioEventual: nombresEventual,
      ),
      '—',
    );
    expect(nombreContraparte(null, nombresCliente: nombresCliente), '—');
  });

  test('claveContraparte distingue los dos tipos con el mismo id', () {
    expect(
      claveContraparte(const ContraparteCobro.cliente('x')),
      isNot(claveContraparte(const ContraparteCobro.servicioEventual('x'))),
    );
  });

  group('sobre filas reales', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('contraparteDeCuenta y contraparteDePago leen la fila, no el contexto', () async {
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Corporativo Sur'),
          );
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DPE-000001',
              clienteId: cliente.id,
              tipoDocumento: 'factura',
              agrupacion: 'porServicio',
              metodo: 'PUE',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'key-1',
              importeBaseEsperado: 100000,
              importeFinalEsperado: 100000,
            ),
          );
      final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: Value(documento.id),
              clienteId: Value(cliente.id),
              tipoDocumento: 'factura',
              metodo: 'PUE',
              fechaEmisionReal: DateTime(2026, 2, 1),
              importeEmitido: 100000,
              saldoOriginal: 100000,
              saldoPendiente: 100000,
            ),
          );
      final pago = await db.into(db.pago).insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-000001',
              clienteId: Value(cliente.id),
              montoTotal: 100000,
              fechaPago: DateTime(2026, 2, 5),
              formaPago: 'transferencia',
            ),
          );

      expect(contraparteDeCuenta(cuenta), ContraparteCobro.cliente(cliente.id));
      expect(contraparteDePago(pago), ContraparteCobro.cliente(cliente.id));
      expect(contraparteDeCuenta(cuenta), contraparteDePago(pago));
      expect(origenDeCuenta(cuenta), OrigenCuentaPorCobrar.documentoPorEmitir);
    });

    test('una CxC sin ningún origen la rechaza el esquema', () async {
      await expectLater(
        db.into(db.cuentaPorCobrar).insert(
              CuentaPorCobrarCompanion.insert(
                clienteId: const Value('cli-suelto'),
                tipoDocumento: 'factura',
                metodo: 'PUE',
                fechaEmisionReal: DateTime(2026, 2, 1),
                importeEmitido: 100000,
                saldoOriginal: 100000,
                saldoPendiente: 100000,
              ),
            ),
        throwsA(anything),
      );
    });
  });
}
