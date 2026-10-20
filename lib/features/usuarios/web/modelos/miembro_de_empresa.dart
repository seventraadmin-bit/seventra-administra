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
    required this.protegidos,
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
    protegidos: (json['protectedPermissionCount'] as num).toInt(),
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

  /// Cuántos de los concedidos son **protegidos** —`maestro_auto_grant = false`—:
  /// los que exigen concesión explícita incluso para un Maestro.
  ///
  /// **Lo cuenta el servidor y no esta clase**, porque la lista de protegidos es
  /// suya: `PermisoCompany.protegidos` existe aquí para pintar el panel, pero usarla
  /// para contar daría un número distinto el día que un permiso cambie de familia
  /// —y lo daría sin fallar—.
  final int protegidos;

  /// Qué alcance tiene esta persona, **en una línea que se entiende sin saber cómo
  /// funciona la autorización por dentro**.
  ///
  /// Antes la lista decía «6 + su rol», que es jerga: sólo se entiende sabiendo que
  /// los permisos de un Maestro no son filas.
  ///
  /// **Un Maestro tiene «Todos los permisos»**, y es literal: ejerce todos los
  /// ordinarios por su rol, no porque alguien se los haya concedido.
  ///
  /// ✅ **AHORA SÍ DICE CUÁNTOS SON PROTEGIDOS**, porque el servidor manda el número.
  ///
  /// Antes no se podía: [permisos] cuenta **todas** las concesiones del periodo, y
  /// para el primer Maestro esas seis son exactamente las protegidas —así que el
  /// número coincidía—, pero bastaba conceder un permiso ordinario por API para que
  /// la pantalla dijera «7 protegidos» y fuera falso. Afirmar en una pantalla algo
  /// que los datos no sostienen es justo lo que no se hace, así que el número vivía
  /// sólo en el panel.
  ///
  /// Con [protegidos] ya es exacto en los dos sitios, y **lo cuenta el servidor**:
  /// la lista de protegidos es suya, y una lista paralela aquí diría otro número el
  /// día que un permiso cambie de familia.
  ///
  /// **A UN MAESTRO NO SE LE DICE «todos los permisos» A SECAS**, y es la corrección
  /// que el número permite: un Maestro deriva por su rol **los ordinarios**, pero los
  /// protegidos los tiene sólo como concesiones explícitas y **se le pueden retirar**.
  /// Decirle «todos» a quien tiene cuatro de seis protegidos sería mentir en el
  /// resumen de lo que esa persona puede hacer.
  String get alcanceVisible {
    final protegidosEnPalabras = protegidos == 1
        ? '1 protegido'
        : '$protegidos protegidos';

    if (esMaestro) {
      return protegidos == 0
          ? 'Todos los ordinarios, ninguno protegido'
          : 'Todos los ordinarios y $protegidosEnPalabras';
    }

    final total = permisos == 1 ? '1 permiso' : '$permisos permisos';

    return protegidos == 0 ? total : '$total, $protegidosEnPalabras';
  }

  /// Lo que se muestra cuando el nombre no vino.
  ///
  /// `/auth/refresh` responde con `displayName` nulo, así que una sesión restaurada
  /// no lo trae; aquí el servidor sí lo manda, pero puede llegar en blanco si alguien
  /// se registró sin nombre. El correo nunca falta.
  String get nombreVisible => nombre.trim().isEmpty ? correo : nombre.trim();
}
