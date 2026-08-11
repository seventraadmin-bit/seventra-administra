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
}
