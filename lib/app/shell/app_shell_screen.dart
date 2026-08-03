import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shell_destinations.dart';
import 'sidebar_mode_controller.dart';
import 'widgets/app_breadcrumb.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_top_bar.dart';

/// Cascarón visual permanente de RISEG ONE: sidebar + top bar + área de
/// contenido, envolviendo el [navigationShell] de go_router
/// (`StatefulShellRoute.indexedStack`).
///
/// Nota de memoria: `IndexedStack` mantiene montadas todas las ramas a la
/// vez (para no perder su estado al cambiar de módulo). Cuando existan
/// módulos pesados, esto puede aumentar el uso de memoria — se evaluará
/// con datos reales de uso antes de optimizar (ej. descargar ramas
/// inactivas), no de forma preventiva.
class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final destinations = buildShellDestinations(l10n);
    final mode = ref.watch(sidebarModeControllerProvider);
    final activeDestination = destinations[navigationShell.currentIndex];

    return Scaffold(
      key: const Key('app_shell'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final collapsed = resolveSidebarCollapsed(
            mode: mode,
            availableWidth: constraints.maxWidth,
          );

          return Row(
            children: [
              AppSidebar(
                destinations: destinations,
                activeIndex: navigationShell.currentIndex,
                collapsed: collapsed,
                onDestinationSelected: (index) => navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                ),
                onToggleCollapse: () => ref
                    .read(sidebarModeControllerProvider.notifier)
                    .toggleFrom(currentlyCollapsed: collapsed),
              ),
              Expanded(
                child: Column(
                  children: [
                    AppTopBar(
                      breadcrumbSegments: [BreadcrumbSegment(label: activeDestination.label)],
                    ),
                    Expanded(
                      child: Container(
                        key: const Key('shell_content_area'),
                        color: Theme.of(context).colorScheme.surface,
                        child: navigationShell,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
