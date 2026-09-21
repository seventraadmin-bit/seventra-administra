import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_ciclo_laboral_empleado.dart';

/// Antigüedad legible del periodo laboral vigente (Etapa 17) — mismo
/// cálculo puro de siempre (`calcularCicloLaboralEmpleado`), nunca los
/// "días activo" crudos (204 días, 120 días... ilegibles con el tiempo).
/// Con al menos un año: "{años} años {meses} meses" (o solo años si
/// meses es 0). Por debajo de un año: "{meses} meses {días} días" (o
/// solo meses/días cuando el otro componente es 0) — el residuo de
/// días usa `antiguedadDiasResiduales`, el mismo criterio de "día de
/// corte" que ya usa `antiguedadMeses`, nunca una aproximación de 30
/// días por mes. Compartida entre "Plantilla activa" y el expediente
/// del Empleado — un solo formato, nunca duplicado.
String antiguedadTexto(AppLocalizations l10n, EmpleadoData empleado) {
  final ciclo = calcularCicloLaboralEmpleado(empleado);
  if (ciclo.antiguedadAnios > 0) {
    return ciclo.antiguedadMeses > 0
        ? l10n.antiguedadCompactaAniosMeses(ciclo.antiguedadAnios, ciclo.antiguedadMeses)
        : l10n.antiguedadCompactaAnios(ciclo.antiguedadAnios);
  }
  if (ciclo.antiguedadMeses > 0) {
    return ciclo.antiguedadDiasResiduales > 0
        ? l10n.antiguedadCompactaMesesDias(ciclo.antiguedadMeses, ciclo.antiguedadDiasResiduales)
        : l10n.antiguedadCompactaMeses(ciclo.antiguedadMeses);
  }
  return l10n.antiguedadCompactaDias(ciclo.diasLaborados);
}
