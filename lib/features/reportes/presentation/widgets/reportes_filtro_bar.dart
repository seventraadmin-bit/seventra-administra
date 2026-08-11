import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Barra de filtro de Reportes (Etapa 12A) — primer componente de rango
/// de fechas del proyecto (`RisegDateField` solo maneja una fecha
/// suelta). Cada pantalla de reporte decide qué filtros adicionales le
/// aplican vía [filtrosAdicionales] — nunca una barra fija con todos
/// los filtros posibles (Desde/Hasta/Servicio/Cliente/Empleado/Estatus)
/// a la vez.
///
/// `Wrap` en vez de `Row` (mismo criterio que la corrección de
/// `RisegSectionHeader`, Etapa 9D): con ancho reducido, los campos
/// bajan de línea en vez de desbordar.
class ReportesFiltroBar extends StatelessWidget {
  const ReportesFiltroBar({
    required this.rangoInicio,
    required this.rangoFin,
    required this.onRangoInicioChanged,
    required this.onRangoFinChanged,
    this.filtrosAdicionales = const [],
    super.key,
  });

  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final ValueChanged<DateTime> onRangoInicioChanged;
  final ValueChanged<DateTime> onRangoFinChanged;
  final List<Widget> filtrosAdicionales;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 180,
          child: RisegDateField(
            key: const Key('reportes_filtro_desde'),
            label: l10n.reportesFiltroDesde,
            value: rangoInicio,
            onChanged: onRangoInicioChanged,
          ),
        ),
        SizedBox(
          width: 180,
          child: RisegDateField(
            key: const Key('reportes_filtro_hasta'),
            label: l10n.reportesFiltroHasta,
            value: rangoFin,
            onChanged: onRangoFinChanged,
          ),
        ),
        for (final filtro in filtrosAdicionales) SizedBox(width: 220, child: filtro),
      ],
    );
  }
}
