/// Contrato para consultar permisos del usuario actual (Etapa 11B).
///
/// La implementación real (`SessionPermissionService`, en
/// `features/usuarios/usuarios_providers.dart`) queda ligada a la
/// sesión activa: sin sesión niega todo, el Maestro concede todo sin
/// tener filas individuales de permiso, y cualquier otro usuario se
/// resuelve contra sus `PermisoUsuario` reales. Vive en `core/` como
/// interfaz pura (sin depender de `features/usuarios`) para que
/// cualquier capa pueda consultarlo sin importar el dominio de sesión
/// completo — mismo criterio de inversión de dependencias que el resto
/// del proyecto.
abstract class PermissionService {
  /// `codigo` con la forma `'modulo.accion'` (ej. `'personal.ver'`,
  /// `'nomina.cerrar'`).
  bool hasCode(String codigo);

  /// Azúcar sobre [hasCode] para los llamadores que ya tienen `modulo`/
  /// `accion` por separado (ej. el gate del router/sidebar).
  bool hasPermission(String modulo, String accion) => hasCode('$modulo.$accion');

  /// Sesión activa con `esMaestro == true` (Etapa 11D) — deliberadamente
  /// **independiente** de [hasCode]/[hasPermission]: la eliminación
  /// física extraordinaria del Maestro (ver `exigirMaestro` en
  /// `authorization_service.dart`) nunca puede otorgarse a través de un
  /// código de `PermisoUsuario`, así que se consulta esta propiedad
  /// directamente — ninguna fila de la matriz de permisos dinámicos
  /// puede volver a un usuario normal equivalente al Maestro para esa
  /// facultad.
  bool get esMaestroActivo;

  /// El mismo servicio, pero **revalidado contra la fuente
  /// autoritativa** (Etapa 3B, cierre de seguridad).
  ///
  /// Es la diferencia entre "lo que la sesión cree" y "lo que la cuenta
  /// es ahora mismo". [hasCode] y [esMaestroActivo] responden en
  /// memoria y son síncronos a propósito: los usa la interfaz —el
  /// sidebar, cada botón, el `redirect` del router— y convertirlos en
  /// asíncronos significaría consultar la base en cada `build`. Esto,
  /// en cambio, se `await`ea exactamente en los dos embudos por los que
  /// pasa toda operación protegida (`autorizarUseCase` y
  /// `exigirMaestro`), que ya eran asíncronos.
  ///
  /// Resultado: **pintar** la interfaz no toca la base ni una vez, y
  /// **ejecutar** una acción protegida pregunta siempre. Una cuenta
  /// desactivada mientras alguien tiene una pantalla abierta deja de
  /// autorizar en su siguiente acción, sin que haga falta navegar.
  ///
  /// La implementación por defecto se devuelve a sí misma: un servicio
  /// que no está ligado a ninguna fuente de datos no tiene nada que
  /// revalidar.
  Future<PermissionService> vigente() async => this;

  /// La sesión existe y puede EJECUTAR operaciones (Etapa 3B, cierre
  /// de seguridad).
  ///
  /// **IF-5** — el motivo cambió: hasta el cutover era `false` cuando la
  /// cuenta arrastraba una contraseña temporal fijada por otra persona.
  /// Ese mecanismo se retiró con la autenticación local. Hoy es `false`
  /// simplemente cuando no hay sesión.
  ///
  /// Deliberadamente separado de [hasCode]: si esto se hubiera metido
  /// dentro, los 94 lugares que consultan permisos para PINTAR la
  /// interfaz habrían empezado a mentir sobre qué permisos tiene la
  /// cuenta, cuando el problema no es el permiso sino el momento.
  bool get puedeOperar => true;

  /// La suscripción está en `restricted`: **se lee, no se escribe** (IF-5).
  ///
  /// NO ES LO MISMO QUE NO TENER PERMISO, y por eso no se resolvió
  /// vaciando [permisos] ni haciendo mentir a [hasCode]. Quien está
  /// restringido conserva TODAS sus facultades de consulta —retener los
  /// datos del cliente no cobra la deuda— y pierde sólo la capacidad de
  /// mutar. Si se hubiera colado dentro de [hasCode], el sidebar habría
  /// escondido módulos enteros y la persona no podría ni mirar lo suyo.
  ///
  /// Lo aplica `AuthorizationService.verificarVigente`, que es el embudo
  /// por el que pasa toda operación protegida del producto: un solo
  /// punto, no sesenta y un controles sueltos.
  bool get restringido => false;
}
