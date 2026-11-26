/// Un **portal del cliente**: por dónde se le sube una factura o se le da de alta como
/// proveedor, con su usuario y su contraseña.
///
/// ## Lo que el escritorio NO puede hacer, y aquí sí
///
/// 🔑 **Ver la contraseña.** En RISEG ONE escritorio **no existe revelar** —es su duda 12—,
/// así que la contraseña de un portal de cliente no se puede consultar en ninguna pantalla:
/// quien la necesita la tiene apuntada en otro sitio, que es exactamente lo que un gestor de
/// credenciales viene a evitar. C4 lo cierra: existe **Mostrar** y **Copiar**, cada uno con
/// su evento en la bitácora y detrás de un permiso propio.
///
/// ## La contraseña no viaja en esta ficha, y es a propósito
///
/// Este objeto dice **si hay** contraseña y **cuándo** se cambió, nunca cuál es. El listado
/// del servidor no la trae —ni cifrada—, así que no hay forma de que aparezca por descuido en
/// una fila, en un registro de red o en una captura de pantalla. Quien la necesita la pide
/// por su propia ruta, que descifra **una vez por acto**.
///
/// ## Se ARCHIVA, no se borra
///
/// Una vigencia de cobro vieja —y un documento ya emitido— siguen citando el portal por el
/// que se subió una factura, así que retirarlo es `status: 'archived'`. **Un portal archivado
/// es sólo consulta**: no se corrige, no se le cambia ni se le borra la contraseña, y **sí se
/// puede revelar la que tiene**, porque consultar un acceso retirado es legítimo.
class PortalDeCliente {
  const PortalDeCliente({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.url,
    required this.usuario,
    required this.observaciones,
    required this.estatus,
    required this.tieneContrasena,
    required this.contrasenaCambiadaEl,
  });

  factory PortalDeCliente.deJson(Map<String, dynamic> json) => PortalDeCliente(
    id: json['id'] as String,
    nombre: json['name'] as String,
    tipo: json['kind'] as String,
    url: json['url'] as String?,
    usuario: json['username'] as String?,
    observaciones: json['notes'] as String?,
    estatus: json['status'] as String,
    tieneContrasena: json['hasSecret'] as bool,
    contrasenaCambiadaEl: json['secretUpdatedAt'] == null
        ? null
        : DateTime.parse(json['secretUpdatedAt'] as String),
  );

  final String id;
  final String nombre;

  /// `billing`, `suppliers`, `payments` u `other`.
  final String tipo;

  final String? url;
  final String? usuario;
  final String? observaciones;

  /// `active` o `archived`.
  final String estatus;

  /// Si hay una contraseña guardada. **No es la contraseña**, y nada en esta ficha lo es.
  final bool tieneContrasena;

  /// Cuándo se cambió por última vez, o nulo si no hay ninguna. Los dos campos van juntos
  /// porque el servidor los guarda juntos: o están los tres del secreto o no está ninguno.
  final DateTime? contrasenaCambiadaEl;

  bool get estaActivo => estatus == 'active';

  /// Cómo se llama su tipo en pantalla.
  ///
  /// ⚠️ **Un tipo que no esté en la lista se enseña TAL CUAL y no como «Otro»**: si el
  /// servidor añadiera un quinto, traducirlo a «Otro» lo haría indistinguible del que de
  /// verdad es «Otro», y nadie notaría que falta un caso.
  String get nombreDelTipo => switch (tipo) {
    'billing' => 'Facturación',
    'suppliers' => 'Proveedores',
    'payments' => 'Pagos',
    'other' => 'Otro',
    _ => tipo,
  };
}

/// Los cuatro tipos de portal, para el selector del formulario.
///
/// Es la **misma lista cerrada** del servidor: un tipo que no esté aquí se rechaza con un
/// 400, así que ofrecerlo sería ofrecer un error.
const tiposDePortal = <String, String>{
  'billing': 'Facturación',
  'suppliers': 'Proveedores',
  'payments': 'Pagos',
  'other': 'Otro',
};

/// Los dos actos con los que se revela una contraseña.
///
/// 🔑 **Son dos actos y dos eventos, y una sola ruta.** Mostrarla y copiarla exigen el mismo
/// permiso y descifran igual; lo que cambia es **el hecho que queda en la bitácora**, porque
/// copiarla la saca de la pantalla y adónde va después no lo sabe nadie.
///
/// 🚫 **Lista cerrada y sin comodín.** El servidor rechaza cualquier otro valor con un 400,
/// así que inventar un tercer acto aquí sería inventar un error.
class ActoDeRevelar {
  const ActoDeRevelar._();

  static const String mostrar = 'mostrar';
  static const String copiar = 'copiar';
}
