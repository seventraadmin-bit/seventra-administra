import '../error/failure.dart';
import '../error/result.dart';

/// Una Company que esta Identity **puede abrir**: lo justo para elegir.
///
/// Es el espejo exacto de `AccessibleCompany` del backend —cinco campos, ni uno
/// más— y la fidelidad es deliberada: inventar aquí un campo que el servidor no
/// manda obligaría a rellenarlo con una suposición.
///
/// **NO TIENE `status`**, y no es un olvido. `GET /companies` sólo devuelve filas
/// con `company_access.status`, `company.status` y `organization.status` en
/// `activa`, los tres. Una Company inactiva —o un acceso revocado— no aparece en
/// la lista: desaparece. Un campo de estado aquí valdría siempre lo mismo e
/// invitaría a ramificar sobre nada.
final class CompanyDisponible {
  const CompanyDisponible({
    required this.companyId,
    required this.organizationId,
    required this.companyName,
    required this.organizationName,
    required this.role,
    this.estado = 'activa',
  });

  final String companyId;
  final String organizationId;
  final String companyName;
  final String organizationName;

  /// `maestro` o `user`. El catálogo del backend es cerrado; aquí se conserva como
  /// texto porque el cliente no decide autorización con él.
  final String role;

  /// `activa` o `inactiva`.
  ///
  /// ⚠️ **HOY VALE SIEMPRE `activa`, y el campo existe de todas formas.** La ruta
  /// filtra por `c.status = 'activa'`, así que por construcción ninguna fila puede
  /// traer otra cosa.
  ///
  /// **Nace ahora para no rehacer la lista en E2.** Cuando E2 traiga desactivar y
  /// reactivar, la lista tendrá que enseñar las inactivas a quien pueda reactivarlas,
  /// y hay una razón dura: una empresa desactivada **desaparece de esta consulta y del
  /// autorizador a la vez**, así que sería inalcanzable desde la única lista que
  /// existe. Lo que E2 añade es el filtro, no la forma.
  ///
  /// **El valor por omisión es `activa` y NO es «ausencia es cero».** Es el único
  /// valor que la ruta puede devolver hoy: con el filtro puesto, una fila sin `status`
  /// sólo puede ser una empresa activa servida por un servidor que todavía no manda el
  /// campo. Exigirlo rompería el **inicio de sesión** contra un servidor viejo, y eso
  /// es un precio desproporcionado para un dato de presentación.
  final String estado;

  static Result<CompanyDisponible> desdeJson(Map<String, Object?> json) {
    final companyId = _texto(json['companyId']);
    final organizationId = _texto(json['organizationId']);
    final companyName = _texto(json['companyName']);
    final organizationName = _texto(json['organizationName']);
    final role = _texto(json['role']);

    final faltantes = <String>[
      if (companyId == null) 'companyId',
      if (organizationId == null) 'organizationId',
      if (companyName == null) 'companyName',
      if (organizationName == null) 'organizationName',
      if (role == null) 'role',
    ];

    if (faltantes.isNotEmpty) {
      return Result.failure(
        ApiRespuestaInesperadaFailure(
          'La lista de empresas no trae: ${faltantes.join(', ')}.',
        ),
      );
    }

    return Result.ok(
      CompanyDisponible(
        companyId: companyId!,
        organizationId: organizationId!,
        companyName: companyName!,
        organizationName: organizationName!,
        role: role!,
        // NO ESTÁ EN `faltantes` A PROPÓSITO: ver el comentario de `estado`. Exigirlo
        // rompería el inicio de sesión contra un servidor que todavía no lo manda.
        estado: _texto(json['status']) ?? 'activa',
      ),
    );
  }

  /// La misma empresa con otro nombre comercial.
  ///
  /// Para cuando alguien lo cambia desde su expediente: la lista que el marco resolvió
  /// al entrar seguiría diciendo el viejo, y **no se vuelve a resolver por eso** —la
  /// resolución es del gestor y tiene su propio momento—. Esto actualiza lo que ya se
  /// tenía, que es otra cosa.
  CompanyDisponible conNombre(String nombre) => CompanyDisponible(
    companyId: companyId,
    organizationId: organizationId,
    companyName: nombre,
    organizationName: organizationName,
    role: role,
    estado: estado,
  );

  @override
  String toString() => 'CompanyDisponible($companyId, $companyName)';

  @override
  bool operator ==(Object other) =>
      other is CompanyDisponible &&
      other.companyId == companyId &&
      other.organizationId == organizationId &&
      other.companyName == companyName &&
      other.organizationName == organizationName &&
      other.role == role &&
      // `estado` ENTRA EN LA IGUALDAD, y se quedó fuera al añadirlo: hoy vale siempre
      // `activa`, así que dos filas no pueden diferir sólo en él — pero cuando E2
      // traiga las inactivas, una lista que compare como igual una empresa activa y
      // la misma desactivada no se repintaría al desactivarla.
      other.estado == estado;

  @override
  int get hashCode => Object.hash(
    companyId,
    organizationId,
    companyName,
    organizationName,
    role,
    estado,
  );
}

/// El contexto completo de una Company para quien está autenticado: la respuesta
/// de `GET /companies/{companyId}/context`, con sus **diez** campos.
///
/// SE CONSERVAN LOS CUATRO CAMPOS DE AUTORIZACIÓN —[isMaestro], [enabledModules],
/// [effectivePermissions], [restricted]— aunque IF-3 **no los aplique**. No es
/// código muerto: el backend los entrega en la misma llamada porque un cliente los
/// necesita para arrancar, y descartarlos obligaría a IF-4 a pedir otra vez lo que
/// ya vino. Lo que IF-3 no hace es decidir nada con ellos.
///
/// [restricted] es una dimensión **separada** de los permisos: alguien puede poseer
/// `personal.manage` y recibir 402 al mutar mientras la suscripción esté
/// restringida. Por eso los permisos no se recortan por estar restringido —
/// mentiría sobre lo que tiene.
final class CompanyContext {
  const CompanyContext({
    required this.companyId,
    required this.organizationId,
    required this.companyName,
    required this.companyStatus,
    required this.organizationName,
    required this.role,
    required this.isMaestro,
    required this.restricted,
    required this.enabledModules,
    required this.effectivePermissions,
  });

  final String companyId;
  final String organizationId;
  final String companyName;

  /// El estado de la Company tal como lo manda el servidor.
  ///
  /// **Hoy sólo puede valer `activa`**: la consulta de `/context` exige los tres
  /// `status = 'activa'`, así que una Company inactiva responde 404 y nunca llega
  /// aquí. Se conserva por fidelidad al contrato —el servidor lo envía— y **no se
  /// usa para decidir**: ramificar sobre un valor constante sería código muerto
  /// disfrazado de defensa.
  final String companyStatus;

  final String organizationName;
  final String role;

  /// Diferido a IF-4. Se conserva, no se aplica.
  final bool isMaestro;

  /// Diferido a IF-4. Se conserva, no se aplica.
  final bool restricted;

  /// Diferido a IF-4. Se conserva, no se aplica.
  final Set<String> enabledModules;

  /// Diferido a IF-4. Se conserva, no se aplica. **No es autorización**: cada
  /// operación se vuelve a autorizar en el servidor.
  final Set<String> effectivePermissions;

  static Result<CompanyContext> desdeJson(Map<String, Object?> json) {
    final companyId = _texto(json['companyId']);
    final organizationId = _texto(json['organizationId']);
    final companyName = _texto(json['companyName']);
    final companyStatus = _texto(json['companyStatus']);
    final organizationName = _texto(json['organizationName']);
    final role = _texto(json['role']);
    final isMaestro = json['isMaestro'];
    final restricted = json['restricted'];

    final faltantes = <String>[
      if (companyId == null) 'companyId',
      if (organizationId == null) 'organizationId',
      if (companyName == null) 'companyName',
      if (companyStatus == null) 'companyStatus',
      if (organizationName == null) 'organizationName',
      if (role == null) 'role',
      if (isMaestro is! bool) 'isMaestro',
      if (restricted is! bool) 'restricted',
      if (json['enabledModules'] is! List) 'enabledModules',
      if (json['effectivePermissions'] is! List) 'effectivePermissions',
    ];

    if (faltantes.isNotEmpty) {
      // Se nombran los campos, nunca los valores.
      return Result.failure(
        ApiRespuestaInesperadaFailure(
          'El contexto de la empresa no trae: ${faltantes.join(', ')}.',
        ),
      );
    }

    return Result.ok(
      CompanyContext(
        companyId: companyId!,
        organizationId: organizationId!,
        companyName: companyName!,
        companyStatus: companyStatus!,
        organizationName: organizationName!,
        role: role!,
        isMaestro: isMaestro as bool,
        restricted: restricted as bool,
        enabledModules: _textos(json['enabledModules']),
        effectivePermissions: _textos(json['effectivePermissions']),
      ),
    );
  }

  /// Los códigos como conjunto: la pregunta que IF-4 hará siempre es
  /// «¿contiene?», no «¿en qué posición?», y un `Set` la responde sin recorrer.
  /// Lo que no sea texto se ignora en vez de romper la respuesta entera.
  static Set<String> _textos(Object? valor) {
    if (valor is! List) return const <String>{};

    return valor.whereType<String>().where((s) => s.isNotEmpty).toSet();
  }

  @override
  String toString() => 'CompanyContext($companyId, $companyName, role: $role)';

  /// Igualdad **por valor, con los diez campos**.
  ///
  /// ⚠️ **NO ES COSMÉTICA: de ella depende que el marco se repinte.** El estado de
  /// empresa viaja en un `ValueNotifier`, que sólo notifica cuando el valor cambia, y
  /// `CompanyActiva` delega aquí. Sin esta igualdad valía la identidad del objeto —dos
  /// contextos nunca eran iguales— y con la igualdad por `companyId` de antes **nunca
  /// eran distintos**: ninguno de los dos extremos sirve.
  ///
  /// **Los dos conjuntos se comparan por su CONTENIDO.** Un `Set` usa identidad, así
  /// que dos conjuntos con los mismos permisos se habrían considerado distintos y el
  /// marco se repintaría en cada revalidación — que es el ruido que la igualdad por id
  /// quería evitar, reintroducido por la puerta de atrás.
  @override
  bool operator ==(Object other) =>
      other is CompanyContext &&
      other.companyId == companyId &&
      other.organizationId == organizationId &&
      other.companyName == companyName &&
      other.companyStatus == companyStatus &&
      other.organizationName == organizationName &&
      other.role == role &&
      other.isMaestro == isMaestro &&
      other.restricted == restricted &&
      _mismoConjunto(other.enabledModules, enabledModules) &&
      _mismoConjunto(other.effectivePermissions, effectivePermissions);

  @override
  int get hashCode => Object.hash(
    companyId,
    organizationId,
    companyName,
    companyStatus,
    organizationName,
    role,
    isMaestro,
    restricted,
    // ORDENADOS ANTES DE HASHEAR: `Object.hashAllUnordered` existe para esto, y usar
    // `hashAll` sobre un `Set` daría un hash distinto según el orden de iteración
    // —que no está garantizado— para dos conjuntos iguales.
    Object.hashAllUnordered(enabledModules),
    Object.hashAllUnordered(effectivePermissions),
  );

  static bool _mismoConjunto(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

String? _texto(Object? valor) {
  if (valor is! String) return null;

  final limpio = valor.trim();
  return limpio.isEmpty ? null : limpio;
}

// ===========================================================================
// El estado observable
// ===========================================================================

/// En qué situación está la Company activa.
///
/// SON CINCO ESTADOS Y NINGUNO SE COLAPSA. Dos parejas son especialmente fáciles
/// de confundir y confundirlas produce errores concretos:
///
///  · **«no hay accesos» no es «no pudimos preguntar»**. El servidor respondiendo
///    una lista vacía es un hecho; un timeout no dice nada. Tratarlos igual haría
///    que una wifi intermitente le dijera al usuario que le quitaron todas sus
///    empresas — y, peor, invitaría a borrar su preferencia guardada.
///  · **«todavía no se ha resuelto» no es «hay que elegir»**. Un portón que los
///    confunda pediría elegir empresa antes de haber preguntado cuáles hay.
sealed class EstadoCompany {
  const EstadoCompany();
}

/// Nadie ha resuelto todavía. Estado inicial.
final class CompanySinResolver extends EstadoCompany {
  const CompanySinResolver();

  @override
  String toString() => 'CompanySinResolver()';
}

/// La Identity es válida y el servidor respondió que **no tiene acceso a ninguna
/// Company**. Es un hecho, no un fallo.
///
/// No es un caso raro: un Owner de Organization que nombró Maestro a otra persona
/// llega aquí el primer día, porque ser Owner no concede acceso a datos.
final class SinAccesoACompanies extends EstadoCompany {
  const SinAccesoACompanies();

  @override
  String toString() => 'SinAccesoACompanies()';
}

/// Hay varias Companies y ninguna candidata válida —no había preferencia, o la que
/// había ya no está en la lista—. Hace falta que alguien elija.
final class SeleccionDeCompanyRequerida extends EstadoCompany {
  const SeleccionDeCompanyRequerida(this.disponibles);

  final List<CompanyDisponible> disponibles;

  @override
  String toString() =>
      'SeleccionDeCompanyRequerida(${disponibles.length} empresas)';
}

/// Hay una Company activa y su contexto está confirmado por el servidor.
final class CompanyActiva extends EstadoCompany {
  const CompanyActiva(this.contexto);

  final CompanyContext contexto;

  @override
  String toString() => 'CompanyActiva(${contexto.companyId})';

  /// ⚠️ **COMPARA EL CONTEXTO ENTERO, Y ANTES SÓLO COMPARABA EL `companyId`.**
  ///
  /// El estado se publica en un `ValueNotifier`, que **sólo notifica si el valor
  /// cambió**. Con la igualdad por id, un contexto nuevo de la MISMA empresa se
  /// consideraba igual al viejo, así que no se notificaba y **el marco no se
  /// repintaba**: se vio en pantalla el 21 de octubre de 2026 —se renombró la empresa,
  /// la ficha decía el nombre nuevo y **la barra inferior seguía con el viejo** hasta
  /// recargar—.
  ///
  /// Y el nombre era el síntoma menor. Lo que esa igualdad también se tragaba eran
  /// **los permisos efectivos y los módulos**: revalidar tras un cambio de permisos no
  /// repintaba nada, así que el menú seguía ofreciendo lo de antes.
  ///
  /// **Lo que la igualdad por id protegía sigue protegido**: resolver dos veces la
  /// misma empresa sin que nada haya cambiado produce contextos iguales y no repinta.
  /// Lo que cambia es que ahora «igual» significa igual de verdad.
  @override
  bool operator ==(Object other) =>
      other is CompanyActiva && other.contexto == contexto;

  @override
  int get hashCode => contexto.hashCode;
}

/// No se pudo resolver: sin red, tiempo agotado, 5xx, o un contexto que el
/// servidor no entrega por una razón comercial.
///
/// **No se borra nada.** La preferencia guardada sigue donde estaba y el siguiente
/// intento la volverá a usar. Es la diferencia entre «no hay» y «no se pudo
/// preguntar», y es la razón de que este estado exista separado de
/// [SinAccesoACompanies].
final class CompanyNoResuelta extends EstadoCompany {
  const CompanyNoResuelta(this.motivo);

  final Failure motivo;

  @override
  String toString() => 'CompanyNoResuelta(${motivo.runtimeType})';
}
