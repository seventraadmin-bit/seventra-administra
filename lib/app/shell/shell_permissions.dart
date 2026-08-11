/// Mapeo ruta del Shell → código de permiso requerido (Etapa 11B).
///
/// Fuente única usada tanto por el filtrado del sidebar
/// (`app_shell_screen.dart`) como por el `redirect` del router
/// (`app_router.dart`) — evita que ambos lugares puedan divergir sobre
/// qué permiso protege qué ruta.
///
/// `null` significa "sin permiso propio, cualquier sesión válida
/// entra" — hoy solo `/dashboard` (punto 9 del plan de la Etapa 11B).
/// `/configuracion` es el único caso especial: no tiene una acción
/// `ver` propia en el catálogo (`modulosPermiso` no incluye
/// `'configuracion'`) — está gateado explícitamente por
/// `usuarios.administrar` (punto 10 del plan), el mismo permiso que
/// controla el acceso a "Configuración → Usuarios".
String? permisoRequeridoParaRuta(String path) {
  if (path == '/dashboard') return null;
  if (path == '/configuracion') return 'usuarios.administrar';

  final segmento = path.startsWith('/') ? path.substring(1) : path;
  final modulo = segmento.split('/').first;
  return '$modulo.ver';
}
