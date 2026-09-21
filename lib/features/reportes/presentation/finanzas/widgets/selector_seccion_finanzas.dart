import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../reportes_finanzas_state.dart';

/// Selector de sección dentro de la pestaña Finanzas.
///
/// No son pestañas anidadas a propósito: el módulo ya tiene `RisegTabs`
/// arriba, y un segundo juego de pestañas debajo se lee como un error de
/// navegación. Es el mismo patrón visual que los presets de periodo, lo
/// que además comunica que se está filtrando una vista, no cambiando de
/// módulo.
class SelectorSeccionFinanzas extends StatelessWidget {
  const SelectorSeccionFinanzas({required this.seleccionada, required this.onCambiar, super.key});

  final SeccionFinanzas seleccionada;
  final ValueChanged<SeccionFinanzas> onCambiar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    String etiqueta(SeccionFinanzas seccion) => switch (seccion) {
          SeccionFinanzas.resumen => l10n.reportesFinanzasSeccionResumen,
          SeccionFinanzas.cuentasPorCobrar => l10n.reportesFinanzasSeccionCxc,
          SeccionFinanzas.pagos => l10n.reportesFinanzasSeccionPagos,
          SeccionFinanzas.deudas => l10n.reportesFinanzasSeccionDeudas,
        };

    IconData icono(SeccionFinanzas seccion) => switch (seccion) {
          SeccionFinanzas.resumen => Icons.insights_outlined,
          SeccionFinanzas.cuentasPorCobrar => Icons.receipt_long_outlined,
          SeccionFinanzas.pagos => Icons.payments_outlined,
          SeccionFinanzas.deudas => Icons.credit_card_outlined,
        };

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final seccion in SeccionFinanzas.values)
          _Chip(
            label: etiqueta(seccion),
            icono: icono(seccion),
            seleccionado: seccion == seleccionada,
            onTap: () => onCambiar(seccion),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icono, required this.seleccionado, required this.onTap});

  final String label;
  final IconData icono;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: seleccionado ? colors.accentSoftBg : Colors.transparent,
      borderRadius: AppRadius.smRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: AppRadius.smRadius,
            border: Border.all(color: seleccionado ? colors.accent : colors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: AppSizes.iconSm, color: seleccionado ? colors.accent : colors.textMuted),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: seleccionado ? colors.accent : colors.textMuted,
                  fontWeight: seleccionado ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
