import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import '../ingresos_resumen.dart';

/// Resumen del conjunto filtrado de Ingresos (Etapa 17) — Ingresos
/// totales | Automáticos | Manuales. Se reorganiza 3→1 columnas según
/// el ancho disponible.
class IngresosResumenRow extends StatelessWidget {
  const IngresosResumenRow({required this.resumen, super.key});

  final IngresosResumen resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(label: l10n.ingresosResumenTotal, value: formatoCentavosPago(resumen.totalIngresos), dense: true),
      RisegStatCard(label: l10n.ingresosResumenAutomaticos, value: formatoCentavosPago(resumen.automaticos), dense: true),
      RisegStatCard(label: l10n.ingresosResumenManuales, value: formatoCentavosPago(resumen.manuales), dense: true),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact ? 1 : 3;
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
