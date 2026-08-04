import 'package:flutter/material.dart';

import '../theme_context.dart';
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
    super.key,
  });

  final String label;
  final String value;
  final String? delta;

  /// Reutiliza el mismo vocabulario de tono que [RisegStatusBadge].
  final RisegStatusTone? deltaTone;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RisegCard(
      variant: onTap == null ? RisegCardVariant.standard : RisegCardVariant.interactive,
      onTap: onTap,
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
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTypography.heading1.copyWith(color: colors.textPrimary)),
          if (delta != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            RisegStatusBadge(label: delta!, tone: deltaTone ?? RisegStatusTone.neutral),
          ],
        ],
      ),
    );
  }
}
