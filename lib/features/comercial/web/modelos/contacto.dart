/// Un contacto de un cliente: con quién se habla, y para qué.
///
/// ## ⚠️ EN LA NUBE UN CONTACTO SE ELIMINA, NO SE ARCHIVA
///
/// El escritorio lo archiva y el archivado desaparece de la vista. Aquí se **borra**, y es
/// del contrato: «los contactos y los portales sí se borran: no son historia de nada, y
/// son listas donde una fila capturada por error no se puede corregir sobrescribiendo».
///
/// Lo que no cambia es el rastro: **eliminar pide motivo**, y el evento de la bitácora se
/// queda con el nombre, el tipo, si era principal y las vías de contacto **enmascaradas**
/// —`•••• 5678`, `an•••@sportium.mx`—. Es lo único que quedará de la fila, y con los
/// valores completos la bitácora se convertiría en un segundo directorio de la cartera.
///
/// ## Y no se elimina si es responsable de un servicio
///
/// El servidor lo bloquea **nombrando el servicio** —«Este contacto es responsable del
/// servicio SRV-0001 Torre Norte. Cambia el responsable antes de eliminarlo.»— en lugar de
/// contestar «está en uso», que no le dice a nadie dónde ir.
class ContactoDeCliente {
  const ContactoDeCliente({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.puesto,
    required this.telefono,
    required this.correo,
    required this.esPrincipal,
    required this.observaciones,
  });

  factory ContactoDeCliente.deJson(Map<String, dynamic> json) =>
      ContactoDeCliente(
        id: json['id'] as String,
        nombre: json['name'] as String,
        tipo: json['kind'] as String,
        puesto: json['role'] as String?,
        telefono: json['phone'] as String?,
        correo: json['email'] as String?,
        esPrincipal: json['isPrimary'] as bool,
        observaciones: json['notes'] as String?,
      );

  final String id;
  final String nombre;

  /// El código del servidor: `comercial`, `operativo` o `cobranza`.
  ///
  /// Se guarda crudo por lo mismo que el estatus de un cliente: un tipo que esta build no
  /// conozca —porque el servidor sea más nuevo— se enseña tal cual, en vez de caer en
  /// «comercial» por omisión y decir algo falso.
  final String tipo;

  final String? puesto;
  final String? telefono;
  final String? correo;

  /// ¿Es **el principal de su tipo**?
  ///
  /// Hay como máximo uno por tipo, y el servidor lo impone con un índice único. Designar a
  /// otro le quita la marca al anterior **del mismo tipo**, así que el principal de
  /// cobranza y el comercial coexisten — y eso es el punto: la facturación manda el
  /// documento al de cobranza, que no es el comercial.
  final bool esPrincipal;

  final String? observaciones;

  /// El tipo reconocido, o nulo si llegó uno que esta build no conoce.
  TipoDeContacto? get comoTipo => TipoDeContacto.deCodigo(tipo);

  /// «5512345678 · ana@sportium.mx», con lo que haya. **Nunca una cadena vacía**: el
  /// servidor exige al menos uno de los dos, así que siempre hay algo que decir.
  String get vias => [
    if ((telefono ?? '').trim().isNotEmpty) telefono!.trim(),
    if ((correo ?? '').trim().isNotEmpty) correo!.trim(),
  ].join(' · ');
}

/// Los **tres** tipos de contacto, con su código y para qué sirve cada uno.
///
/// ## El tercero no está en el escritorio
///
/// El escritorio tiene dos —comercial y operativo— y **cobranza lo añadiste tú** el 25 de
/// octubre de 2026. La razón es de facturación: el documento de cobro se manda a los
/// correos de los contactos, y **a quien se le cobra no es con quien se negocia**. Sin el
/// tercer tipo, la factura acabaría en el buzón del comercial.
enum TipoDeContacto {
  comercial('comercial', 'Comercial', 'Con quien se negocia.'),
  operativo('operativo', 'Operativo', 'Con quien se resuelve el día a día.'),
  cobranza('cobranza', 'Cobranza', 'A quien se le manda la factura y con quien se cobra.');

  const TipoDeContacto(this.codigo, this.nombre, this.paraQue);

  /// El código del servidor. Es el que viaja.
  final String codigo;

  final String nombre;

  /// Para qué sirve, en una línea. Va en el selector: sin esto, «comercial» y
  /// «cobranza» se eligen al azar la primera vez.
  final String paraQue;

  static TipoDeContacto? deCodigo(String codigo) {
    for (final t in values) {
      if (t.codigo == codigo) return t;
    }

    return null;
  }
}
