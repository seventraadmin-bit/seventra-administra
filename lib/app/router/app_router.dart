import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../dev/design_system_catalog_screen.dart';
import '../shell/app_shell_screen.dart';
import '../shell/dashboard_welcome_screen.dart';
import '../shell/module_placeholder_screen.dart';
import '../shell/shell_destinations.dart';

/// Construye la configuración de rutas de RISEG ONE.
///
/// Es una función (no una instancia global `final`) deliberadamente: un
/// `GoRouter` guarda estado de navegación mutable, y una sola instancia
/// global compartida entre pruebas hace que el estado de una prueba se
/// filtre a la siguiente. Cada `main.dart`/prueba debe crear la suya con
/// [createAppRouter].
///
/// Un `StatefulShellRoute.indexedStack` con una rama por cada uno de los
/// 10 destinos del Shell — cada rama conserva su propia navegación interna
/// y queda preparada para rutas anidadas (hoy solo tiene el placeholder).
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) => state.uri.path == '/' ? '/dashboard' : null,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShellScreen(navigationShell: navigationShell),
        branches: [
          for (final def in shellModuleDefs)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: def.path,
                  builder: (context, state) {
                    // El Dashboard es la pantalla de inicio real del
                    // producto, no un módulo pendiente — tiene su propia
                    // pantalla en vez del placeholder genérico.
                    if (def.path == '/dashboard') {
                      return const DashboardWelcomeScreen();
                    }
                    final l10n = AppLocalizations.of(context)!;
                    final destinations = buildShellDestinations(l10n);
                    return ModulePlaceholderScreen(
                      destination: destinationForPath(destinations, def.path),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
      // Solo se registra en desarrollo: la ruta ni siquiera existe en un
      // build de producción, no solo queda oculta del sidebar.
      if (Env.resolve().isDev)
        GoRoute(
          path: '/dev/design-system',
          builder: (context, state) => const DesignSystemCatalogScreen(),
        ),
    ],
  );
}
