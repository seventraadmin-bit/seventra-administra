import 'dart:convert';

import '../modelos/evento_de_auditoria.dart';
import '../../../../app/shell/apartados_web.dart' as apartados;

/// **La auditoría dicha en español, para alguien que no programa.**
///
/// El servidor guarda los hechos con la precisión que hace falta para una traza:
/// códigos de entidad y de acción, y el antes y el después como JSON. Eso es lo
/// correcto para la base —sobrevive a cualquier cambio de interfaz— y es **ilegible**
/// para la persona que administra una empresa.
///
/// Aquí vive toda la traducción, y **nada más**: esta clase no pide datos, no pinta y
/// no decide permisos. Por eso se puede probar entera sin tocar un widget, que es lo
/// que hacen sus pruebas.
///
/// ## Las cuatro reglas que la gobiernan
///
///  1. **NUNCA SE MUESTRA JSON.** Ni como respaldo, ni «para depurar», ni cuando algo
///     no se entiende. Si un detalle no se puede interpretar, se dice con palabras;
///     volcar la llave cruda convierte la pantalla en una consola.
///  2. **Lo que cambió, y sólo eso.** Cuando hay antes y después, se comparan y se
///     listan los campos distintos. Repetir los diez que siguen iguales esconde el
///     único que se movió.
///  3. **Los campos técnicos no se muestran.** Identificadores, huellas y marcas
///     internas no le dicen nada a nadie y empujan fuera de la pantalla lo que sí.
///  4. **Un campo sin etiqueta conocida se dice legible, nunca con su clave.** Y hay
///     una prueba en el backend que falla si una entidad auditada escribe una clave
///     que aquí no está traducida: el hueco se descubre al añadirla, no en producción.
class AuditoriaLegible {
  const AuditoriaLegible({
    required this.nombrePorIdentidad,
    required this.nombrePorPermiso,
  });

  /// Nombres de personas por identidad, de quienes tienen acceso HOY.
  ///
  /// Quien ya no lo tiene no está aquí, y entonces se nombra por su identidad
  /// abreviada. **Nunca se oculta la fila**: una auditoría que esconde lo que no sabe
  /// nombrar deja de servir justo para lo que existe.
  final Map<String, String> nombrePorIdentidad;

  /// Nombres de permisos por código, del catálogo del servidor. Permite decir
  /// «Concedió el permiso Ver personal» en lugar de «Concedió · un permiso».
  final Map<String, String> nombrePorPermiso;

  // =========================================================================
  // El título de la fila
  // =========================================================================

  /// La frase que se lee de un barrido: **qué se hizo y sobre qué objeto, nombrado**.
  ///
  /// «Creó el área Monitoreo», no «Creó · un área». El nombre sale del propio registro
  /// —el `after` de un alta lo trae—, así que no hace falta ir a buscarlo.
  String titulo(EventoDeAuditoria e) {
    final antes = _mapa(e.antes);
    final despues = _mapa(e.despues);

    final nombre = _nombreDelObjeto(e, antes, despues);

    // LOS CASOS CON FRASE PROPIA VAN PRIMERO, porque «Concedió el permiso de acceso
    // Ver sueldo» es correcto y suena a traducción automática.
    final propia = _fraseEspecifica(e, antes, despues, nombre);
    if (propia != null) return propia;

    final verbo = _verbo(e, antes, despues);
    final objeto = _ObjetoDeAuditoria.de(e.tipoDeEntidad);

    // SIN NOMBRE SE DICE «un/una», que es la verdad: el registro no lo trae.
    if (nombre == null) return '$verbo ${objeto.indeterminado}';

    return '$verbo ${objeto.determinado} $nombre';
  }

  /// Las frases que no se construyen con «verbo + el objeto».
  String? _fraseEspecifica(
    EventoDeAuditoria e,
    Map<String, Object?> antes,
    Map<String, Object?> despues,
    String? nombre,
  ) {
    final persona = nombre ?? 'alguien';

    return switch ((e.tipoDeEntidad, e.accion)) {
      // Los accesos se cuentan en personas, no en filas: «Dio acceso a Juan Pérez».
      ('company_access', 'granted') => 'Dio acceso a $persona',
      ('company_access', 'revoked') => 'Quitó el acceso a $persona',
      ('company_access', 'role_changed') => 'Cambió el rol de $persona',

      // El permiso ya es «un permiso»: «Concedió el permiso Ver sueldo».
      ('company_access_permission', 'granted') =>
        'Concedió el permiso ${nombre ?? 'desconocido'}',
      ('company_access_permission', 'revoked') =>
        'Retiró el permiso ${nombre ?? 'desconocido'}',

      ('company_module', 'enabled') => 'Activó el módulo ${nombre ?? ''}'.trim(),
      ('company_module', 'disabled') =>
        'Desactivó el módulo ${nombre ?? ''}'.trim(),

      _ => null,
    };
  }

  /// El verbo, **derivado del cambio cuando el cambio lo dice mejor**.
  ///
  /// `status_changed` con el estado pasando a inactiva es «Desactivó», no «Cambió el
  /// estado»: la persona que lo lee quiere saber qué pasó, no qué columna se tocó.
  String _verbo(
    EventoDeAuditoria e,
    Map<String, Object?> antes,
    Map<String, Object?> despues,
  ) {
    if (e.accion == 'status_changed' || e.accion == 'updated') {
      final nuevo = despues['status'];

      if (nuevo == 'inactiva' || nuevo == 'revocada') return 'Desactivó';
      if (nuevo == 'activa' && antes['status'] != null) return 'Activó';
    }

    return _verbos[e.accion] ?? _humanizar(e.accion);
  }

  /// Cómo se llama el objeto de este hecho.
  ///
  /// Se busca donde puede estar, **en orden de utilidad**: el nombre, luego el código
  /// —un área sin nombre todavía tiene «MON»—, y para los casos que apuntan a otra
  /// cosa, lo que esa cosa se llame.
  String? _nombreDelObjeto(
    EventoDeAuditoria e,
    Map<String, Object?> antes,
    Map<String, Object?> despues,
  ) {
    switch (e.tipoDeEntidad) {
      case 'company_access':
        final id = _texto(despues['subjectIdentityId'] ?? antes['subjectIdentityId']);
        return id == null ? null : _nombreDeIdentidad(id);

      case 'company_access_permission':
        final codigo = _texto(despues['permission'] ?? antes['permission']);
        return codigo == null ? null : (nombrePorPermiso[codigo] ?? _humanizar(codigo));

      case 'company_module':
        final codigo = _texto(despues['module'] ?? antes['module']);
        return codigo == null ? null : apartados.nombreDelModulo(codigo);
    }

    return _texto(despues['name']) ??
        _texto(antes['name']) ??
        _texto(despues['code']) ??
        _texto(antes['code']);
  }

  /// Cómo se nombra a quien actuó, o a quien se le hizo algo.
  ///
  /// Tres casos y ninguno «desconocido»: quien sigue teniendo acceso tiene nombre;
  /// quien ya no, se muestra por su identidad abreviada —ocho caracteres bastan para
  /// distinguirla y para buscarla—.
  String _nombreDeIdentidad(String id) =>
      nombrePorIdentidad[id] ??
      'una identidad (${id.length >= 8 ? id.substring(0, 8) : id}…)';

  /// Quién lo hizo.
  String actor(EventoDeAuditoria e) {
    final id = e.identidadDelActor;
    if (id != null) return _nombreDeIdentidad(id);

    return switch (e.tipoDeActor) {
      'identity' => 'Una persona (sin identificar)',
      'system' => 'El sistema',
      'integration' => 'Una integración',
      'seventra_operator' => 'Soporte de SEVENTRA',
      _ => _humanizar(e.tipoDeActor),
    };
  }

  // =========================================================================
  // El detalle
  // =========================================================================

  /// Los campos del detalle, ya traducidos.
  ///
  /// **Con antes y después, sólo los que cambiaron.** Con uno solo —un alta no tiene
  /// antes—, los que trae, sin los técnicos.
  List<CampoLegible> campos(EventoDeAuditoria e) {
    final antes = _mapa(e.antes);
    final despues = _mapa(e.despues);

    final campos = <CampoLegible>[];

    // EL MOTIVO VA PRIMERO cuando lo hay: es lo que una persona escribió a mano, y es
    // lo más informativo de todo el registro.
    if (e.motivo case final m? when m.trim().isNotEmpty) {
      campos.add(
        CampoLegible(
          etiqueta: 'Motivo',
          despues: ValorLegible.texto(m.trim()),
        ),
      );
    }

    final hayDosLados = antes.isNotEmpty && despues.isNotEmpty;

    // LAS CLAVES DE LOS DOS LADOS, sin repetir y en el orden en que vinieron: el
    // servidor las escribe en el orden en que importan.
    final claves = <String>[
      ...despues.keys,
      ...antes.keys.where((k) => !despues.containsKey(k)),
    ];

    for (final clave in claves) {
      if (_esTecnico(clave)) continue;

      // ESTOS DOS YA ESTÁN EN EL TÍTULO. Repetirlos abajo es ruido, y en el caso de
      // `subjectIdentityId` sería además un identificador crudo.
      if (_yaEstaEnElTitulo(e, clave)) continue;

      final valorAntes = antes[clave];
      final valorDespues = despues[clave];

      // SÓLO LO QUE CAMBIÓ, cuando hay con qué comparar.
      if (hayDosLados && _mismoValor(valorAntes, valorDespues)) continue;

      campos.add(
        CampoLegible(
          etiqueta: etiquetaDe(clave),
          antes: valorAntes == null ? null : _valor(clave, valorAntes),
          despues: valorDespues == null ? null : _valor(clave, valorDespues),
        ),
      );
    }

    return campos;
  }

  /// El aviso de que un detalle no se pudo interpretar, **en palabras**.
  ///
  /// Devuelve `null` cuando todo fue bien. **No existe un camino que vuelque el JSON**:
  /// si llegara algo con otra forma, la pantalla lo dice y ya. Una consola dentro de la
  /// auditoría no ayuda a quien la está leyendo.
  String? avisoDeFormato(EventoDeAuditoria e) {
    final roto =
        (e.antes != null && _mapaONulo(e.antes) == null) ||
        (e.despues != null && _mapaONulo(e.despues) == null);

    return roto
        ? 'El detalle de este registro llegó en un formato que esta pantalla todavía '
              'no reconoce. El hecho quedó guardado completo.'
        : null;
  }

  bool _yaEstaEnElTitulo(EventoDeAuditoria e, String clave) =>
      (e.tipoDeEntidad == 'company_access' && clave == 'subjectIdentityId') ||
      (e.tipoDeEntidad == 'company_access_permission' && clave == 'permission') ||
      (e.tipoDeEntidad == 'company_module' && clave == 'module');

  // =========================================================================
  // Valores
  // =========================================================================

  ValorLegible _valor(String clave, Object? valor) {
    // UN ESTADO ES UN CHIP, no un texto: color más ícono, para que quien no distinga
    // verde de gris siga viendo la diferencia.
    if (clave == 'status' && valor is String) return ValorLegible.estado(valor);

    if (valor is bool) return ValorLegible.texto(valor ? 'Sí' : 'No');

    if (clave == 'role' && valor is String) {
      return ValorLegible.texto(_roles[valor] ?? _humanizar(valor));
    }

    if (clave == 'module' && valor is String) {
      return ValorLegible.texto(apartados.nombreDelModulo(valor));
    }

    if (clave == 'permission' && valor is String) {
      return ValorLegible.texto(nombrePorPermiso[valor] ?? _humanizar(valor));
    }

    if (clave == 'kind' && valor is String) {
      return ValorLegible.texto(_tiposDePuesto[valor] ?? _humanizar(valor));
    }

    // LAS FECHAS, EN dd/mmm/aaaa. Se detectan por la clave Y por la forma del valor:
    // sólo por la clave, un `starts_on` con un texto raro se rompería al interpretarlo.
    if (valor is String && _pareceFecha(clave, valor)) {
      final fecha = DateTime.tryParse(valor);
      if (fecha != null) return ValorLegible.fecha(_fechaCorta(fecha));
    }

    if (valor is String) return ValorLegible.texto(valor);
    if (valor is num) return ValorLegible.texto(valor.toString());

    // UNA LISTA O UN OBJETO ANIDADO NO SE VUELCA. Se dice cuántos hay, que es lo
    // único que una persona puede usar sin leer JSON.
    if (valor is List) {
      return ValorLegible.texto(
        valor.length == 1 ? '1 elemento' : '${valor.length} elementos',
      );
    }

    return ValorLegible.texto('(sin detalle legible)');
  }

  static bool _pareceFecha(String clave, String valor) =>
      (clave.endsWith('_on') || clave.endsWith('_at') || clave.contains('date')) &&
      RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(valor);

  /// `18/oct/2026`. El mes **en letras y abreviado** a propósito: `18/10/2026` y
  /// `10/18/2026` se confunden, y tres letras no se confunden con nada.
  static String _fechaCorta(DateTime d) {
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];

    return '${d.day.toString().padLeft(2, '0')}/${meses[d.month - 1]}/${d.year}';
  }

  // =========================================================================
  // Etiquetas
  // =========================================================================

  /// La etiqueta en español de una clave del registro.
  ///
  /// **Pública para que una prueba pueda recorrer el vocabulario entero** y afirmar que
  /// ninguna clave de las entidades auditadas cae en el respaldo.
  static String etiquetaDe(String clave) => _etiquetas[clave] ?? _humanizar(clave);

  /// ¿Tiene esta clave una etiqueta propia, o caería en el respaldo?
  ///
  /// Lo usa la prueba del vocabulario. El respaldo **es legible** —nunca la clave
  /// cruda— pero no es español: `created_count` saldría «Created count».
  static bool tieneEtiqueta(String clave) => _etiquetas.containsKey(clave);

  /// ¿Es una clave técnica, que no se muestra?
  ///
  /// Identificadores, huellas y marcas internas. **`area_code` no es un identificador**
  /// y sobrevive a este filtro a propósito: es el código que el cliente escribió y
  /// reconoce.
  static bool _esTecnico(String clave) {
    if (clave == 'id') return true;
    if (clave.endsWith('_id') || clave.endsWith('Id')) return true;

    const fragmentos = ['hash', 'checksum', 'secret', 'token', 'salt', 'fingerprint'];

    final minuscula = clave.toLowerCase();
    return fragmentos.any(minuscula.contains);
  }

  /// El respaldo: una clave convertida en algo que se puede leer.
  ///
  /// `created_count` → «Created count». No es español, y por eso existe la prueba que
  /// exige que ninguna entidad auditada llegue aquí. Pero **es legible**, y entre esto
  /// y mostrar `created_count` no hay duda.
  static String _humanizar(String clave) {
    final conEspacios = clave
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase()
        .trim();

    if (conEspacios.isEmpty) return clave;

    return conEspacios[0].toUpperCase() + conEspacios.substring(1);
  }

  // =========================================================================
  // Vocabularios
  // =========================================================================

  /// Las claves de los registros, en español.
  ///
  /// **Están TODAS las de las entidades que esta etapa audita** —empresa, acceso,
  /// permiso de acceso, módulo, área, puesto, sucursal y tipo de sucursal—, y una
  /// prueba del backend falla si alguna de ellas escribe una clave que no esté aquí.
  ///
  /// Las demás se añaden **cuando su módulo se muda**, igual que `apartados_web.dart`: no
  /// se inventa el texto oficial de un campo cuya pantalla no existe.
  static const Map<String, String> _etiquetas = {
    // --- Comunes a casi todo ---------------------------------------------
    'code': 'Código',
    'name': 'Nombre',
    'status': 'Estado',
    'reason': 'Motivo',

    // --- Empresa ----------------------------------------------------------
    'protectedPermissionsGranted': 'Permisos protegidos concedidos',

    // --- Acceso y permisos ------------------------------------------------
    'role': 'Rol',
    'permission': 'Permiso',

    // --- Módulos ----------------------------------------------------------
    'module': 'Módulo',
    'enabled': 'Habilitado',

    // --- Estructura -------------------------------------------------------
    'kind': 'Tipo',
    'area_code': 'Área',
    'recommended': 'De los recomendados',
    'created_count': 'Cuántos se crearon',
  };

  /// Los verbos. Vocabulario **cerrado y corto** —los de `AuditAction`—, así que
  /// traducirlos entero es razonable y no promete nada que no se pueda cumplir.
  static const Map<String, String> _verbos = {
    'created': 'Creó',
    'updated': 'Cambió',
    'deleted': 'Borró',
    'granted': 'Concedió',
    'revoked': 'Retiró',
    'role_changed': 'Cambió el rol de',
    'enabled': 'Activó',
    'disabled': 'Desactivó',
    'initiated': 'Inició',
    'accepted': 'Aceptó',
    'cancelled': 'Canceló',
    'activated': 'Activó',
    'status_changed': 'Cambió el estado de',
    'replaced': 'Reemplazó',
    'corrected': 'Corrigió',
    'uploaded': 'Subió',
    'attached': 'Vinculó',
    'detached': 'Desvinculó',
  };

  static const Map<String, String> _roles = {
    'maestro': 'Maestro',
    'user': 'Usuario',
  };

  static const Map<String, String> _tiposDePuesto = {
    'operativo': 'Operativo',
    'administrativo': 'Administrativo',
  };

  // =========================================================================
  // JSON, que no sale de aquí
  // =========================================================================

  /// Decodifica un lado del registro. **Un texto ilegible devuelve un mapa vacío**, no
  /// una excepción y no el texto: ningún camino de esta clase deja escapar el JSON.
  static Map<String, Object?> _mapa(String? json) => _mapaONulo(json) ?? const {};

  static Map<String, Object?>? _mapaONulo(String? json) {
    if (json == null || json.trim().isEmpty) return const {};

    try {
      final decodificado = jsonDecode(json);
      return decodificado is Map<String, Object?> ? decodificado : null;
    } on FormatException {
      return null;
    }
  }

  static String? _texto(Object? valor) {
    if (valor is! String) return null;
    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  /// Igualdad para decidir si un campo cambió. **Compara el texto**, porque el JSON
  /// puede traer `1` donde antes había `1.0` y eso no es un cambio que nadie quiera
  /// leer.
  static bool _mismoValor(Object? a, Object? b) =>
      a == b || (a != null && b != null && a.toString() == b.toString());
}

// ===========================================================================
// Cómo se nombra cada objeto auditado
// ===========================================================================

/// El sustantivo de una entidad, **con su artículo**, para poder escribir una frase.
///
/// El género hace falta: «la sucursal», «el área». Sin él saldría «el sucursal», que
/// es justo la clase de detalle que hace que una pantalla parezca traducida a máquina.
class _ObjetoDeAuditoria {
  const _ObjetoDeAuditoria(this.determinado, this.indeterminado);

  /// «el área», «la sucursal». Para cuando hay nombre: «Creó el área Monitoreo».
  final String determinado;

  /// «un área», «una sucursal». Para cuando el registro no trae nombre.
  final String indeterminado;

  static _ObjetoDeAuditoria de(String tipoDeEntidad) =>
      _conocidos[tipoDeEntidad] ?? _desconocido(tipoDeEntidad);

  static const Map<String, _ObjetoDeAuditoria> _conocidos = {
    'company': _ObjetoDeAuditoria('la empresa', 'la empresa'),
    'company_access': _ObjetoDeAuditoria('el acceso de', 'un acceso'),
    'company_access_permission': _ObjetoDeAuditoria('el permiso', 'un permiso'),
    'company_module': _ObjetoDeAuditoria('el módulo', 'un módulo'),
    'area': _ObjetoDeAuditoria('el área', 'un área'),
    'position': _ObjetoDeAuditoria('el puesto', 'un puesto'),
    'branch': _ObjetoDeAuditoria('la sucursal', 'una sucursal'),
    'branch_type': _ObjetoDeAuditoria('el tipo de sucursal', 'un tipo de sucursal'),
    'employee': _ObjetoDeAuditoria('al empleado', 'un empleado'),
    'person': _ObjetoDeAuditoria('a la persona', 'una persona'),
    'client': _ObjetoDeAuditoria('al cliente', 'un cliente'),
    'service': _ObjetoDeAuditoria('el servicio', 'un servicio'),
    'contract': _ObjetoDeAuditoria('el contrato', 'un contrato'),
  };

  /// Una entidad que todavía no tiene frase. **Se nombra legible, nunca con su código
  /// crudo**: `subscription_extra` sale «el registro de tipo Subscription extra».
  ///
  /// Es fea a propósito — es la señal visible de que falta traducirla— y sigue siendo
  /// infinitamente mejor que esconder la fila.
  static _ObjetoDeAuditoria _desconocido(String tipoDeEntidad) {
    final legible = AuditoriaLegible.etiquetaDe(tipoDeEntidad);

    return _ObjetoDeAuditoria(
      'el registro de tipo $legible,',
      'un registro de tipo $legible',
    );
  }
}

// ===========================================================================
// Lo que la pantalla pinta
// ===========================================================================

/// Un campo del detalle, ya en español.
///
/// Con [antes] y [despues] es un cambio y se lee «Nombre: Monitoreo → Monitoreo
/// central». Con sólo uno de los dos es un valor, de un alta o de una baja.
class CampoLegible {
  const CampoLegible({required this.etiqueta, this.antes, this.despues});

  final String etiqueta;
  final ValorLegible? antes;
  final ValorLegible? despues;

  bool get esCambio => antes != null && despues != null;
}

/// Cómo se pinta un valor. El widget decide la forma; aquí se decide **qué es**.
enum FormaDeValor {
  texto,

  /// Un estado: chip con color e ícono.
  estado,

  /// Una fecha ya formateada como `18/oct/2026`.
  fecha,
}

class ValorLegible {
  const ValorLegible._(this.texto, this.forma, {this.estadoCrudo});

  factory ValorLegible.texto(String texto) =>
      ValorLegible._(texto, FormaDeValor.texto);

  factory ValorLegible.fecha(String texto) =>
      ValorLegible._(texto, FormaDeValor.fecha);

  /// Un estado. Guarda **el código crudo además del texto** porque el color y el ícono
  /// se eligen por el código, no por la traducción.
  factory ValorLegible.estado(String codigo) => ValorLegible._(
    _estados[codigo] ?? AuditoriaLegible.etiquetaDe(codigo),
    FormaDeValor.estado,
    estadoCrudo: codigo,
  );

  final String texto;
  final FormaDeValor forma;
  final String? estadoCrudo;

  static const Map<String, String> _estados = {
    'activa': 'Activa',
    'inactiva': 'Inactiva',
    'revocada': 'Revocada',
    'draft': 'Borrador',
  };
}
