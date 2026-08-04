import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/config/app_info.dart';
import '../../core/design_system/tokens/app_color_scheme.dart';
import '../../core/design_system/tokens/app_spacing.dart';
import '../../core/design_system/tokens/app_typography.dart';

/// Pantalla de bienvenida del destino Dashboard.
///
/// A diferencia de los otros 9 destinos (que todavía no existen y usan
/// [ModulePlaceholderScreen]), el Dashboard es la pantalla de inicio real
/// del producto — por eso tiene su propio contenido en vez de un genérico
/// "disponible próximamente".
class DashboardWelcomeScreen extends StatelessWidget {
  const DashboardWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).extension<AppColorScheme>()!;
    final displayVersion = kAppVersion.split('+').first;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            key: const Key('dashboard_welcome'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.dashboardWelcomeTitle,
                textAlign: TextAlign.center,
                style: AppTypography.heading1.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.dashboardWelcomeMessage,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                l10n.dashboardVersionLabel(displayVersion),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
