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
    this.debeCambiarPassword = false,
  });

  final String usuarioId;
  final String nombre;
  final String nombreUsuario;
  final bool esMaestro;
  final Set<String> permisos;

  /// La cuenta arrastra una contraseña temporal (Etapa "Usuarios,
  /// permisos y UX de seguridad"): la fijó quien la dio de alta o quien
  /// la reseteó, así que la conoce alguien más. Mientras sea `true` el
  /// `redirect` del router no deja llegar a ninguna pantalla de la app
  /// salvo el cambio obligatorio — la sesión existe, pero no opera.
  ///
  /// Nace de `Usuario.debeCambiarPassword` en el login (o al restaurar
  /// "Recuérdame"), y se apaga en el momento en que el titular cambia su
  /// contraseña, sin exigir un nuevo login.
  final bool debeCambiarPassword;

  SesionUsuario copyWith({bool? debeCambiarPassword}) => SesionUsuario(
        usuarioId: usuarioId,
        nombre: nombre,
        nombreUsuario: nombreUsuario,
        esMaestro: esMaestro,
        permisos: permisos,
        debeCambiarPassword: debeCambiarPassword ?? this.debeCambiarPassword,
      );
}
