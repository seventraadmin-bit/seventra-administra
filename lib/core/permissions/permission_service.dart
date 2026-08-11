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
}
