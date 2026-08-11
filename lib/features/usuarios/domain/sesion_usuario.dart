/// Sesión activa — todo lo que la app necesita saber sobre quién está
/// usándola ahora mismo.
///
/// `permisos` (Etapa 11B) se calcula una sola vez, en el momento del
/// login (`LoginUseCase`): para un Maestro, el catálogo completo
/// (`todosLosCodigosDePermiso()`); para cualquier otro, sus
/// `PermisoUsuario` reales. **No se refresca en vivo**: si un Maestro
/// cambia los permisos de un usuario con sesión ya abierta, esa sesión
/// sigue viendo el conjunto con el que inició hasta su siguiente login
/// — decisión deliberada por simplicidad y previsibilidad (ver el plan
/// de la Etapa 11B, punto 12); no hay sincronización multiusuario en
/// tiempo real todavía.
class SesionUsuario {
  const SesionUsuario({
    required this.usuarioId,
    required this.nombre,
    required this.nombreUsuario,
    required this.esMaestro,
    required this.permisos,
  });

  final String usuarioId;
  final String nombre;
  final String nombreUsuario;
  final bool esMaestro;
  final Set<String> permisos;
}
