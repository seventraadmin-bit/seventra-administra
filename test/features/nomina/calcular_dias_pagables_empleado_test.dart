import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/nomina/data/tables/nomina_empleado_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/calcular_dias_pagables_empleado.dart';

void main() {
  group('calcularDiasPagablesEmpleado — cobertura completa (Caso A)', () {
    test('primera quincena, un solo tramo: 15 días pagables, importe = sueldo/2', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 15),
      );

      expect(resultado.diasPagables, 15);
      expect(resultado.importeBase, 1500000, reason: 'la primera quincena siempre tiene 15 días reales — se reduce a sueldo/2');
      expect(resultado.tramos, hasLength(1));
    });

    test('segunda quincena de 31 días, un solo tramo: 15 días pagables (no 16), importe = sueldo/2', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      expect(resultado.diasPagables, 15, reason: 'una segunda quincena completa nunca paga 16 días, aunque el mes tenga 31');
      expect(resultado.importeBase, 1500000);
    });

    test('segunda quincena de febrero no bisiesto (13 días reales): igual paga sueldo/2, no menos', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 2, 16),
        periodoFin: DateTime(2026, 2, 28),
      );

      expect(resultado.diasPagables, 15);
      expect(resultado.importeBase, 1500000, reason: 'un febrero corto no debe pagar menos que medio sueldo con cobertura completa');
    });

    test('segunda quincena de febrero bisiesto (14 días reales): igual paga sueldo/2', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2028, 2, 16),
        periodoFin: DateTime(2028, 2, 29),
      );

      expect(resultado.diasPagables, 15);
      expect(resultado.importeBase, 1500000);
    });

    test('segunda quincena de un mes de 30 días (15 días reales): paga sueldo/2 exacto', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 4, 16),
        periodoFin: DateTime(2026, 4, 30),
      );

      expect(resultado.diasPagables, 15);
      expect(resultado.importeBase, 1500000);
    });

    test('cambio de Servicio a mitad de una segunda quincena de 31 días: nunca excede sueldo/2 del mayor', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(
            inicio: _muyAntes,
            fin: DateTime(2026, 1, 23),
            fuente: FuenteSueldoNomina.servicio,
            servicioId: 'servicio-a',
            sueldoMensual: 2000000,
            bonoMensual: 0,
          ),
          IntervaloSueldo(
            inicio: DateTime(2026, 1, 24),
            fuente: FuenteSueldoNomina.servicio,
            servicioId: 'servicio-b',
            sueldoMensual: 3000000,
            bonoMensual: 0,
          ),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      expect(resultado.diasPagables, 15);
      expect(resultado.tramos, hasLength(2));
      expect(resultado.tramos[0].diasReales, 8); // 16-23
      expect(resultado.tramos[1].diasReales, 8); // 24-31
      // Promedio ponderado de ambos medios-sueldos (50/50 en días reales):
      // (2,000,000/2 * 0.5) + (3,000,000/2 * 0.5) = 1,250,000.
      expect(resultado.importeBase, 1250000);
      expect(resultado.importeBase, lessThan(1500000), reason: 'nunca debe superar el equivalente a 15 días del sueldo mayor');
      expect(resultado.sueldoMensualUtilizado, 3000000, reason: 'el sueldo mensual utilizado es el del último tramo');
    });
  });

  group('calcularDiasPagablesEmpleado — cobertura parcial (Caso B): altas/bajas/reingresos', () {
    test('alta a mitad de la segunda quincena: días pagables reales, importe real-day/30', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: DateTime(2026, 1, 20))],
        intervalosSueldo: [
          IntervaloSueldo(
            inicio: DateTime(2026, 1, 20),
            fuente: FuenteSueldoNomina.servicio,
            sueldoMensual: 3000000,
            bonoMensual: 0,
          ),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      expect(resultado.diasPagables, 12, reason: '20 al 31 inclusive = 12 días');
      expect(resultado.importeBase, (3000000 * 12 / 30).round());
    });

    test('baja a mitad de la segunda quincena: solo los días reales trabajados', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes, fin: DateTime(2026, 1, 25))],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      expect(resultado.diasPagables, 10, reason: '16 al 25 inclusive = 10 días');
      expect(resultado.importeBase, (3000000 * 10 / 30).round());
    });

    test('reingreso dentro de la misma quincena: dos segmentos, ambos días reales cuentan (sin el hueco)', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [
          SegmentoLaboral(inicio: _muyAntes, fin: DateTime(2026, 1, 18)),
          SegmentoLaboral(inicio: DateTime(2026, 1, 22)),
        ],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      // Segmento 1: 16-18 = 3 días. Segmento 2: 22-31 = 10 días. Total 13.
      expect(resultado.diasPagables, 13);
      expect(resultado.tramos, hasLength(2));
      expect(resultado.importeBase, (3000000 * 3 / 30).round() + (3000000 * 10 / 30).round());
    });

    test('alta y baja el mismo día (un solo día pagable)', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: DateTime(2026, 1, 20), fin: DateTime(2026, 1, 20))],
        intervalosSueldo: [
          IntervaloSueldo(inicio: DateTime(2026, 1, 20), fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      expect(resultado.diasPagables, 1);
      expect(resultado.importeBase, (3000000 * 1 / 30).round());
    });

    test('cambio de Servicio dentro de un segmento parcial usa real-day/30 por sub-tramo, no la ponderación del Caso A', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: DateTime(2026, 1, 20))],
        intervalosSueldo: [
          IntervaloSueldo(
            inicio: DateTime(2026, 1, 20),
            fin: DateTime(2026, 1, 25),
            fuente: FuenteSueldoNomina.servicio,
            servicioId: 'servicio-a',
            sueldoMensual: 2000000,
            bonoMensual: 0,
          ),
          IntervaloSueldo(
            inicio: DateTime(2026, 1, 26),
            fuente: FuenteSueldoNomina.servicio,
            servicioId: 'servicio-b',
            sueldoMensual: 3000000,
            bonoMensual: 0,
          ),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      // Tramo 1: 20-25 = 6 días. Tramo 2: 26-31 = 6 días.
      expect(resultado.diasPagables, 12);
      expect(resultado.importeBase, (2000000 * 6 / 30).round() + (3000000 * 6 / 30).round());
    });
  });

  group('calcularDiasPagablesEmpleado — fuente administrativa', () {
    test('empleado administrativo (sin Servicio) calcula igual, con fuente administrativo', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.administrativo, sueldoMensual: 1800000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 15),
      );

      expect(resultado.diasPagables, 15);
      expect(resultado.importeBase, 900000);
      expect(resultado.tramos.single.fuente, FuenteSueldoNomina.administrativo);
    });
  });

  group('calcularDiasPagablesEmpleado — bono nunca se prorratea', () {
    test('el bono disponible es el del último tramo, no una mezcla', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(
            inicio: _muyAntes,
            fin: DateTime(2026, 1, 23),
            fuente: FuenteSueldoNomina.servicio,
            sueldoMensual: 2000000,
            bonoMensual: 100000,
          ),
          IntervaloSueldo(
            inicio: DateTime(2026, 1, 24),
            fuente: FuenteSueldoNomina.servicio,
            sueldoMensual: 3000000,
            bonoMensual: 200000,
          ),
        ],
        periodoInicio: DateTime(2026, 1, 16),
        periodoFin: DateTime(2026, 1, 31),
      );

      expect(resultado.bonoDisponible, 200000, reason: 'el bono del último tramo, nunca prorrateado ni sumado');
    });
  });

  group('calcularDiasPagablesEmpleado — casos límite', () {
    test('sin ningún segmento laboral que intersecte el periodo: 0 días, 0 importe', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: DateTime(2026, 3, 1))],
        intervalosSueldo: [
          IntervaloSueldo(inicio: DateTime(2026, 3, 1), fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 15),
      );

      expect(resultado.diasPagables, 0);
      expect(resultado.importeBase, 0);
      expect(resultado.tramos, isEmpty);
    });

    test('un hueco sin ninguna fuente de sueldo lanza SueldoNoDisponibleException', () {
      expect(
        () => calcularDiasPagablesEmpleado(
          segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
          intervalosSueldo: [
            IntervaloSueldo(
              inicio: _muyAntes,
              fin: DateTime(2026, 1, 10),
              fuente: FuenteSueldoNomina.servicio,
              sueldoMensual: 3000000,
              bonoMensual: 0,
            ),
            // Hueco: sin cobertura del 11 al 15.
            IntervaloSueldo(
              inicio: DateTime(2026, 1, 16),
              fuente: FuenteSueldoNomina.servicio,
              sueldoMensual: 3000000,
              bonoMensual: 0,
            ),
          ],
          periodoInicio: DateTime(2026, 1, 1),
          periodoFin: DateTime(2026, 1, 15),
        ),
        throwsA(isA<SueldoNoDisponibleException>()),
      );
    });

    test('puestoNombre se propaga tal cual al resultado', () {
      final resultado = calcularDiasPagablesEmpleado(
        segmentosLaborales: [SegmentoLaboral(inicio: _muyAntes)],
        intervalosSueldo: [
          IntervaloSueldo(inicio: _muyAntes, fuente: FuenteSueldoNomina.servicio, sueldoMensual: 3000000, bonoMensual: 0),
        ],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 15),
        puestoNombre: 'Guardia',
      );

      expect(resultado.puestoNombre, 'Guardia');
    });
  });
}

final _muyAntes = DateTime(2000, 1, 1);
