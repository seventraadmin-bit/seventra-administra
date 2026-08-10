import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/design_system/tokens/app_color_scheme.dart';
import '../../../core/design_system/tokens/app_spacing.dart';
import '../../../core/design_system/tokens/app_typography.dart';
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
          // Branding: siempre fijo, nunca entra en el área con scroll —
          // Resolución explícita de Marlon (Etapa 3B, revisión de
          // navegación): ningún destino debe volverse inaccesible por
          // altura de ventana reducida.
          _SidebarHeader(collapsed: collapsed),
          Divider(height: 1, color: theme.dividerColor),
          // Zona con scroll: solo los destinos. `Scrollbar` con
          // `thumbVisibility: true` para que el scroll sea descubrible a
          // simple vista, no solo funcional (Resolución de Marlon: "el
          // comportamiento correcto es responsive + scroll"). El control
          // de colapso se queda fijo fuera de esta zona (ver más abajo) —
          // la protección contra desborde en alturas extremas vive en
          // `resolveSidebarCollapsed`, que ahora también reacciona a la
          // altura disponible (mismo mecanismo ya usado para el ancho),
          // en vez de mover el control a un lugar donde dejaría de estar
          // siempre visible en el caso común.
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                key: const Key('app_sidebar_nav_scroll'),
                padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                children: [
                  for (var index = 0; index < destinations.length; index++)
                    _SidebarItem(
                      destination: destinations[index],
                      isActive: index == activeIndex,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(index),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          _CollapseButton(collapsed: collapsed, onPressed: onToggleCollapse),
        ],
      ),
    );
  }
}

/// Encabezado corporativo del sidebar: logotipo + nombre + subtítulo cuando
/// hay espacio, solo el logotipo (escalado, nunca recortado) cuando está
/// colapsado. El archivo del logotipo nunca se modifica — solo cambia el
/// tamaño con el que se dibuja.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).extension<AppColorScheme>()!;

    final logo = Image.asset(
      'assets/images/logo.png',
      key: const Key('sidebar_logo'),
      fit: BoxFit.contain,
      height: collapsed ? 40 : 56,
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xl),
        child: Tooltip(message: l10n.appTitle, child: logo),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        children: [
          logo,
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.appTitle,
            textAlign: TextAlign.center,
            style: AppTypography.heading3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.appSubtitle,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
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
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hasFocus = false;

  ShellDestination get destination => widget.destination;
  bool get isActive => widget.isActive;
  bool get collapsed => widget.collapsed;
  VoidCallback get onTap => widget.onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColorScheme>()!;

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
              const SizedBox(width: AppSpacing.sm),
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
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: isActive ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
        borderRadius: BorderRadius.circular(8),
        // Anillo de foco de teclado explícito: sin esto, Tab a través del
        // sidebar es invisible (confirmado con captura antes/después de
        // Tab) — InkWell por sí solo no dibuja un borde perceptible.
        border: _hasFocus ? Border.all(color: colors.focusRing, width: 2) : null,
      ),
      // Padding horizontal constante a propósito (no condicionado a
      // `collapsed`): si cambiara de golpe junto con la estructura del
      // contenido mientras el ancho del sidebar todavía está animando,
      // reaparece el desborde transitorio que este diseño evita. El margen
      // (más generoso que el padding) es lo que da la sensación de
      // "respiro" entre ítems sin reabrir ese riesgo.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
      child: rowOrIcon,
    );

    Widget child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: content,
    );
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
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: IconButton(
        key: const Key('sidebar_collapse_button'),
        tooltip: collapsed ? l10n.shellExpandSidebarTooltip : l10n.shellCollapseSidebarTooltip,
        icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
        onPressed: onPressed,
      ),
    );
  }
}
