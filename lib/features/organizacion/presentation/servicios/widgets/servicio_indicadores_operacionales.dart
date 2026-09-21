import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_comercial_section.dart' show formatoCentavos;

/// Antigüedad del Servicio en meses completos desde `fechaInicio` —
/// función pura nueva (Etapa 16): el calculador de antigüedad de
/// Personal es específico de la relación laboral del Empleado y no
/// aplica aquí, nunca se reutiliza forzadamente.
int calcularAntiguedadServicioEnMeses(DateTime fechaInicio, {DateTime? hoy}) {
  final referencia = hoy ?? DateTime.now();
  var meses = (referencia.year - fechaInicio.year) * 12 + (referencia.month - fechaInicio.month);
  if (referencia.day < fechaInicio.day) meses--;
  return meses < 0 ? 0 : meses;
}

/// Formatea la antigüedad en meses como "X años, Y meses" / "Y meses" /
/// "Menos de 1 mes" — mismo criterio de redacción que el resto de
/// RISEG ONE (nunca decimales, nunca "0 años 0 meses").
String formatearAntiguedadServicio(AppLocalizations l10n, int meses) {
  if (meses < 1) return l10n.servicioAntiguedadMenosDeUnMes;
  final anios = meses ~/ 12;
  final mesesRestantes = meses % 12;
  if (anios == 0) return l10n.servicioAntiguedadMeses(mesesRestantes);
  if (mesesRestantes == 0) return l10n.servicioAntiguedadAnios(anios);
  return l10n.servicioAntiguedadAniosYMeses(anios, mesesRestantes);
}

/// Indicadores operacionales del Servicio (Etapa 16, ficha operacional)
/// — Personal asignado | Cobertura/turnos | Importe mensual |
/// Antigüedad, cada uno mostrado solo cuando es derivable del modelo
/// real (ver construcción en `ServicioExpedienteScreen`). Se
/// reorganiza 4→2→1 columnas según el ancho disponible, mismo criterio
/// ya usado en Cliente/Empresa/Área.
class ServicioIndicadoresOperacionales extends StatelessWidget {
  const ServicioIndicadoresOperacionales({
    required this.personalAsignado,
    required this.coberturaTurnos,
    required this.importeMensual,
    required this.antiguedad,
    super.key,
  });

  final int personalAsignado;

  /// `null` si ninguna asignación vigente tiene turno capturado.
  final String? coberturaTurnos;
  final int importeMensual;
  final String antiguedad;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(label: l10n.servicioIndicadorPersonalAsignado, value: '$personalAsignado', dense: true),
      RisegStatCard(
        label: l10n.servicioIndicadorCoberturaTurnos,
        value: coberturaTurnos ?? l10n.servicioCoberturaTurnosSinRegistrar,
        dense: true,
      ),
      RisegStatCard(label: l10n.servicioIndicadorImporteMensual, value: formatoCentavos(importeMensual), dense: true),
      RisegStatCard(label: l10n.servicioIndicadorAntiguedad, value: antiguedad, dense: true),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact
            ? 1
            : (constraints.maxWidth < AppBreakpoints.medium ? 2 : 4);
        final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final tarjeta in tarjetas) SizedBox(width: ancho, child: tarjeta)],
        );
      },
    );
  }
}
