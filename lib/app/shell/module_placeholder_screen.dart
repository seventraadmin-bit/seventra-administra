import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/design_system/tokens/app_spacing.dart';
import 'shell_destinations.dart';

/// Pantalla placeholder genérica usada por los 9 destinos del Shell que
/// todavía no se implementan (el Dashboard tiene su propia pantalla —
/// [DashboardWelcomeScreen] — por ser la pantalla de inicio real).
///
/// Deliberadamente simple: solo confirma que la navegación llega al
/// destino correcto. No contiene lógica de negocio ni datos reales — cada
/// módulo la reemplaza por su propia pantalla cuando se implemente.
class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({required this.destination, super.key});

  final ShellDestination destination;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          key: Key('module_placeholder_${destination.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(destination.icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(destination.label, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.modulePlaceholderMessage(destination.label),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
