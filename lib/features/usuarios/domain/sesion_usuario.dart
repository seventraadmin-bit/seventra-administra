/// Sesión activa — todo lo que la app necesita saber sobre quién está
/// usándola ahora mismo.
///
/// `permisos` (Etapa 11B) nace en el login (`LoginUseCase`): para un
/// Maestro, el catálogo completo (`todosLosCodigosDePermiso()`); para
/// cualquier otro, sus `PermisoUsuario` reales.
///
/// **Etapa 3B — ya no es un conjunto congelado.** Hasta entonces la
/// sesión conservaba los permisos del momento del login hasta el
/// siguiente, y una cuenta desactivada seguía operando mientras no
/// cerrara la aplicación. Ahora `SesionController.revalidar()` vuelve a
/// leer la cuenta —permisos, condición de Maestro, estado— en cada
/// navegación y justo después de cualquier mutación que la afecte. Sin
/// temporizadores y sin consultar la base desde ningún widget: ver su
/// doc comment para el detalle de cuándo exactamente.
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
