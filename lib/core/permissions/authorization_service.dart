import 'permission_service.dart';
import 'vocabulario_permisos.dart';

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

  /// Igual que [verificar], pero preguntando antes a la fuente
  /// autoritativa si la cuenta **sigue vigente** (Etapa 3B, cierre de
  /// seguridad).
  ///
  /// Es lo que usa `autorizarUseCase`, y por tanto lo que se aplica a
  /// toda operación protegida del proyecto. [verificar] se conserva
  /// para consultas en memoria (la interfaz), pero ninguna EJECUCIÓN
  /// pasa ya por ella.
  ///
  /// Cubre de una sola vez —y con un único mecanismo— la cuenta
  /// desactivada, la cuenta que ya no existe, el permiso revocado, el
  /// permiso recién concedido y el Maestro degradado: todos son el
  /// mismo hecho, "la sesión en memoria dejó de describir a la cuenta".
  Future<PermisoDenegado?> verificarVigente(String codigo) async {
    final vigente = await _permissionService.vigente();

    // Sin sesión no se ejecuta nada, tenga el permiso que tenga.
    if (!vigente.puedeOperar) return PermisoDenegado(codigo);
    if (!vigente.hasCode(codigo)) return PermisoDenegado(codigo);

    // `restricted` (IF-5) — la suscripción está al día para LEER y no para
    // escribir. Se aplica AQUÍ, en el embudo único de toda operación protegida,
    // y no en los sesenta y un sitios que consultan permisos: un control
    // repetido sesenta y una veces es un control que un día falta en una.
    //
    // La distinción lectura/mutación es la que el catálogo ya codificaba —`ver`
    // consulta, el resto cambia algo—, así que no hubo que inventar ninguna
    // clasificación nueva ni marcar permiso por permiso.
    if (vigente.restringido && !esLectura(codigo)) return PermisoDenegado(codigo);

    return null;
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
///
/// **Etapa 3B (cierre de seguridad)** — antes de autorizar se revalida
/// la sesión contra la base. Hasta entonces la comprobación se hacía
/// sólo contra el conjunto de permisos cargado en el login, así que
/// quien no navegaba conservaba su autorización indefinidamente: una
/// cuenta desactivada —o alguien a quien acababan de dar de baja—
/// seguía pudiendo ejecutar mutaciones desde la pantalla que ya tenía
/// abierta. La seguridad no podía depender del `redirect` del router.
///
/// El coste es **una consulta** (dos si la cuenta no es Maestra) por
/// operación protegida, nunca durante el pintado. La firma no cambió:
/// los 216 lugares que la invocan siguen escribiéndose igual.
Future<R> autorizarUseCase<R>(
  AuthorizationService authorizationService,
  String codigo,
  Future<R> Function() operacion,
  R Function(String mensaje) errorInesperado,
) async {
  if (await authorizationService.verificarVigente(codigo) != null) {
    return errorInesperado('No tiene permiso para realizar esta acción.');
  }
  return operacion();
}

/// Facultad extraordinaria del Usuario Maestro (Etapa 11D) — mecanismo
/// **deliberadamente distinto** de [autorizarUseCase]: no consulta
/// ningún código de `PermisoUsuario` (usa
/// [PermissionService.esMaestroActivo] directo, nunca [hasCode]), así
/// que ninguna casilla de la matriz de permisos dinámicos puede volver
/// a un usuario normal equivalente al Maestro. No es un mecanismo
/// genérico de "bypass": cada acción extraordinaria sigue siendo su
/// propio UseCase dedicado, con su propia validación de negocio — hoy
/// lo usan los `EliminarXxxFisicamenteUseCase` (Etapa 11D) y
/// Respaldo/Restauración (Etapa 14C).
///
/// **Etapa 3B (cierre de seguridad)** — igual que `autorizarUseCase`,
/// comprueba el estado VIGENTE, no el que la sesión traía del login.
/// Degradar a un Maestro tenía que dejar de bastar con que su sesión en
/// memoria siguiera diciendo `esMaestro = true`: esta es exactamente la
/// facultad donde eso importaba más, porque es la que autoriza la
/// eliminación física y el respaldo.
Future<R> exigirMaestro<R>(
  PermissionService permissionService,
  Future<R> Function() operacion,
  R Function(String mensaje) noAutorizado,
) async {
  final vigente = await permissionService.vigente();
  if (!vigente.puedeOperar || !vigente.esMaestroActivo) {
    return noAutorizado('Esta acción requiere el Usuario Maestro.');
  }

  // `restricted` alcanza también al Maestro (IF-5). Todo lo que pasa por aquí
  // —eliminación física, respaldo, bóveda— muta, y ser Maestro no paga la
  // suscripción: si el titular pudiera seguir operando, `restricted` no
  // significaría nada en la empresa donde más importa.
  if (vigente.restringido) {
    return noAutorizado('La suscripción sólo permite consultar. No se puede realizar esta acción.');
  }

  return operacion();
}
