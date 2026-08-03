import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'shell_destinations.dart';

/// Pantalla placeholder genérica usada por los 10 destinos del Shell.
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          key: Key('module_placeholder_${destination.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(destination.icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(destination.label, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              l10n.modulePlaceholderMessage(destination.label),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
