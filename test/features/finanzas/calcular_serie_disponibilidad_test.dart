// Etapa 19D — "Calendario financiero y planeación de liquidez".
// Pruebas puras (sin BD) de la serie diaria de disponibilidad, el
// saldo mínimo proyectado y el resumen por semana calendario real.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';

CompromisoFinanciero _compromiso({
  required DateTime fecha,
  required TipoCompromiso tipo,
  required int importe,
  String origenId = 'origen-1',
}) {
  return CompromisoFinanciero(
    fecha: fecha,
    concepto: 'Compromiso de prueba',
    tipo: tipo,
    origen: OrigenCompromiso.cuentaPorCobrar,
    importe: importe,
    origenId: origenId,
  );
}

void main() {
  group('calcularSerieDisponibilidad', () {
    test('disponible hoy \$50,000, cobro futuro \$20,000, pago futuro \$10,000 → saldo final \$60,000', () {
      final hoy = DateTime(2026, 9, 1);
      final serie = calcularSerieDisponibilidad(
        hoy: hoy,
        hasta: DateTime(2026, 9, 10),
        saldoActual: 5000000,
        compromisos: [
          _compromiso(fecha: DateTime(2026, 9, 5), tipo: TipoCompromiso.entrada, importe: 2000000),
          _compromiso(fecha: DateTime(2026, 9, 8), tipo: TipoCompromiso.salida, importe: 1000000),
        ],
      );

      expect(serie.last.saldo, 6000000);
      expect(serie.first.saldo, 5000000, reason: 'el día de hoy sin compromisos no altera el saldo inicial');
    });

    test('dos eventos el mismo día se agregan correctamente', () {
      final hoy = DateTime(2026, 9, 1);
      final serie = calcularSerieDisponibilidad(
        hoy: hoy,
        hasta: DateTime(2026, 9, 5),
        saldoActual: 1000000,
        compromisos: [
          _compromiso(fecha: DateTime(2026, 9, 3), tipo: TipoCompromiso.entrada, importe: 500000),
          _compromiso(fecha: DateTime(2026, 9, 3), tipo: TipoCompromiso.salida, importe: 200000),
        ],
      );

      final punto3 = serie.firstWhere((p) => p.fecha == DateTime(2026, 9, 3));
      expect(punto3.entradasDelDia, 500000);
      expect(punto3.salidasDelDia, 200000);
      expect(punto3.saldo, 1300000, reason: r'$10,000 + $5,000 - $2,000 = $13,000');
    });

    test('el déficit cruza cero correctamente cuando un compromiso supera el saldo acumulado', () {
      final hoy = DateTime(2026, 9, 1);
      final serie = calcularSerieDisponibilidad(
        hoy: hoy,
        hasta: DateTime(2026, 9, 10),
        saldoActual: 500000,
        compromisos: [
          _compromiso(fecha: DateTime(2026, 9, 5), tipo: TipoCompromiso.salida, importe: 2000000),
        ],
      );

      final antesDelPago = serie.firstWhere((p) => p.fecha == DateTime(2026, 9, 4));
      final despuesDelPago = serie.firstWhere((p) => p.fecha == DateTime(2026, 9, 5));
      expect(antesDelPago.saldo, greaterThanOrEqualTo(0));
      expect(despuesDelPago.saldo, lessThan(0), reason: r'$5,000 - $20,000 = -$15,000');
    });

    test('sin CuentaFinanciera (saldoActual 0 tratado como no configurado por el llamador) la serie sigue siendo determinista', () {
      final serie = calcularSerieDisponibilidad(
        hoy: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 3),
        saldoActual: 0,
        compromisos: const [],
      );
      expect(serie, hasLength(3));
      expect(serie.every((p) => p.saldo == 0), isTrue, reason: 'la función nunca inventa un saldo inicial — usa exactamente lo que recibe');
    });
  });

  group('encontrarMinimo', () {
    test('saldo mínimo y fecha se calculan correctamente', () {
      final serie = calcularSerieDisponibilidad(
        hoy: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 20),
        saldoActual: 5000000,
        compromisos: [
          _compromiso(fecha: DateTime(2026, 9, 10), tipo: TipoCompromiso.salida, importe: 4200000),
          _compromiso(fecha: DateTime(2026, 9, 18), tipo: TipoCompromiso.entrada, importe: 3000000),
        ],
      );

      final minimo = encontrarMinimo(serie)!;
      expect(minimo.fecha, DateTime(2026, 9, 10));
      expect(minimo.saldo, 800000);
    });
  });

  group('agruparPorSemanaCalendario', () {
    test('resumen por semana conserva exactamente los totales diarios, con cortes de calendario real', () {
      // 1/sep/2026 es martes — la primera "semana" visible queda
      // recortada a martes-domingo (1 al 6), nunca un bloque fijo de 7
      // días que ignore dónde cae el 1 del mes.
      final serie = calcularSerieDisponibilidad(
        hoy: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 20),
        saldoActual: 6330000,
        compromisos: [
          _compromiso(fecha: DateTime(2026, 9, 2), tipo: TipoCompromiso.salida, importe: 8200000),
          _compromiso(fecha: DateTime(2026, 9, 10), tipo: TipoCompromiso.entrada, importe: 3500000),
          _compromiso(fecha: DateTime(2026, 9, 16), tipo: TipoCompromiso.salida, importe: 6800000),
        ],
      );

      final semanas = agruparPorSemanaCalendario(serie);

      expect(semanas[0].inicio, DateTime(2026, 9, 1));
      expect(semanas[0].fin, DateTime(2026, 9, 6));
      expect(semanas[0].salidas, 8200000);
      expect(semanas[0].entradas, 0);

      expect(semanas[1].inicio, DateTime(2026, 9, 7));
      expect(semanas[1].fin, DateTime(2026, 9, 13));
      expect(semanas[1].entradas, 3500000);

      expect(semanas[2].inicio, DateTime(2026, 9, 14));
      expect(semanas[2].salidas, 6800000);

      // El último saldo de cada semana debe coincidir exactamente con
      // el último punto diario de esa semana — nunca un total
      // recalculado por separado.
      final ultimoPuntoSemana1 = serie.firstWhere((p) => p.fecha == semanas[0].fin);
      expect(semanas[0].saldoFinal, ultimoPuntoSemana1.saldo);
    });

    test('cambio de mes no duplica eventos: cada compromiso cae en exactamente una semana', () {
      final serie = calcularSerieDisponibilidad(
        hoy: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 30),
        saldoActual: 0,
        compromisos: [
          _compromiso(fecha: DateTime(2026, 9, 5), tipo: TipoCompromiso.entrada, importe: 100000),
        ],
      );

      final semanas = agruparPorSemanaCalendario(serie);
      final totalEntradas = semanas.fold<int>(0, (s, sem) => s + sem.entradas);
      expect(totalEntradas, 100000, reason: 'ninguna semana debe contar el mismo compromiso dos veces');
    });
  });
}
