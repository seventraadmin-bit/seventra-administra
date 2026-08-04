import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_sizes.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Estado vacío de RISEG ONE — siempre específico al contexto (título +
/// explicación breve), nunca un genérico "No hay datos". Se usa tanto
/// para listados/tablas vacíos como para pantallas de módulo (ver
/// `DashboardWelcomeScreen`, que sigue el mismo patrón a mano).
class RisegEmptyState extends StatelessWidget {
  const RisegEmptyState({
    required this.title,
    required this.message,
    this.icon,
    this.primaryAction,
    this.secondaryAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData? icon;
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSizes.iconLg, color: colors.textMuted),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.heading3.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
              if (primaryAction != null || secondaryAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (secondaryAction != null) secondaryAction!,
                    if (primaryAction != null) primaryAction!,
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
