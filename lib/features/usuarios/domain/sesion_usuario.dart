/// Sesión activa (Etapa 11A) — todo lo que la app necesita saber sobre
/// quién está usándola ahora mismo. Deliberadamente sin `permisos`
/// todavía: hasta la Etapa 11B no existe `PermisoUsuario`, y nada gatea
/// accesos con este dato en 11A (cualquiera con sesión ve todo — ver el
/// plan de la Etapa 11).
class SesionUsuario {
  const SesionUsuario({
    required this.usuarioId,
    required this.nombre,
    required this.nombreUsuario,
    required this.esMaestro,
  });

  final String usuarioId;
  final String nombre;
  final String nombreUsuario;
  final bool esMaestro;
}
