import 'permission_service.dart';

/// Permiso que faltó al intentar autorizar una acción — se devuelve
/// `null` de [AuthorizationService.verificar] cuando sí está
/// autorizado, o esta clase cuando no. Cada Controller la traduce a su
/// propia variante sellada `XxxSinPermiso(codigo)` (nunca una excepción
/// que se propague hasta la UI) — así el `switch` exhaustivo de cada
/// pantalla obliga, en tiempo de compilación, a mostrar un mensaje
/// claro en vez de dejar pasar el caso silenciosamente.
class PermisoDenegado {
  const PermisoDenegado(this.codigo);

  /// Código exacto que faltó (ej. `'personal.crear'`) — se conserva
  /// para pruebas/auditoría, nunca se muestra crudo al usuario final.
  final String codigo;
}

/// Punto único de autorización para casos de uso protegidos (Etapa
/// 11C) — envuelve `PermissionService` (que ya reconoce sesión y
/// Maestro, ver `SessionPermissionService`) para que ningún Controller
/// reimplemente esa lógica por su cuenta.
///
/// Deliberadamente sin `Ref`/dependencias de Riverpod más allá de su
/// propio provider — los Controllers ya dependen de Riverpod (son
/// `@riverpod class`), así que la autorización vive ahí, nunca dentro
/// del caso de uso puro (que solo recibe parámetros planos, ver el doc
/// comment de `actor` en cada `ejecutar`).
class AuthorizationService {
  const AuthorizationService(this._permissionService);

  final PermissionService _permissionService;

  /// `null` si [codigo] está autorizado (incluye Maestro, que siempre
  /// pasa sin tener filas individuales de `PermisoUsuario`) — si no,
  /// el [PermisoDenegado] correspondiente. Una sesión inexistente
  /// (`null`) se resuelve exactamente igual que un permiso faltante,
  /// sin caso especial: `SessionPermissionService.hasCode` ya niega
  /// todo sin sesión, así que "sin sesión" y "sin permiso" son la
  /// misma rama de código — ningún caso de uso protegido puede
  /// ejecutarse sin usuario autenticado, sin necesidad de un chequeo
  /// aparte.
  PermisoDenegado? verificar(String codigo) {
    return _permissionService.hasCode(codigo) ? null : PermisoDenegado(codigo);
  }
}

/// Envoltura única de toda operación protegida (Etapa 11C, corrección
/// final) — el único lugar del proyecto donde se llama
/// [AuthorizationService.verificar]. Vive siempre en la capa de
/// aplicación (un método de Controller, o una función de fachada en
/// `xxx_providers.dart` cuando el dominio no tiene Controller
/// intermedio — ver `personal_providers.dart`), nunca dentro de un
/// diálogo/pantalla ni dentro de un caso de uso puro. Así, llamar la
/// operación protegida directamente (sin pasar por ningún botón/
/// diálogo — ej. desde una prueba con `ProviderContainer`) exige
/// exactamente la misma autorización que el camino real de UI, sin
/// duplicar el chequeo en ambas capas.
///
/// [errorInesperado] reutiliza la variante `XxxErrorInesperado(String
/// mensaje)` que cada tipo sellado del proyecto ya tiene — nunca se
/// introduce un tipo de error nuevo ni se modifica ningún union
/// existente para esto.
Future<R> autorizarUseCase<R>(
  AuthorizationService authorizationService,
  String codigo,
  Future<R> Function() operacion,
  R Function(String mensaje) errorInesperado,
) {
  if (authorizationService.verificar(codigo) != null) {
    return Future.value(errorInesperado('No tiene permiso para realizar esta acción.'));
  }
  return operacion();
}
