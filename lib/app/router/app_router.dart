import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import '../../features/organizacion/presentation/clientes/clientes_list_screen.dart';
import '../../features/organizacion/presentation/organizacion_shell_screen.dart';
import '../../features/organizacion/presentation/puestos/puesto_expediente_screen.dart';
import '../../features/organizacion/presentation/sucursales/sucursal_expediente_screen.dart';
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
/// 11 destinos del Shell — cada rama conserva su propia navegación interna
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
                if (def.path == '/organizacion')
                  // Organización tiene subnavegación propia (Empresa |
                  // Sucursales | Puestos | Áreas) desde la Etapa 4D —
                  // `/organizacion` en sí sigue mostrando Empresa por
                  // defecto (compatibilidad con la Etapa 4B).
                  GoRoute(
                    path: def.path,
                    builder: (context, state) => const OrganizacionShellScreen(tab: OrganizacionTab.empresa),
                    routes: [
                      GoRoute(
                        path: 'sucursales',
                        builder: (context, state) => const OrganizacionShellScreen(tab: OrganizacionTab.sucursales),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                SucursalExpedienteScreen(sucursalId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'puestos',
                        builder: (context, state) => const OrganizacionShellScreen(tab: OrganizacionTab.puestos),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                PuestoExpedienteScreen(puestoId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'areas',
                        builder: (context, state) => const OrganizacionShellScreen(tab: OrganizacionTab.areas),
                      ),
                    ],
                  )
                else if (def.path == '/comercial')
                  // Comercial es un dominio propio, separado de
                  // Organización (Arquitectura Funcional v1.1). Por ahora
                  // `/comercial` muestra el listado de Clientes
                  // directamente, sin `RisegTabs` — mismo criterio que
                  // Organización antes de la Etapa 4C: no se introduce un
                  // shell de pestañas hasta que exista una segunda
                  // pestaña real (Servicios, Etapa 4F).
                  GoRoute(
                    path: def.path,
                    builder: (context, state) => const ClientesListScreen(),
                    routes: [
                      GoRoute(
                        path: 'clientes/:id',
                        builder: (context, state) =>
                            ClienteExpedienteScreen(clienteId: state.pathParameters['id']!),
                      ),
                    ],
                  )
                else
                  GoRoute(
                    path: def.path,
                    builder: (context, state) {
                      // El Dashboard es la pantalla de inicio real del
                      // producto, no un módulo pendiente — tiene su
                      // propia pantalla en vez del placeholder genérico.
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
