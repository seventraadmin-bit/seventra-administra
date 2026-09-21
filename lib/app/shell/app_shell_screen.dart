import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/usuarios/usuarios_providers.dart';
import 'shell_destinations.dart';
import 'shell_permissions.dart';
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
///
/// Etapa 11B: las ramas del `StatefulShellRoute` siguen siendo las 11
/// completas — no se pueden quitar dinámicamente (se arman una sola vez,
/// sin `BuildContext`, ver `app_router.dart`). Lo que sí es dinámico es
/// qué subconjunto se **muestra** en el sidebar, así que aquí se filtra
/// la lista completa por permiso y se remapea cada índice mostrado a su
/// índice real de rama antes de navegar — `AppSidebar` en sí no sabe
/// nada de permisos, sigue recibiendo una lista de destinos + índice
/// activo ya resueltos.
class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final allDestinations = buildShellDestinations(l10n);
    final permissionService = ref.watch(permissionServiceProvider);
    final mode = ref.watch(sidebarModeControllerProvider);

    final visibleDestinations = <ShellDestination>[];
    final visibleToRealIndex = <int>[];
    for (var i = 0; i < allDestinations.length; i++) {
      // Basta CUALQUIERA de los códigos que abren la ruta — desde que
      // Auditoría se separó, `/configuracion` tiene más de un dueño.
      final permisosQueAbren = permisosQueAbrenRuta(allDestinations[i].path);
      if (permisosQueAbren.isEmpty || permisosQueAbren.any(permissionService.hasCode)) {
        visibleDestinations.add(allDestinations[i]);
        visibleToRealIndex.add(i);
      }
    }

    final activeRealIndex = navigationShell.currentIndex;
    // -1 solo podría darse si el `redirect` del router dejara pasar una
    // rama sin permiso (no debería ocurrir — es la misma función
    // `permisoRequeridoParaRuta` la que gatea ahí) — Dashboard (sin
    // permiso propio) siempre está en la lista visible en la posición 0,
    // así que es el resguardo seguro.
    final activeVisibleIndexRaw = visibleToRealIndex.indexOf(activeRealIndex);
    final activeVisibleIndex = activeVisibleIndexRaw == -1 ? 0 : activeVisibleIndexRaw;
    final activeDestination = allDestinations[activeRealIndex];

    return Scaffold(
      key: const Key('app_shell'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final collapsed = resolveSidebarCollapsed(
            mode: mode,
            availableWidth: constraints.maxWidth,
            availableHeight: constraints.maxHeight,
          );

          return Row(
            children: [
              AppSidebar(
                destinations: visibleDestinations,
                activeIndex: activeVisibleIndex,
                collapsed: collapsed,
                onDestinationSelected: (index) {
                  final realIndex = visibleToRealIndex[index];
                  navigationShell.goBranch(realIndex, initialLocation: realIndex == navigationShell.currentIndex);
                },
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
                        // Etapa 16, evolución visual: `scaffoldBackgroundColor`
                        // (= `colors.canvas`), NUNCA `colorScheme.surface` —
                        // jerarquía de 3 niveles (Shell azul / sidebar y topbar
                        // en `surface` / área de trabajo en `canvas`, un tono
                        // ligeramente distinto). Las tarjetas/tablas de cada
                        // pantalla siguen usando `surface` por su cuenta, así
                        // que quedan visualmente separadas del fondo.
                        color: Theme.of(context).scaffoldBackgroundColor,
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
