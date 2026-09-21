import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_color_scheme.dart';
import '../tokens/app_sizes.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'riseg_card.dart';
import 'riseg_status_badge.dart';

/// Tarjeta de métrica para el Dashboard y resúmenes de módulo.
///
/// Deliberadamente sobre [RisegCard] en vez de un `Container` propio —
/// reutiliza el propio Design System, no solo Material directo.
class RisegStatCard extends StatelessWidget {
  const RisegStatCard({
    required this.label,
    required this.value,
    this.delta,
    this.deltaTone,
    this.icon,
    this.onTap,
    this.dense = false,
    super.key,
  });

  final String label;
  final String value;
  final String? delta;

  /// Reutiliza el mismo vocabulario de tono que [RisegStatusBadge]. Sin
  /// [delta], tiñe directamente el número (el elemento dominante de la
  /// tarjeta) en vez de no tener ningún efecto visible — antes, pasar
  /// `deltaTone` sin `delta` no cambiaba nada en pantalla (Etapa 15,
  /// hallazgo real: varias pantallas ya lo hacían esperando un efecto).
  final RisegStatusTone? deltaTone;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Tarjeta ejecutiva compacta (Etapa 15, rediseño visual de
  /// Personal/Bajas) — mismo contenido, con menos aire alrededor.
  /// `false` conserva el aspecto exacto de todos los usos existentes.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueColor = delta == null && deltaTone != null ? _colorDeTono(colors, deltaTone!) : colors.textPrimary;

    return RisegCard(
      variant: onTap == null ? RisegCardVariant.standard : RisegCardVariant.interactive,
      onTap: onTap,
      padding: dense ? const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
              ),
              if (icon != null) Icon(icon, size: AppSizes.iconMd, color: colors.textMuted),
            ],
          ),
          SizedBox(height: dense ? AppSpacing.xxs : AppSpacing.xs),
          Text(value, style: AppTypography.heading1.copyWith(color: valueColor)),
          if (delta != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            RisegStatusBadge(label: delta!, tone: deltaTone ?? RisegStatusTone.neutral),
          ],
        ],
      ),
    );
  }
}

Color _colorDeTono(AppColorScheme colors, RisegStatusTone tone) {
  return switch (tone) {
    RisegStatusTone.success => colors.success,
    RisegStatusTone.warning => colors.warning,
    RisegStatusTone.error => colors.error,
    RisegStatusTone.info => colors.info,
    RisegStatusTone.neutral => colors.neutralText,
  };
}
