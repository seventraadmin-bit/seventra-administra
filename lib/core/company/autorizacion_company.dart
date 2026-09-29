import 'company_remota.dart';

/// Qué puede hacer esta Identity dentro de la Company activa.
///
/// ES UNA VISTA, NO UN ESTADO. No copia permisos, no copia módulos, no tiene caché y
/// no hace I/O: envuelve el [CompanyContext] que IF-3 publica y responde preguntas
/// sobre él. Por eso un cambio de empresa la cambia por completo sin que nada tenga
/// que sincronizarse — no hay una segunda copia que pueda quedarse atrás.
///
/// **EL BACKEND YA DECIDIÓ.** `effectivePermissions` es el resultado de
/// `PermissionPossession.Evaluate` del servidor, que ya aplicó, en este orden: si el
/// módulo está habilitado, si el rol Maestro hereda ese permiso concreto según el
/// catálogo, y si este periodo de acceso tiene la concesión explícita. Esta clase
/// **no recalcula nada de eso**: preguntar si un código está en la lista es todo lo
/// que hace, y ahí está su valor. Cualquier inferencia adicional aquí sería un segundo
/// sistema de autorización que divergiría del primero en el primer cambio.
///
/// **NO ES SEGURIDAD.** Sirve para ocultar, deshabilitar y orientar. Cada operación se
/// vuelve a autorizar en el servidor, así que un cliente manipulado que se invente
/// permisos no obtiene nada. Lo que esta clase evita es lo contrario: ofrecer un botón
/// que el servidor va a rechazar.
///
/// **NO CONOCE NADA LOCAL.** Ni `Usuario`, ni `SesionUsuario`, ni los 95 permisos del
/// sistema legacy, ni la `Empresa`. La frontera es absoluta en los dos sentidos: los
/// permisos remotos no autorizan una mutación de Drift, y los locales no autorizan un
/// endpoint.
final class AutorizacionCompany {
  const AutorizacionCompany(this._contexto);

  /// Sin empresa activa. **Niega todo**, que es el valor por omisión correcto.
  const AutorizacionCompany.sinCompany() : _contexto = null;

  /// El contexto activo, o `null` si no hay empresa resuelta.
  ///
  /// Es la **única** fuente. Que sea anulable es lo que hace estructural el
  /// «denegar por omisión»: «no hay empresa» es un valor representable, y no un nulo
  /// que cada punto de llamada deba recordar comprobar.
  final CompanyContext? _contexto;

  /// Si hay una empresa activa de la que derivar autorización.
  bool get hayCompany => _contexto != null;

  // -------------------------------------------------------------------------
  // Permisos
  // -------------------------------------------------------------------------

  /// ¿Posee este permiso?
  ///
  /// **Pertenencia literal a `effectivePermissions`, y nada más.** No expande `manage`
  /// a `read`, no interpreta los puntos del código como jerarquía, no concede por ser
  /// Maestro y no consulta ninguna otra fuente.
  ///
  /// Un código que no existe en el catálogo del servidor devuelve `false` como
  /// cualquier otro ausente. Conviene saber que enviarlo de verdad a un endpoint
  /// produciría un **500** —para el backend es un cliente exigiendo algo que nadie
  /// sembró—, y por eso los códigos viven en `PermisoCompany` y no escritos a mano.
  bool puede(String permiso) =>
      _contexto?.effectivePermissions.contains(permiso) ?? false;

  /// ¿Posee **al menos uno**?
  ///
  /// Un conjunto vacío devuelve `false`: no hay ninguno presente, y no hay nada que
  /// interpretar.
  bool puedeAlguno(Set<String> permisos) {
    final efectivos = _contexto?.effectivePermissions;
    if (efectivos == null) return false;

    return permisos.any(efectivos.contains);
  }

  /// ¿Posee **todos**?
  ///
  /// Hace falta porque el backend exige dos permisos a la vez en un sitio real: el
  /// expediente sensible de personal pide el protegido **y** el ordinario.
  ///
  /// EL CONJUNTO VACÍO, que es la única decisión discutible de esta clase:
  ///
  ///  · **sin empresa activa → `false`**, sin excepción. Denegar por omisión precede a
  ///    cualquier otra consideración: si no hay contexto, no hay nada que afirmar.
  ///  · **con empresa activa → `true`**, la verdad vacua. Se elige para que la
  ///    operación COMPONGA: `puedeTodos(a ∪ b)` equivale a
  ///    `puedeTodos(a) && puedeTodos(b)`, y con `false` esa igualdad se rompe en cuanto
  ///    uno de los dos conjuntos está vacío. Quien construya la lista de requisitos de
  ///    una pantalla espera eso; lo contrario obligaría a tratar el caso vacío a mano
  ///    en cada punto de llamada, que es precisamente donde se olvida.
  ///
  /// El riesgo del lado elegido —una lista de requisitos vacía por error habilita algo—
  /// es de interfaz, no de seguridad: el servidor vuelve a autorizar.
  bool puedeTodos(Set<String> permisos) {
    final efectivos = _contexto?.effectivePermissions;
    if (efectivos == null) return false;

    return permisos.every(efectivos.contains);
  }

  /// ¿Puede **ejecutar** una mutación que exige este permiso?
  ///
  /// Poseer el permiso **y** que la suscripción no esté restringida, en ese orden —el
  /// mismo del servidor, donde el veredicto comercial se evalúa antes que el permiso—.
  ///
  /// PARA EL MENSAJE HAY QUE PREGUNTAR APARTE. Esta operación colapsa dos negativas que
  /// el backend distingue: **402** cuando falta lo comercial y **403** cuando falta el
  /// permiso. Si la interfaz sólo mira esto, dirá «no tienes permiso» a alguien cuyo
  /// permiso está perfecto y cuyo problema es una gestión de cobro. Consulta
  /// [restringido] primero cuando vayas a explicar algo.
  bool puedeMutar(String permiso) => puede(permiso) && !restringido;

  // -------------------------------------------------------------------------
  // Módulos
  // -------------------------------------------------------------------------

  /// ¿Está el módulo habilitado en esta Company?
  ///
  /// **Pertenencia literal a `enabledModules`.** No se deriva de los permisos, y la
  /// separación importa: `effectivePermissions` ya **excluye** los permisos de un
  /// módulo apagado, así que mirando sólo esa lista, «el módulo está apagado para toda
  /// la empresa» y «a ti no te toca» son indistinguibles. Son dos arreglos distintos
  /// —uno lo resuelve el Maestro, el otro quien concede permisos— y el cliente
  /// necesita saber cuál ofrecer. Por eso hacen falta los dos campos.
  ///
  /// Un módulo apagado lo está **también para el Maestro**: es el primer paso del
  /// algoritmo del servidor, y Flutter no lo reinterpreta.
  bool moduloHabilitado(String modulo) =>
      _contexto?.enabledModules.contains(modulo) ?? false;

  // -------------------------------------------------------------------------
  // Estado
  // -------------------------------------------------------------------------

  /// La suscripción de la Organization no permite la operación normal.
  ///
  /// **Es de sólo lectura, no de datos ocultos.** Todo lo legible sigue legible: deber
  /// dinero es motivo para no dejar crecer —crear, editar, subir—, no para retener el
  /// expediente de los empleados de un cliente. Es la regla del propio backend.
  ///
  /// `false` sin empresa activa, y es deliberado: mostrar una restricción comercial a
  /// quien simplemente no ha elegido empresa sería inventar un problema. «Sin empresa»
  /// tiene sus propios estados en IF-3 y no se disfraza de restricción.
  bool get restringido => _contexto?.restricted ?? false;

  /// Si esta Identity es Maestro de esta Company.
  ///
  /// **NO es un comodín, y confundirlo es el error más caro de esta capa.** El Maestro
  /// del backend **no** hereda los permisos protegidos, y un módulo apagado lo detiene
  /// igual. [puede] no lo consulta: responde con `effectivePermissions`, que ya
  /// incorporó la herencia con sus excepciones. Así, un Maestro al que se le retiró
  /// `personal.sensitive.read` obtiene `false`, que es la verdad.
  ///
  /// Sirve para lo que de verdad es Maestro-only en el servidor: habilitar módulos y
  /// administrar concesiones de permisos.
  bool get esMaestro => _contexto?.isMaestro ?? false;

  /// El rol tal como lo manda el servidor (`maestro` o `user`), o `null`.
  ///
  /// **Para MOSTRARLO, no para decidir.** La capacidad sale de [puede]; comparar
  /// cadenas de rol para conceder algo sería reimplementar —mal— la herencia que el
  /// catálogo ya resolvió.
  String? get rol => _contexto?.role;

  @override
  String toString() =>
      _contexto == null
          ? 'AutorizacionCompany(sin empresa)'
          : 'AutorizacionCompany(${_contexto.companyId}, rol: ${_contexto.role}, '
              '${_contexto.effectivePermissions.length} permisos'
              '${_contexto.restricted ? ', restringida' : ''})';
}
