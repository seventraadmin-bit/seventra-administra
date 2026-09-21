import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/personal/domain/usecases/analitica_bajas.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';

BajaEvento _evento({
  String id = 'e',
  int numero = 1,
  DateTime? ingreso,
  required DateTime baja,
  String motivo = 'renuncia',
  String? servicio,
  String? puesto,
}) {
  return BajaEvento(
    empleadoId: id,
    numeroEmpleado: numero,
    nombreCompleto: 'Empleado $numero',
    fechaIngreso: ingreso ?? DateTime(baja.year, baja.month - 6, baja.day),
    fechaBaja: baja,
    motivoBaja: motivo,
    puestoNombre: puesto,
    servicioNombre: servicio,
    esBajaVigente: true,
  );
}

void main() {
  group('resolverRangoPeriodoBajas', () {
    test('esteMes resuelve al primer y último día del mes actual', () {
      final rango = resolverRangoPeriodoBajas(PeriodoAnaliticaBajas.esteMes, hoy: DateTime(2026, 8, 15));
      expect(rango.inicio, DateTime(2026, 8, 1));
      expect(rango.fin, DateTime(2026, 8, 31));
    });

    test('ultimos3Meses incluye el mes actual y los 2 anteriores', () {
      final rango = resolverRangoPeriodoBajas(PeriodoAnaliticaBajas.ultimos3Meses, hoy: DateTime(2026, 8, 15));
      expect(rango.inicio, DateTime(2026, 6, 1));
      expect(rango.fin, DateTime(2026, 8, 31));
    });

    test('esteAnio resuelve al 1 de enero – 31 de diciembre del año actual', () {
      final rango = resolverRangoPeriodoBajas(PeriodoAnaliticaBajas.esteAnio, hoy: DateTime(2026, 3, 1));
      expect(rango.inicio, DateTime(2026, 1, 1));
      expect(rango.fin, DateTime(2026, 12, 31));
    });

    test('personalizado respeta el rango explícito dado', () {
      final rango = resolverRangoPeriodoBajas(
        PeriodoAnaliticaBajas.personalizado,
        inicioPersonalizado: DateTime(2026, 2, 10),
        finPersonalizado: DateTime(2026, 5, 20),
      );
      expect(rango.inicio, DateTime(2026, 2, 10));
      expect(rango.fin, DateTime(2026, 5, 20));
    });
  });

  group('calcularBajasPorMes', () {
    test('incluye TODOS los meses del rango, incluidos los que tienen 0 bajas', () {
      final eventos = [_evento(baja: DateTime(2026, 1, 10)), _evento(baja: DateTime(2026, 3, 5))];
      final resultado = calcularBajasPorMes(eventos, DateTime(2026, 1, 1), DateTime(2026, 3, 31));

      expect(resultado, hasLength(3));
      expect(resultado[0].mes, 1);
      expect(resultado[0].cantidad, 1);
      expect(resultado[1].mes, 2);
      expect(resultado[1].cantidad, 0, reason: 'febrero no tuvo bajas pero debe aparecer en la serie');
      expect(resultado[2].mes, 3);
      expect(resultado[2].cantidad, 1);
    });
  });

  group('calcularMotivosBaja', () {
    test('cuenta y calcula porcentaje exacto por motivo, ordenado descendente', () {
      final eventos = [
        _evento(baja: DateTime(2026, 1, 1), motivo: 'renuncia'),
        _evento(baja: DateTime(2026, 1, 2), motivo: 'renuncia'),
        _evento(baja: DateTime(2026, 1, 3), motivo: 'inasistencias'),
        _evento(baja: DateTime(2026, 1, 4), motivo: 'reduccionPersonal'),
      ];
      final resultado = calcularMotivosBaja(eventos);

      expect(resultado.first.motivo.name, 'renuncia');
      expect(resultado.first.cantidad, 2);
      expect(resultado.first.porcentaje, 50.0);
      expect(resultado.fold<int>(0, (s, m) => s + m.cantidad), 4, reason: 'la suma de todos los motivos debe ser exactamente el total de eventos');
    });

    test('lista vacía si no hay eventos', () {
      expect(calcularMotivosBaja(const []), isEmpty);
    });
  });

  group('calcularSegmentosPermanencia', () {
    test('clasifica correctamente cada frontera de segmento', () {
      final eventos = [
        _evento(baja: DateTime(2026, 1, 15), ingreso: DateTime(2026, 1, 1)), // 14 días → <30
        _evento(baja: DateTime(2026, 3, 1), ingreso: DateTime(2026, 1, 1)), // ~59 días → 1-3 meses
        _evento(baja: DateTime(2026, 6, 1), ingreso: DateTime(2026, 1, 1)), // ~151 días → 3-6 meses
        _evento(baja: DateTime(2026, 10, 1), ingreso: DateTime(2026, 1, 1)), // ~273 días → 6-12 meses
        _evento(baja: DateTime(2027, 6, 1), ingreso: DateTime(2026, 1, 1)), // >365 días → +1 año
      ];
      final resultado = calcularSegmentosPermanencia(eventos);
      final porSegmento = {for (final s in resultado) s.segmento: s.cantidad};

      expect(porSegmento[SegmentoPermanencia.menos30Dias], 1);
      expect(porSegmento[SegmentoPermanencia.uno3Meses], 1);
      expect(porSegmento[SegmentoPermanencia.tres6Meses], 1);
      expect(porSegmento[SegmentoPermanencia.seis12Meses], 1);
      expect(porSegmento[SegmentoPermanencia.masDeUnAnio], 1);
      expect(resultado.fold<int>(0, (s, e) => s + e.cantidad), 5);
    });
  });

  group('calcularServiciosConMayorRotacion', () {
    test('agrupa por servicioNombre del SNAPSHOT de cada evento, nunca por el Servicio actual del Empleado', () {
      final eventos = [
        _evento(baja: DateTime(2026, 1, 1), servicio: 'Sportium Cuautitlán', motivo: 'renuncia'),
        _evento(baja: DateTime(2026, 1, 2), servicio: 'Sportium Cuautitlán', motivo: 'renuncia'),
        _evento(baja: DateTime(2026, 1, 3), servicio: 'Residencial Tikal', motivo: 'inasistencias'),
        _evento(baja: DateTime(2026, 1, 4), servicio: null), // sin servicio al momento de la baja — excluido
      ];
      final resultado = calcularServiciosConMayorRotacion(eventos);

      expect(resultado, hasLength(2), reason: 'el evento sin servicioNombre se excluye, nunca se inventa un Servicio');
      expect(resultado.first.servicioNombre, 'Sportium Cuautitlán');
      expect(resultado.first.cantidad, 2);
      expect(resultado.first.motivoPrincipal.name, 'renuncia');
    });
  });

  group('filtrarRotacionTemprana', () {
    test('solo incluye eventos con menos de 30 días laborados', () {
      final eventos = [
        _evento(baja: DateTime(2026, 1, 10), ingreso: DateTime(2026, 1, 1)), // 9 días
        _evento(baja: DateTime(2026, 6, 1), ingreso: DateTime(2026, 1, 1)), // ~151 días
      ];
      final resultado = filtrarRotacionTemprana(eventos);
      expect(resultado, hasLength(1));
      expect(resultado.single.permanenciaDias, lessThan(30));
    });
  });

  group('filtrarEventosPorRango', () {
    test('excluye eventos fuera del rango, incluye los límites', () {
      final eventos = [
        _evento(baja: DateTime(2026, 1, 31)),
        _evento(baja: DateTime(2026, 2, 1)),
        _evento(baja: DateTime(2026, 2, 28)),
        _evento(baja: DateTime(2026, 3, 1)),
      ];
      final resultado = filtrarEventosPorRango(eventos, DateTime(2026, 2, 1), DateTime(2026, 2, 28));
      expect(resultado, hasLength(2));
    });
  });
}
