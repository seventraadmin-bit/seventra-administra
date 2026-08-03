import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../shell_breakpoints.dart';
import '../shell_destinations.dart';

/// Sidebar persistente del Shell.
///
/// Widget de presentación puro: no lee providers directamente — recibe
/// [collapsed] ya resuelto y notifica [onToggleCollapse]/[onDestinationSelected]
/// hacia arriba. Así se puede probar y reutilizar sin depender de Riverpod.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.destinations,
    required this.activeIndex,
    required this.collapsed,
    required this.onDestinationSelected,
    required this.onToggleCollapse,
    super.key,
  });

  final List<ShellDestination> destinations;
  final int activeIndex;
  final bool collapsed;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      key: const Key('app_sidebar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: collapsed ? ShellBreakpoints.sidebarCollapsedWidth : ShellBreakpoints.sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          _SidebarHeader(collapsed: collapsed),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final destination = destinations[index];
                return _SidebarItem(
                  destination: destination,
                  isActive: index == activeIndex,
                  collapsed: collapsed,
                  onTap: () => onDestinationSelected(index),
                );
              },
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          _CollapseButton(collapsed: collapsed, onPressed: onToggleCollapse),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final logo = Image.asset(
      'assets/images/logo.png',
      key: const Key('sidebar_logo'),
      fit: BoxFit.contain,
      height: collapsed ? 40 : 96,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 20, vertical: 20),
      child: collapsed ? Tooltip(message: l10n.appTitle, child: logo) : logo,
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.isActive,
    required this.collapsed,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool isActive;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final icon = Icon(
      destination.icon,
      color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
    );

    // Un solo hijo cuando está colapsado: se centra directamente en vez de
    // envolverlo en un Row, para no depender de un ancho mínimo de fila que
    // pueda quedar por debajo del contenido en anchos de ventana extremos.
    final rowOrIcon = collapsed
        ? Center(child: icon)
        : Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          );

    final content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      // Padding horizontal constante a propósito (no condicionado a
      // `collapsed`): si cambiara de golpe junto con la estructura del
      // contenido mientras el ancho del sidebar todavía está animando,
      // reaparece el desborde transitorio que este diseño evita.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: rowOrIcon,
    );

    Widget child = InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: content);
    if (collapsed) {
      child = Tooltip(message: destination.label, child: child);
    }

    return Semantics(
      key: Key('nav_item_${destination.id}'),
      container: true,
      selected: isActive,
      button: true,
      label: destination.label,
      child: child,
    );
  }
}

class _CollapseButton extends StatelessWidget {
  const _CollapseButton({required this.collapsed, required this.onPressed});

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: IconButton(
        key: const Key('sidebar_collapse_button'),
        tooltip: collapsed ? l10n.shellExpandSidebarTooltip : l10n.shellCollapseSidebarTooltip,
        icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
        onPressed: onPressed,
      ),
    );
  }
}
