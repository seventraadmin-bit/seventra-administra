/// Sesión activa — todo lo que la app necesita saber sobre quién está usándola
/// ahora mismo.
///
/// ## Desde IF-5 NO NACE DE SQLITE
///
/// Nace de tres respuestas del backend, en este orden: la Identity dice quién
/// es, `GET /context` dice qué Company está activa y qué puede hacer ahí, y de
/// ahí salen [permisos], [esMaestro] y [restringido]. **SQLite dejó de ser
/// autoridad de autorización**: la fila `Usuario` local sigue existiendo como
/// proyección para las claves foráneas de los módulos que aún viven ahí, pero
/// nadie le pregunta ya qué puede hacer nadie.
///
/// [usuarioId] ES el `identityId` del SaaS, carácter por carácter. No es una
/// segunda identidad ni un id traducido: es el mismo, y por eso los mil
/// setecientos noventa `actorUsuarioId` del producto siguen atribuyendo
/// correctamente sin tocarse.
///
/// ## Lo que se fue
///
/// `debeCambiarPassword` desapareció con el modelo local: ya no hay contraseñas
/// que un Maestro fije y el titular tenga que cambiar. La contraseña vive en el
/// backend y se recupera por correo.
class SesionUsuario {
  const SesionUsuario({
    required this.usuarioId,
    required this.nombre,
    required this.nombreUsuario,
    required this.esMaestro,
    required this.permisos,
    this.restringido = false,
  });

  /// El `identityId` del backend. Ver la nota de la clase.
  final String usuarioId;

  final String nombre;

  /// El correo con el que se autenticó. Es un dato proyectado, **no una clave**:
  /// nadie identifica a nadie por aquí.
  final String nombreUsuario;

  /// Proyectado desde `CompanyContext.isMaestro` — el servidor lo decide.
  final bool esMaestro;

  /// Traducidos desde `CompanyContext.effectivePermissions` por la frontera de
  /// vocabulario, en el idioma que el producto ya consulta.
  final Set<String> permisos;

  /// La suscripción de la Organization está en `restricted`: **se lee, no se
  /// escribe**.
  ///
  /// No es lo mismo que no tener permiso. Quien está restringido conserva todas
  /// sus facultades de consulta —retener los datos del cliente no cobra la
  /// deuda— y pierde únicamente la capacidad de mutar. Lo aplica
  /// `AuthorizationService.verificarVigente`, que es el embudo por el que pasa
  /// toda operación protegida del producto.
  final bool restringido;

  SesionUsuario copyWith({bool? restringido}) => SesionUsuario(
    usuarioId: usuarioId,
    nombre: nombre,
    nombreUsuario: nombreUsuario,
    esMaestro: esMaestro,
    permisos: permisos,
    restringido: restringido ?? this.restringido,
  );
}
