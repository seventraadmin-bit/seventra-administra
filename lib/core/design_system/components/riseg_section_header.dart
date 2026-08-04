import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Encabezado de una sección de formulario, listado o expediente.
///
/// El título/descripción se truncan y las acciones nunca empujan el
/// layout a desbordarse en anchos reducidos — mismo cuidado que ya
/// resolvió el desbordamiento del breadcrumb en la Etapa 2.
class RisegSectionHeader extends StatelessWidget {
  const RisegSectionHeader({
    required this.title,
    this.description,
    this.primaryAction,
    this.secondaryAction,
    super.key,
  });

  final String title;
  final String? description;

  /// Normalmente un [RisegButton]; el llamador decide la variante.
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasActions = primaryAction != null || secondaryAction != null;

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(description!, style: AppTypography.body.copyWith(color: colors.textMuted)),
        ],
      ],
    );

    if (!hasActions) return titleColumn;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleColumn),
        const SizedBox(width: AppSpacing.md),
        if (secondaryAction != null) ...[secondaryAction!, const SizedBox(width: AppSpacing.xs)],
        if (primaryAction != null) primaryAction!,
      ],
    );
  }
}
