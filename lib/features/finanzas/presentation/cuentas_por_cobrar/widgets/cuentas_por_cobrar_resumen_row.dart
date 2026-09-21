import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../cuentas_por_cobrar_list_screen.dart' show formatoCentavosCuentaPorCobrar;
import '../cuentas_por_cobrar_resumen.dart';

/// Resumen del conjunto filtrado de Cuentas por cobrar (Etapa 17) —
/// Saldo pendiente | Saldo vencido | Por vencer | Pagadas. Se
/// reorganiza 4→2→1 columnas según el ancho disponible, mismo criterio
/// ya usado en Cliente/Servicio/Agenda.
class CuentasPorCobrarResumenRow extends StatelessWidget {
  const CuentasPorCobrarResumenRow({required this.resumen, super.key});

  final CuentasPorCobrarResumen resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(
        label: l10n.cuentasPorCobrarResumenSaldoPendiente,
        value: formatoCentavosCuentaPorCobrar(resumen.saldoPendiente),
        dense: true,
      ),
      RisegStatCard(
        label: l10n.cuentasPorCobrarResumenSaldoVencido,
        value: formatoCentavosCuentaPorCobrar(resumen.saldoVencido),
        dense: true,
        deltaTone: resumen.saldoVencido > 0 ? RisegStatusTone.error : null,
      ),
      RisegStatCard(
        label: l10n.cuentasPorCobrarResumenPorVencer,
        value: formatoCentavosCuentaPorCobrar(resumen.saldoPorVencer),
        dense: true,
      ),
      RisegStatCard(label: l10n.cuentasPorCobrarResumenPagadas, value: '${resumen.pagadas}', dense: true),
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
