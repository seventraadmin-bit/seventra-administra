import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../features/compras/presentation/compra_expediente_screen.dart';
import '../../features/descuentos_personal/presentation/descuento_programado_detalle_screen.dart';
import '../../features/tiempos_extra/presentation/tiempo_extra_detalle_screen.dart';
import '../../features/compras/presentation/corregir_compra_screen.dart';
import '../../features/compras/presentation/compras_list_screen.dart';
import '../../features/compras/presentation/registrar_compra_screen.dart';
import '../../features/finanzas/presentation/cuentas_financieras/cuenta_financiera_expediente_screen.dart';
import '../../features/finanzas/presentation/deudas_credito/deuda_expediente_screen.dart';
import '../../features/finanzas/presentation/finanzas_shell_screen.dart';
import '../../features/inventario/presentation/articulos/articulo_expediente_screen.dart';
import '../../features/inventario/presentation/inventario_shell_screen.dart';
import '../../features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import '../../features/organizacion/presentation/comercial_shell_screen.dart';
import '../../features/servicios_eventuales/presentation/servicio_eventual_expediente_screen.dart';
import '../../features/organizacion/presentation/organizacion_shell_screen.dart';
import '../../features/organizacion/presentation/puestos/puesto_expediente_screen.dart';
import '../../features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import '../../features/organizacion/presentation/areas/area_expediente_screen.dart';
import '../../features/organizacion/presentation/sucursales/sucursal_expediente_screen.dart';
import '../../features/nomina/presentation/nominas/nomina_detalle_screen.dart';
import '../../features/personal/presentation/empleados/conciliar_baja_empleado_screen.dart';
import '../../features/personal/presentation/empleados/empleado_expediente_screen.dart';
import '../../features/personal/presentation/personal_shell_screen.dart';
import '../../features/reportes/presentation/reportes_shell_screen.dart';
import '../../features/telefonia/presentation/equipo_telefonico_expediente_screen.dart';
import '../../features/telefonia/presentation/linea_telefonica_expediente_screen.dart';
import '../../features/telefonia/presentation/telefonia_shell_screen.dart';
import '../../features/usuarios/presentation/auth/bootstrap_maestro_screen.dart';
import '../../features/usuarios/presentation/auth/cambio_obligatorio_password_screen.dart';
import '../../features/usuarios/presentation/auth/login_screen.dart';
import '../../features/usuarios/presentation/configuracion_shell_screen.dart';
import '../../features/usuarios/presentation/sesion_controller.dart';
import '../../features/usuarios/usuarios_providers.dart';
import '../../features/vehiculos/presentation/vehiculo_expediente_screen.dart';
import '../../features/vehiculos/presentation/vehiculos_shell_screen.dart';
import '../dev/design_system_catalog_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../shell/acceso_denegado_screen.dart';
import '../shell/app_shell_screen.dart';
import '../shell/module_placeholder_screen.dart';
import '../shell/shell_destinations.dart';
import '../shell/shell_permissions.dart';

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
    // Además del `/` → `/dashboard` de siempre, exige el bootstrap del
    // primer Maestro y la sesión antes de cualquier otra ruta (Etapa
    // 11A), y desde la Etapa 11B también el permiso `<modulo>.ver` de
    // cada ruta de módulo (`permisoRequeridoParaRuta`, fuente única
    // compartida con el filtrado del sidebar en `app_shell_screen.dart`).
    // `ProviderScope.containerOf(context)` es el patrón estándar para
    // leer providers de Riverpod desde un callback de GoRouter que solo
    // recibe `BuildContext` — sin esto no hay forma de consultar
    // `contarUsuariosProvider`/`sesionControllerProvider`/
    // `permissionServiceProvider` aquí.
    redirect: (context, state) async {
      final container = ProviderScope.containerOf(context);
      final path = state.uri.path;

      final totalUsuarios = await container.read(contarUsuariosProvider.future);
      if (totalUsuarios == 0) {
        return path == '/bootstrap-maestro' ? null : '/bootstrap-maestro';
      }
      if (path == '/bootstrap-maestro') return '/login';

      // Etapa 3B — revalidación central de la sesión viva. Es el único
      // punto del proyecto donde una sesión ya abierta puede dejar de
      // estar autorizada, y está aquí por dos razones: este `redirect`
      // ya corre en CADA navegación y ya es asíncrono, así que no hace
      // falta ni un temporizador ni un observador nuevo; y corre
      // ANTES de construir cualquier pantalla, así que una cuenta
      // desactivada no alcanza a ver nada.
      //
      // Va justo antes de leer la sesión, nunca después: si la cuenta
      // dejó de estar activa, `revalidar()` deja el estado en `null` y
      // la comprobación de las líneas siguientes —la de siempre— manda
      // a `/login` en esta misma evaluación.
      //
      // Coste: dos consultas por clave primaria sobre SQLite local. Lo
      // que compra es que desactivar una cuenta (a mano o por una baja
      // laboral) y cambiar permisos surtan efecto sin cerrar sesión.
      await container.read(sesionControllerProvider.notifier).revalidar();

      final sesion = container.read(sesionControllerProvider);
      if (sesion == null) {
        return path == '/login' ? null : '/login';
      }
      // Cambio obligatorio de contraseña (Etapa "Usuarios, permisos y UX
      // de seguridad") — va ANTES de cualquier otra decisión de ruta,
      // incluidos los permisos: una contraseña temporal la conoce quien
      // la fijó, así que la sesión existe pero no opera hasta cambiarla.
      // Se resuelve aquí, en el `redirect`, y no con un diálogo del
      // Shell, por la misma razón que los permisos: ninguna pantalla del
      // sistema llega siquiera a construirse.
      if (sesion.debeCambiarPassword) {
        return path == '/cambiar-contrasena' ? null : '/cambiar-contrasena';
      }
      if (path == '/cambiar-contrasena') return '/dashboard';

      if (path == '/login' || path == '/') return '/dashboard';

      // Herramienta solo de desarrollo (ni siquiera se registra fuera de
      // `Env.dev` — ver más abajo) — no tiene módulo ni permiso propio.
      if (path.startsWith('/dev/')) return null;

      // Semántica "cualquiera de estos abre la ruta" (Etapa "Usuarios,
      // permisos y UX de seguridad"): `/configuracion` la abren tanto
      // `usuarios.administrar` como `auditoria.ver`, y `auditoria.ver`
      // existe justamente para ver la auditoría SIN poder administrar
      // cuentas. El `redirect` usaba `permisoRequeridoParaRuta`, que se
      // queda con el PRIMER código de la lista — así que el sidebar ya
      // le mostraba Configuración a un usuario con solo `auditoria.ver`
      // y el router se la negaba al entrar. Misma fuente que el sidebar
      // (`app_shell_screen.dart`), ahora con la misma semántica.
      final permisosQueAbren = permisosQueAbrenRuta(path);
      if (permisosQueAbren.isNotEmpty && !permisosQueAbren.any(container.read(permissionServiceProvider).hasCode)) {
        // Nunca construye ni muestra contenido del módulo protegido, ni
        // brevemente — el `redirect` corre antes de que esa ruta llegue
        // a construirse.
        return path == '/acceso-denegado' ? null : '/acceso-denegado';
      }

      // Respaldo y restauración (Etapa 14C) y Bóveda de Accesos (Etapa
      // 14D) son exclusivas del Usuario Maestro — `usuarios.administrar`
      // (el permiso de todo `/configuracion`) no basta, igual que ningún
      // permiso dinámico basta para la eliminación física de la Etapa
      // 11D. Doble candado con `exigirMaestro` en
      // `respaldo_providers.dart`/`boveda_providers.dart`: aquí se evita
      // incluso construir la pantalla, allá se protege la acción aunque
      // se invoque sin pasar por esta ruta.
      if ((path == '/configuracion/respaldo' || path == '/configuracion/boveda') && !sesion.esMaestro) {
        return '/acceso-denegado';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/bootstrap-maestro', builder: (context, state) => const BootstrapMaestroScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/acceso-denegado', builder: (context, state) => const AccesoDenegadoScreen()),
      // Fuera del `StatefulShellRoute` a propósito, igual que `/login`:
      // sin sidebar ni barra superior, no hay a dónde ir desde aquí.
      GoRoute(path: '/cambiar-contrasena', builder: (context, state) => const CambioObligatorioPasswordScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShellScreen(navigationShell: navigationShell),
        branches: [
          for (final def in shellModuleDefs)
            StatefulShellBranch(
              routes: [
                if (def.path == '/organizacion')
                  // Organización tiene subnavegación propia (Empresa |
                  // Sucursales | Puestos | Áreas) desde la Etapa 4D.
                  // `/organizacion` en sí solo redirige a
                  // `/organizacion/empresa` — mismo patrón que
                  // `/comercial`/`/finanzas`/`/personal`/`/inventario`
                  // (padre sin `builder` propio, las 4 pestañas como
                  // rutas hermanas planas). Corregido en la Etapa 15:
                  // antes `/organizacion` tenía su propio `builder`
                  // (Empresa) *y* rutas hijas — eso hacía que go_router
                  // mantuviera varias instancias de `OrganizacionShellScreen`
                  // vivas a la vez (una por nivel de ruta coincidente) y
                  // desincronizaba la pestaña marcada del contenido
                  // realmente visible.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/organizacion' ? '/organizacion/empresa' : null,
                    routes: [
                      GoRoute(
                        path: 'empresa',
                        builder: (context, state) => const OrganizacionShellScreen(tab: OrganizacionTab.empresa),
                      ),
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
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) => AreaExpedienteScreen(areaId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (def.path == '/comercial')
                  // Comercial es un dominio propio, separado de
                  // Organización (Arquitectura Funcional v1.1). Desde la
                  // Etapa 4F.1 ya tiene 2 pestañas reales (Clientes,
                  // Servicios) — `/comercial` en sí ya no muestra nada
                  // directamente, redirige a `/comercial/clientes` (mismo
                  // patrón que `/organizacion` desde la Etapa 15).
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
                        //
                        // `?filtro=pendientes` (Dashboard → "Documentos por
                        // emitir pendientes"): la ruta basta para
                        // reconstruir la vista, sin depender de estado del
                        // Dashboard. Mismo precedente que
                        // `?filtro=sinAsignar` en Personal.
                        builder: (context, state) => ComercialShellScreen(
                          tab: ComercialTab.agenda,
                          agendaModoPendientes: state.uri.queryParameters['filtro'] == 'pendientes',
                        ),
                      ),
                      GoRoute(
                        path: 'eventuales',
                        builder: (context, state) => const ComercialShellScreen(tab: ComercialTab.eventuales),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) => ServicioEventualExpedienteScreen(
                              servicioEventualId: state.pathParameters['id']!,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (def.path == '/finanzas')
                  // Finanzas es un dominio propio, nuevo, separado de
                  // Organización/Comercial (Etapa 4J.1, Resolución B de
                  // Marlon). `/finanzas` en sí redirige a
                  // `/finanzas/resumen` (Etapa 17: portada ejecutiva,
                  // antes redirigía a Cuentas por cobrar) — mismo
                  // patrón que `/comercial`.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/finanzas' ? '/finanzas/resumen' : null,
                    routes: [
                      GoRoute(
                        path: 'resumen',
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.resumen),
                      ),
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
                      GoRoute(
                        path: 'deudas-y-credito',
                        // Con sub-ruta `:id` (Etapa 19) — a diferencia
                        // del resto de Finanzas, el expediente de una
                        // Deuda es una pantalla propia, no un diálogo:
                        // la vista de tarjeta + historial + pagos +
                        // egresos vinculados no cabe cómodo en un
                        // `RisegDialog`, mismo criterio que Compras.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.deudasYCredito),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) => DeudaExpedienteScreen(deudaId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'cuentas-financieras',
                        // Con sub-ruta `:id` (Etapa 19C) — mismo
                        // criterio exacto que `deudas-y-credito`: el
                        // expediente (saldo + historial unificado
                        // Ingreso/Egreso) no cabe cómodo en un
                        // `RisegDialog`.
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.cuentasFinancieras),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                CuentaFinancieraExpedienteScreen(cuentaId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'planeacion',
                        // Sin sub-ruta `:id` (Etapa 19D) — no es un
                        // expediente propio, es la portada de
                        // calendario/gráfica/resumen semanal; cada
                        // compromiso navega a su expediente REAL
                        // (CxC → diálogo, Nómina/Deuda → su propia
                        // pantalla ya existente).
                        builder: (context, state) => const FinanzasShellScreen(tab: FinanzasTab.planeacion),
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
                        // `?filtro=sinAsignar` (Etapa 20, Dashboard →
                        // Personal "Sin asignar") — único query param
                        // real que este Shell soporta hoy.
                        builder: (context, state) => PersonalShellScreen(
                          tab: PersonalTab.empleados,
                          filtroInicialSinAsignar: state.uri.queryParameters['filtro'] == 'sinAsignar',
                        ),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                EmpleadoExpedienteScreen(empleadoId: state.pathParameters['id']!),
                            routes: [
                              // La baja dejó de caber en un diálogo: ahora
                              // concilia todo el resguardo de la persona.
                              GoRoute(
                                path: 'baja',
                                builder: (context, state) =>
                                    ConciliarBajaEmpleadoScreen(empleadoId: state.pathParameters['id']!),
                              ),
                            ],
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
                      GoRoute(
                        path: 'descuentos',
                        builder: (context, state) => const PersonalShellScreen(tab: PersonalTab.descuentos),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                DescuentoProgramadoDetalleScreen(descuentoProgramadoId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'tiempos-extra',
                        builder: (context, state) => const PersonalShellScreen(tab: PersonalTab.tiemposExtra),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                TiempoExtraDetalleScreen(tiempoExtraId: state.pathParameters['id']!),
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
                  // Telefonía (Etapa 9A) gana subnavegación de pestañas
                  // desde la Etapa 9D (Equipos | Líneas), mismo patrón y
                  // mismo momento relativo que Inventario (7A → 7D) /
                  // Vehículos (8A → 8C) — `/telefonia` en sí redirige a
                  // `/telefonia/equipos`. Líneas ya existía como
                  // pantalla única desde la Etapa 9A y se mueve de ruta
                  // (antes `/telefonia/:id`, ahora
                  // `/telefonia/lineas/:id`) sin cambios de contenido.
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) =>
                        state.uri.path == '/telefonia' ? '/telefonia/equipos' : null,
                    routes: [
                      GoRoute(
                        path: 'equipos',
                        builder: (context, state) => const TelefoniaShellScreen(tab: TelefoniaTab.equipos),
                        routes: [
                          GoRoute(
                            path: ':unidadId',
                            builder: (context, state) =>
                                EquipoTelefonicoExpedienteScreen(unidadId: state.pathParameters['unidadId']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'lineas',
                        builder: (context, state) => const TelefoniaShellScreen(tab: TelefoniaTab.lineas),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (context, state) =>
                                LineaTelefonicaExpedienteScreen(lineaTelefonicaId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (def.path == '/compras')
                  // Compras (Etapa 10) — una sola pantalla, sin
                  // pestañas todavía (mismo criterio que Inventario
                  // 7A/Vehículos 8A/Telefonía 9A). "Registrar compra"
                  // es una pantalla completa propia (`/compras/nueva`),
                  // no un diálogo modal — el volumen potencial de
                  // partidas y captura de números de serie no cabe
                  // cómodo en un `RisegDialog` pequeño.
                  GoRoute(
                    path: def.path,
                    builder: (context, state) => const ComprasListScreen(),
                    routes: [
                      GoRoute(
                        path: 'nueva',
                        builder: (context, state) => const RegistrarCompraScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => CompraExpedienteScreen(compraId: state.pathParameters['id']!),
                        routes: [
                          GoRoute(
                            path: 'corregir',
                            builder: (context, state) => CorregirCompraScreen(compraId: state.pathParameters['id']!),
                          ),
                        ],
                      ),
                    ],
                  )
                else if (def.path == '/reportes')
                  // Reportes generales (Etapa 12A) — mismo patrón que
                  // Finanzas/Configuración: `/reportes` en sí redirige
                  // a `/reportes/general`. La visibilidad de cada
                  // pestaña por permiso vive en `ReportesShellScreen`,
                  // no aquí (`permisoRequeridoParaRuta` solo exige
                  // `reportes.ver` para cualquier subruta — la barrera
                  // real por dominio vive en el controller de cada
                  // pestaña, ver `reportes_permisos.dart`).
                  GoRoute(
                    path: def.path,
                    redirect: (context, state) => state.uri.path == '/reportes' ? '/reportes/general' : null,
                    routes: [
                      GoRoute(
                        path: 'general',
                        builder: (context, state) => const ReportesShellScreen(tab: ReportesTab.general),
                      ),
                      GoRoute(
                        path: 'finanzas',
                        builder: (context, state) => const ReportesShellScreen(tab: ReportesTab.finanzas),
                      ),
                      GoRoute(
                        path: 'personal-nomina',
                        builder: (context, state) => const ReportesShellScreen(tab: ReportesTab.personalNomina),
                      ),
                      GoRoute(
                        path: 'operacion',
                        builder: (context, state) => const ReportesShellScreen(tab: ReportesTab.operacion),
                      ),
                      GoRoute(
                        path: 'patrimonio',
                        builder: (context, state) => const ReportesShellScreen(tab: ReportesTab.patrimonio),
                      ),
                    ],
                  )
                else if (def.path == '/configuracion')
                  // Configuración (Etapa 11A: Usuarios; Etapa 11D:
                  // Auditoría) gana subnavegación de pestañas, mismo
                  // patrón y mismo momento relativo que Inventario (7A
                  // → 7D) / Vehículos (8A → 8C) — `/configuracion` en
                  // sí redirige a `/configuracion/usuarios`.
                  GoRoute(
                    path: def.path,
                    // La raíz no tiene pantalla propia: manda a la
                    // primera pestaña que ESTA sesión puede abrir.
                    // Redirigir siempre a Usuarios dejaba a quien solo
                    // tiene `auditoria.ver` rebotando a
                    // `/acceso-denegado`: veía la sección en el sidebar
                    // y no llegaba a la única pestaña que sí le
                    // correspondía (Etapa "Usuarios, permisos y UX de
                    // seguridad").
                    redirect: (context, state) {
                      if (state.uri.path != '/configuracion') return null;
                      final permisos = ProviderScope.containerOf(context).read(permissionServiceProvider);
                      if (permisos.hasCode('usuarios.administrar')) return '/configuracion/usuarios';
                      if (permisos.hasCode('auditoria.ver')) return '/configuracion/auditoria';
                      // Sin ninguno de los dos, el `redirect` raíz ya
                      // negó el acceso antes de llegar aquí.
                      return '/configuracion/usuarios';
                    },
                    routes: [
                      GoRoute(
                        path: 'usuarios',
                        builder: (context, state) =>
                            const ConfiguracionShellScreen(tab: ConfiguracionTab.usuarios),
                      ),
                      GoRoute(
                        path: 'auditoria',
                        builder: (context, state) =>
                            const ConfiguracionShellScreen(tab: ConfiguracionTab.auditoria),
                      ),
                      GoRoute(
                        path: 'respaldo',
                        builder: (context, state) =>
                            const ConfiguracionShellScreen(tab: ConfiguracionTab.respaldo),
                      ),
                      GoRoute(
                        path: 'boveda',
                        builder: (context, state) =>
                            const ConfiguracionShellScreen(tab: ConfiguracionTab.boveda),
                      ),
                    ],
                  )
                else
                  GoRoute(
                    path: def.path,
                    builder: (context, state) {
                      // El Dashboard es la pantalla de inicio real del
                      // producto, no un módulo pendiente — tiene su
                      // propia pantalla en vez del placeholder genérico
                      // (Etapa 13: dinámica por permisos, ya no una
                      // bienvenida estática).
                      if (def.path == '/dashboard') {
                        return const DashboardScreen();
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
