/// Una persona con acceso activo a la empresa, tal como la devuelve
/// `GET /companies/{id}/access`.
///
/// **Modelo plano y propio de la web**, por la misma razón que [Area]: el dominio del
/// escritorio habla tipos generados por Drift, y aquí no hay Drift.
class MiembroDeEmpresa {
  const MiembroDeEmpresa({
    required this.accesoId,
    required this.identidadId,
    required this.correo,
    required this.nombre,
    required this.esMaestro,
    required this.permisos,
  });

  factory MiembroDeEmpresa.deJson(Map<String, dynamic> json) => MiembroDeEmpresa(
    accesoId: json['accessId'] as String,
    identidadId: json['identityId'] as String,
    correo: json['email'] as String,
    nombre: json['displayName'] as String,
    // **Se deriva del rol**, igual que `activa` se deriva del estado en [Area]. El
    // servidor manda `maestro` o `user`, y lo que la pantalla pregunta de verdad es
    // si esta persona administra la empresa.
    esMaestro: json['role'] == 'maestro',
    permisos: (json['permissionCount'] as num).toInt(),
  );

  /// El identificador del **PERIODO de acceso**, no de la persona.
  ///
  /// Es el que piden las rutas de permisos, y por eso viaja: los permisos cuelgan del
  /// periodo. Si a alguien se le revoca el acceso y se le vuelve a conceder, es un
  /// periodo nuevo —y empieza sin los permisos del anterior, a propósito—.
  final String accesoId;

  final String identidadId;
  final String correo;
  final String nombre;

  /// ¿Administra la empresa? Sólo un Maestro puede ver esta lista y tocar permisos.
  final bool esMaestro;

  /// Cuántos permisos tiene **concedidos como filas**.
  ///
  /// ⚠️ **NO es todo lo que puede hacer.** Un Maestro ejerce además los permisos
  /// ordinarios por su rol, que no son filas y no se cuentan aquí. Y el **primer**
  /// Maestro de la empresa nace con los seis protegidos ya concedidos —sueldo,
  /// expediente sensible y portales—, mientras que uno añadido después empieza sin
  /// ellos. La pantalla tiene que dejar ver esa diferencia.
  final int permisos;

  /// Qué alcance tiene esta persona, **en una línea que se entiende sin saber cómo
  /// funciona la autorización por dentro**.
  ///
  /// Antes la lista decía «6 + su rol», que es jerga: sólo se entiende sabiendo que
  /// los permisos de un Maestro no son filas.
  ///
  /// **Un Maestro tiene «Todos los permisos»**, y es literal: ejerce todos los
  /// ordinarios por su rol, no porque alguien se los haya concedido.
  ///
  /// ⚠️ **NO DICE «N PROTEGIDOS», Y HAY QUE EXPLICAR POR QUÉ.** [permisos] cuenta
  /// **todas** las concesiones del periodo, no sólo las protegidas. Para el primer
  /// Maestro esas seis son exactamente las protegidas, así que el número coincidiría
  /// hoy — pero si alguien le concediera un permiso ordinario por API diría
  /// «7 protegidos» y sería falso. Afirmar en una pantalla algo que los datos no
  /// sostienen es justo lo que no se hace, así que el número se queda donde es
  /// exacto: el panel, que sí sabe cuáles son.
  ///
  /// ⏳ Para decirlo con número, `GET /companies/{id}/access` tendría que mandar su
  /// propio `protectedPermissionCount`.
  String get alcanceVisible {
    if (esMaestro) return 'Todos los permisos';

    return permisos == 1 ? '1 permiso' : '$permisos permisos';
  }

  /// Lo que se muestra cuando el nombre no vino.
  ///
  /// `/auth/refresh` responde con `displayName` nulo, así que una sesión restaurada
  /// no lo trae; aquí el servidor sí lo manda, pero puede llegar en blanco si alguien
  /// se registró sin nombre. El correo nunca falta.
  String get nombreVisible => nombre.trim().isEmpty ? correo : nombre.trim();
}
