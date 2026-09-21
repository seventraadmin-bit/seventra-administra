// Etapa 16 — indicador "Antigüedad" del expediente de Servicio.
// Función pura nueva: no reutiliza el calculador de antigüedad de
// Personal (es específico de la relación laboral del Empleado, un
// concepto distinto).

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_indicadores_operacionales.dart';

void main() {
  group('calcularAntiguedadServicioEnMeses', () {
    test('el mismo día es 0 meses', () {
      expect(calcularAntiguedadServicioEnMeses(DateTime(2026, 8, 21), hoy: DateTime(2026, 8, 21)), 0);
    });

    test('45 días después es 1 mes completo', () {
      expect(calcularAntiguedadServicioEnMeses(DateTime(2026, 1, 1), hoy: DateTime(2026, 2, 15)), 1);
    });

    test('un día antes de cumplir el mes todavía no cuenta ese mes', () {
      expect(calcularAntiguedadServicioEnMeses(DateTime(2026, 1, 15), hoy: DateTime(2026, 2, 14)), 0);
    });

    test('14 meses exactos', () {
      expect(calcularAntiguedadServicioEnMeses(DateTime(2025, 1, 1), hoy: DateTime(2026, 3, 1)), 14);
    });

    test('24 meses exactos', () {
      expect(calcularAntiguedadServicioEnMeses(DateTime(2024, 8, 21), hoy: DateTime(2026, 8, 21)), 24);
    });
  });

  group('formatearAntiguedadServicio', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('es'));
    });

    test('0 meses → "Menos de 1 mes"', () {
      expect(formatearAntiguedadServicio(l10n, 0), l10n.servicioAntiguedadMenosDeUnMes);
    });

    test('1 mes → "1 mes"', () {
      expect(formatearAntiguedadServicio(l10n, 1), l10n.servicioAntiguedadMeses(1));
    });

    test('14 meses → "1 año, 2 meses"', () {
      expect(formatearAntiguedadServicio(l10n, 14), '${l10n.servicioAntiguedadAnios(1)}, ${l10n.servicioAntiguedadMeses(2)}');
    });

    test('24 meses exactos → "2 años" sin sobrante de meses', () {
      expect(formatearAntiguedadServicio(l10n, 24), l10n.servicioAntiguedadAnios(2));
    });
  });
}
