import '../config/env.dart';

/// Contrato para consultar permisos del usuario actual.
///
/// La implementación real (respaldada por Rol/Permiso) todavía no existe —
/// se construye cuando el módulo de permisos del Core se implemente. Hasta
/// entonces, cualquier consumidor de este contrato debe seguir funcionando
/// sin cambios cuando esa implementación real llegue.
abstract class PermissionService {
  bool hasPermission(String modulo, String accion);
}

/// Implementación de SOLO DESARROLLO.
///
/// Permite explícitamente todo, para poder navegar y probar la aplicación
/// mientras el sistema real de Roles/Permisos no existe. Su nombre es
/// deliberadamente explícito para que nunca pase inadvertida si terminara
/// mal cableada.
class DevelopmentPermissionService implements PermissionService {
  const DevelopmentPermissionService();

  @override
  bool hasPermission(String modulo, String accion) => true;
}

/// Implementación provisional para cualquier entorno que no sea desarrollo.
///
/// Niega cualquier permiso no definido explícitamente ("deny by default").
/// Es intencionalmente conservadora: es preferible que una pantalla se
/// muestre de más restringida a que otorgue un acceso no autorizado.
class DenyByDefaultPermissionService implements PermissionService {
  const DenyByDefaultPermissionService();

  @override
  bool hasPermission(String modulo, String accion) => false;
}

/// Selecciona la implementación correcta según el entorno.
///
/// Solo [Env.dev] obtiene la implementación permisiva; cualquier otro valor
/// (incluido uno mal configurado o desconocido) recibe la implementación
/// que niega por defecto.
PermissionService resolvePermissionService(Env env) {
  return env.isDev
      ? const DevelopmentPermissionService()
      : const DenyByDefaultPermissionService();
}
