import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../features/finanzas/presentation/finanzas_shell_screen.dart';
import '../../features/inventario/presentation/articulos/articulo_expediente_screen.dart';
import '../../features/inventario/presentation/inventario_shell_screen.dart';
import '../../features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import '../../features/organizacion/presentation/comercial_shell_screen.dart';
import '../../features/organizacion/presentation/organizacion_shell_screen.dart';
import '../../features/organizacion/presentation/puestos/puesto_expediente_screen.dart';
import '../../features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import '../../features/organizacion/presentation/sucursales/sucursal_expediente_screen.dart';
import '../../features/nomina/presentation/nominas/nomina_detalle_screen.dart';
import '../../features/personal/presentation/empleados/empleado_expediente_screen.dart';
import '../../features/personal/presentation/personal_shell_screen.dart';
import '../../features/telefonia/presentation/linea_telefonica_expediente_screen.dart';
import '../../features/telefonia/presentation/lineas_telefonicas_list_screen.dart';
import '../../features/vehiculos/presentation/vehiculo_expediente_screen.dart';
import '../../features/vehiculos/presentation/vehiculos_shell_screen.dart';
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
                  // Organización (Arquitectura Funcional v1.1). Desde la
                  // Etapa 4F.1 ya tiene 2 pestañas reales (Clientes,
                  // Servicios) — `/comercial` en sí ya no muestra nada
                  // directamente, redirige a `/comercial/clientes` (a
                  // diferencia de `/organizacion`, que sí muestra Empresa
                  // en su propia ruta).
                  GoRoute(
                    path: def.path,
                    // Condicionado a la ruta exacta: el `redirect` de un
                    // `GoRoute` se evalúa para toda la cadena de rutas
                    // coincidentes al resolver una ruta anidada (ej.
                    // `/comercial/clientes/:id`), no solo cuando la ruta
                    // navegada es literalmente `/comercial` — sin esta
                    // condición, cualquier sub-ruta (incluida
                    // `/comercial/clientes/:id`) quedaba redirigida de
                    // vuelta a `/comercial/clientes`, perdiendo el `:id`.
                    redirect: (context, state) =>
                        state.uri.path == '/comercial' ? '/comercial/clientes' : null,
                    routes: [
                      GoRoute(
                        path: 'clientes',
                        builder: (context, state) => const ComercialShellScreen(tab: ComercialTab.clientes),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                ClienteExpedienteScreen(clienteId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'servicios',
                        builder: (context, state) => const ComercialShellScreen(tab: ComercialTab.servicios),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                ServicioExpedienteScreen(servicioId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'agenda',
                        // Sin sub-ruta `:id` — el detalle de un
                        // DocumentoPorEmitir se muestra en un diálogo, no
                        // en su propia pantalla (Etapa 4I.1).
                        builder: (context, state) => const ComercialShellScreen(tab: ComercialTab.agenda),
                      ),
                    ],
                  )
                else if (def.path == '/finanzas')
                  // Finanzas es un dominio propio, nuevo, separado de
                  // Organización/Comercial (Etapa 4J.1, Resolución B de
                  // Marlon). `/finanzas` en sí redirige a
                  // `/finanzas/cuentas-por-cobrar` — mismo patrón que
                  // `/comercial`.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/finanzas' ? '/finanzas/cuentas-por-cobrar' : null,
                    routes: [
                      GoRoute(
                        path: 'cuentas-por-cobrar',
                        // Sin sub-ruta `:id` — el detalle de una Cuenta
                        // por cobrar se muestra en un diálogo, no en su
                        // propia pantalla (mismo criterio que la Agenda).
                        builder: (context, state) =>
                            const FinanzasShellScreen(tab: FinanzasTab.cuentasPorCobrar),
                      ),
                      GoRoute(
                        path: 'pagos',
                        // Sin sub-ruta `:id` — el detalle de un Pago se
                        // muestra en un diálogo (Etapa 4J.2), mismo
                        // criterio que Cuentas por cobrar/Agenda.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.pagos),
                      ),
                      GoRoute(
                        path: 'complementos',
                        // Sin sub-ruta `:id` — el detalle de un
                        // Complemento se muestra en un diálogo (Etapa
                        // 4J.3), mismo criterio que Pagos/Agenda.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.complementos),
                      ),
                      GoRoute(
                        path: 'ingresos',
                        // Sin sub-ruta `:id` — el detalle de un Ingreso
                        // se muestra en un diálogo (Etapa 4K.1), mismo
                        // criterio que Pagos/Complementos.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.ingresos),
                      ),
                      GoRoute(
                        path: 'egresos',
                        // Sin sub-ruta `:id` — el detalle de un Egreso
                        // se muestra en un diálogo (Etapa 4K.1), mismo
                        // criterio que Ingresos.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.egresos),
                      ),
                      GoRoute(
                        path: 'categorias',
                        // Catálogo administrable de Categorías
                        // financieras (Etapa 4K.1) — alta/archivado vía
                        // diálogo, sin sub-ruta `:id`.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.categorias),
                      ),
                    ],
                  )
                else if (def.path == '/personal')
                  // Personal es un dominio propio, separado de
                  // Organización/Comercial/Finanzas (Etapa 5A, mismo
                  // criterio que la Resolución B de Marlon para
                  // Finanzas en 4J.1). `/personal` en sí redirige a
                  // `/personal/empleados` — mismo patrón que
                  // `/comercial`/`/finanzas`. Desde la Etapa 6C gana
                  // subnavegación de pestañas (Empleados | Nómina),
                  // mismo patrón `PersonalShellScreen`/`FinanzasShellScreen`.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/personal' ? '/personal/empleados' : null,
                    routes: [
                      GoRoute(
                        path: 'empleados',
                        builder: (context, state) => const PersonalShellScreen(tab: PersonalTab.empleados),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                EmpleadoExpedienteScreen(empleadoId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'nomina',
                        builder: (context, state) => const PersonalShellScreen(tab: PersonalTab.nomina),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                NominaDetalleScreen(nominaId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (def.path == '/inventario')
                  // Inventario es un dominio propio (Etapa 7A). Desde la
                  // Etapa 7D gana subnavegación de pestañas (Artículos |
                  // Reportes), mismo patrón `PersonalShellScreen` —
                  // `/inventario` en sí redirige a `/inventario/articulos`.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/inventario' ? '/inventario/articulos' : null,
                    routes: [
                      GoRoute(
                        path: 'articulos',
                        builder: (context, state) => const InventarioShellScreen(tab: InventarioTab.articulos),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                ArticuloExpedienteScreen(articuloId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'reportes',
                        builder: (context, state) => const InventarioShellScreen(tab: InventarioTab.reportes),
                      ),
                    ],
                  )
                else if (def.path == '/vehiculos')
                  // Vehículos (Etapa 8A) gana subnavegación de pestañas
                  // desde la Etapa 8C (Flotilla | Alertas), mismo
                  // patrón y mismo momento relativo que Inventario
                  // (7A de una sola pantalla → 7D con Reportes) —
                  // `/vehiculos` en sí redirige a `/vehiculos/flotilla`.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/vehiculos' ? '/vehiculos/flotilla' : null,
                    routes: [
                      GoRoute(
                        path: 'flotilla',
                        builder: (context, state) => const VehiculosShellScreen(tab: VehiculosTab.flotilla),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                VehiculoExpedienteScreen(vehiculoId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'alertas',
                        builder: (context, state) => const VehiculosShellScreen(tab: VehiculosTab.alertas),
                      ),
                    ],
                  )
                else if (def.path == '/telefonia')
                  // Telefonía (Etapa 9A) — una sola pantalla, sin
                  // pestañas todavía (mismo criterio que Inventario
                  // 7A/Vehículos 8A: la subnavegación llega cuando
                  // exista una segunda sección real, ver la Etapa 9C).
                  GoRoute(
                    path: def.path,
                    builder: (context, state) => const LineasTelefonicasListScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            LineaTelefonicaExpedienteScreen(lineaTelefonicaId: state.pathParameters['id']!),
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
