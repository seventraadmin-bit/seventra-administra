// Mapeo ruta del Shell → permisos que la abren (Etapa 11B, ampliado en
// la Etapa "Usuarios, permisos y UX de seguridad").
//
// Fuente única usada tanto por el filtrado del sidebar
// (`app_shell_screen.dart`) como por el `redirect` del router
// (`app_router.dart`) — evita que ambos lugares puedan divergir sobre
// qué permiso protege qué ruta. Divergieron una vez, precisamente
// porque cada uno llamaba a una función distinta de este archivo: el
// sidebar a `permisosQueAbrenRuta` y el router a
// `permisoRequeridoParaRuta`. Ahora los dos usan la primera.
//
// `/configuracion` es el caso especial: no tiene una acción `ver`
// propia en el catálogo (`modulosPermiso` no incluye
// `'configuracion'`), y sus pestañas ya no comparten un mismo dueño.

/// Códigos que ABREN una ruta — basta tener CUALQUIERA (Etapa
/// "Usuarios, permisos y UX de seguridad"). Lista vacía = ruta abierta a
/// cualquier sesión válida.
///
/// Existe porque `/configuracion` dejó de tener un único dueño: sus
/// pestañas ya no comparten permiso (Usuarios exige
/// `usuarios.administrar`, Auditoría solo `auditoria.ver`), así que la
/// raíz debe abrirse para quien pueda entrar a AL MENOS una de ellas.
/// Sin esto, alguien con solo `auditoria.ver` quedaba fuera de la
/// sección entera y no podía llegar a la única pestaña que sí le
/// correspondía.
List<String> permisosQueAbrenRuta(String path) {
  if (path == '/dashboard') return const [];
  if (path == '/configuracion/auditoria') return const ['auditoria.ver'];
  if (path == '/configuracion') return const ['usuarios.administrar', 'auditoria.ver'];
  if (path.startsWith('/configuracion/')) return const ['usuarios.administrar'];

  final segmento = path.startsWith('/') ? path.substring(1) : path;
  return ['${segmento.split('/').first}.ver'];
}

/// Compatibilidad con el criterio de un solo código — devuelve el
/// primero de [permisosQueAbrenRuta]. Úsala solo donde de verdad basta
/// uno; para decidir acceso, `permisosQueAbrenRuta` es la correcta.
String? permisoRequeridoParaRuta(String path) {
  if (path == '/dashboard') return null;
  // Etapa "Usuarios, permisos y UX de seguridad": Auditoría deja de
  // exigir `usuarios.administrar`. Consultar quién hizo qué es una
  // facultad de solo lectura, independiente de poder crear o editar
  // cuentas — antes cada una implicaba la otra.
  if (path == '/configuracion/auditoria') return 'auditoria.ver';
  if (path == '/configuracion' || path.startsWith('/configuracion/')) return 'usuarios.administrar';

  final segmento = path.startsWith('/') ? path.substring(1) : path;
  final modulo = segmento.split('/').first;
  return '$modulo.ver';
}
