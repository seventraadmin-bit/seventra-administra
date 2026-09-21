import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../pagos_list_screen.dart' show formatoCentavosPago;
import '../pagos_resumen.dart';

/// Resumen del conjunto filtrado de Pagos (Etapa 17) — Pagos recibidos
/// | Monto recibido | Monto aplicado | Pendiente de aplicar. Se
/// reorganiza 4→2→1 columnas según el ancho disponible.
class PagosResumenRow extends StatelessWidget {
  const PagosResumenRow({required this.resumen, super.key});

  final PagosResumen resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(label: l10n.pagosResumenRecibidos, value: '${resumen.pagosRecibidos}', dense: true),
      RisegStatCard(label: l10n.pagosResumenMontoRecibido, value: formatoCentavosPago(resumen.montoRecibido), dense: true),
      RisegStatCard(label: l10n.pagosResumenMontoAplicado, value: formatoCentavosPago(resumen.montoAplicado), dense: true),
      RisegStatCard(
        label: l10n.pagosResumenPendienteAplicar,
        value: formatoCentavosPago(resumen.pendienteAplicar),
        dense: true,
        deltaTone: resumen.pendienteAplicar > 0 ? RisegStatusTone.info : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact
            ? 1
            : constraints.maxWidth < AppBreakpoints.medium
                ? 2
                : 4;
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
