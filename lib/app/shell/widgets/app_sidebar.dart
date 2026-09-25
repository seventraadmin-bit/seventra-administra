import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/branding/marca_producto.dart';
import '../../../core/design_system/tokens/app_color_scheme.dart';
import '../../../core/design_system/tokens/app_spacing.dart';
import '../shell_breakpoints.dart';
import '../shell_destinations.dart';

/// Sidebar persistente del Shell.
///
/// Widget de presentación puro: no lee providers directamente — recibe
/// [collapsed] ya resuelto y notifica [onToggleCollapse]/[onDestinationSelected]
/// hacia arriba. Así se puede probar y reutilizar sin depender de Riverpod.
class AppSidebar extends StatefulWidget {
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
  State<AppSidebar> createState() => _AppSidebarState();
}

/// `StatefulWidget` únicamente por el `ScrollController` de la zona de
/// navegación: `Scrollbar` y su `ListView` deben compartir exactamente
/// el mismo controller (creado una sola vez aquí, nunca dentro de
/// `build()`) — ver el doc comment de nivel de archivo/prueba de
/// regresión en `test/app/shell/widgets/app_sidebar_test.dart` para el
/// porqué exacto: sin un controller explícito compartido, en
/// plataformas de escritorio el `Scrollbar` y el `ListView` terminan
/// resolviendo cada uno un controller distinto (el `Scrollbar` cae en
/// el `PrimaryScrollController` ambiental de la página; el `ListView`
/// no lo hereda porque `PrimaryScrollController.shouldInherit` solo lo
/// hace por defecto en plataformas móviles), y el del `Scrollbar` nunca
/// tiene una `ScrollPosition` adjunta.
class _AppSidebarState extends State<AppSidebar> {
  final _navScrollController = ScrollController();

  @override
  void dispose() {
    _navScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColorScheme>()!;

    return AnimatedContainer(
      key: const Key('app_sidebar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: widget.collapsed ? ShellBreakpoints.sidebarCollapsedWidth : ShellBreakpoints.sidebarExpandedWidth,
      decoration: BoxDecoration(
        // Tinta en claro y en oscuro: el sidebar viste la marca, no el tema.
        color: colors.shellSurface,
        border: Border(right: BorderSide(color: colors.shellOverlaySubtle)),
      ),
      child: Column(
        children: [
          // Branding: siempre fijo, nunca entra en el área con scroll —
          // Resolución explícita de Marlon (Etapa 3B, revisión de
          // navegación): ningún destino debe volverse inaccesible por
          // altura de ventana reducida.
          _SidebarHeader(collapsed: widget.collapsed),
          Divider(height: 1, color: colors.shellOverlaySubtle),
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
          //
          // `Scrollbar` y `ListView` comparten explícitamente
          // `_navScrollController` — un `Scrollbar` con `thumbVisibility:
          // true` necesita conocer la `ScrollPosition` de inmediato para
          // poder pintar el thumb, y sin un controller común ambos
          // widgets pueden terminar resolviendo controllers distintos en
          // plataformas de escritorio (ver el doc comment de la clase de
          // estado, arriba).
          Expanded(
            child: Scrollbar(
              controller: _navScrollController,
              thumbVisibility: true,
              child: ListView(
                key: const Key('app_sidebar_nav_scroll'),
                controller: _navScrollController,
                padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                children: [
                  for (var index = 0; index < widget.destinations.length; index++)
                    _SidebarItem(
                      destination: widget.destinations[index],
                      isActive: index == widget.activeIndex,
                      collapsed: widget.collapsed,
                      onTap: () => widget.onDestinationSelected(index),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.shellOverlaySubtle),
          _CollapseButton(collapsed: widget.collapsed, onPressed: widget.onToggleCollapse),
        ],
      ),
    );
  }
}

/// Encabezado del sidebar con la marca del **producto** (Etapa 5B.1).
///
/// Desplegado muestra el logotipo completo `SEVENTRA Administra`;
/// colapsado, la marca cuadrada. No es una decisión estética: el logotipo
/// mide 1715×280 y a 40 px de alto ocuparía 245 px de ancho en un raíl de
/// 80. El escudo anterior era cuadrado y servía para las dos anchuras; éste
/// no, así que cada estado usa el archivo que le corresponde.
///
/// Ya no se dibuja `l10n.appTitle` ni `l10n.appSubtitle` debajo: el logotipo
/// **es** el nombre del producto, y "Sistema Integral Administrativo" hacía
/// que la identidad nueva pareciera un retoque de la anterior.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xl),
        child: Tooltip(
          message: l10n.appTitle,
          child: const IconoProducto(key: Key('sidebar_logo'), lado: 40),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        children: [
          // Blanco siempre: el sidebar es tinta en los dos temas. Sin ancho
          // fijo, ocupa el que deje el padding, así que tiene la presencia de
          // la referencia sin deformarse ni salirse.
          LogotipoProducto(key: Key('sidebar_logo'), sobreFondoOscuro: true),
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
  bool _hovered = false;

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
      color: isActive ? colors.shellForeground : colors.shellForegroundMuted,
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
                    color: isActive ? colors.shellForeground : colors.shellForegroundMuted,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          );

    final content = Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: isActive
            ? colors.shellOverlayStrong
            : (_hovered ? colors.shellOverlaySubtle : null),
        borderRadius: BorderRadius.circular(8),
        // Anillo de foco de teclado explícito: sin esto, Tab a través del
        // sidebar es invisible (confirmado con captura antes/después de
        // Tab) — InkWell por sí solo no dibuja un borde perceptible.
        border: _hasFocus ? Border.all(color: colors.shellFocusRing, width: 2) : null,
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

    // `hoverColor`/`splashColor`/`highlightColor` transparentes — el
    // fondo de hover ya lo pinta `content` explícitamente arriba (mismo
    // criterio que `RisegTableBase`), para no encimar el velo propio de
    // `InkWell` sobre el fondo azul-suave ya calculado.
    Widget child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      onHover: (hovered) => setState(() => _hovered = hovered),
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
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
