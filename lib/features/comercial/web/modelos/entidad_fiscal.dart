/// Una razón social con la que se factura a este cliente.
///
/// **`Client != FiscalEntity`**, y es una de las fronteras que no se colapsan: el cliente
/// es la marca —«Sportium»— y sus entidades fiscales son con quién se factura. Puede tener
/// varias, porque Sportium factura distinto por club.
///
/// ## Qué cambió respecto al escritorio, y lo decidiste tú
///
/// - **El RFC es opcional y único por CLIENTE.** En el escritorio es obligatorio y único
///   en todo el sistema. Opcional porque la constancia del cliente llega después del alta;
///   único por cliente —y no global— porque el mismo RFC en otro cliente **es legal y a
///   veces correcto**: dos marcas de la misma empresa legal. Lo que hace el servidor con
///   eso es **avisar sin bloquear** ([AvisoDeRfc]).
/// - **Gana el régimen fiscal**, contra el catálogo del SAT, también opcional. Para
///   **emitir** un CFDI los tres son obligatorios —RFC, régimen y código postal fiscal—, y
///   eso es el compromiso CP-13.
///
/// ## Se ARCHIVA, no se borra
///
/// Con una entidad fiscal se emitieron facturas, así que retirarla de circulación es
/// `status: 'archived'`. **Una archivada no se edita** hasta reactivarla, y el servidor
/// responde 409 `entidad_fiscal_archivada` a quien lo intente.
class EntidadFiscal {
  const EntidadFiscal({
    required this.id,
    required this.razonSocial,
    required this.rfc,
    required this.regimenFiscal,
    required this.observaciones,
    required this.estatus,
  });

  factory EntidadFiscal.deJson(Map<String, dynamic> json) => EntidadFiscal(
    id: json['id'] as String,
    razonSocial: json['legalName'] as String,
    rfc: json['taxId'] as String?,
    regimenFiscal: json['fiscalRegimeCode'] as String?,
    observaciones: json['notes'] as String?,
    estatus: json['status'] as String,
  );

  final String id;
  final String razonSocial;
  final String? rfc;

  /// El código del régimen —`601`—, no su nombre. El nombre sale del catálogo, y por eso
  /// la pantalla necesita las dos cosas para poder escribir «601 · General de Ley
  /// Personas Morales».
  final String? regimenFiscal;

  final String? observaciones;

  /// `active` o `archived`.
  final String estatus;

  bool get estaActiva => estatus == 'active';

  /// ¿Le falta algo para poder **facturar**? (CP-13)
  ///
  /// El domicilio fiscal no se mira aquí —viaja en otra ruta— así que esto responde por lo
  /// que la entidad sí sabe de sí misma. Quien conoce el domicilio compone el aviso
  /// completo.
  bool get leFaltanDatosFiscales => rfc == null || regimenFiscal == null;
}

/// El aviso de **RFC repetido en otro cliente**.
///
/// ## No es un error: la petición se guardó
///
/// El RFC es único por cliente, así que el mismo RFC en otro cliente **es legal** —dos
/// marcas de la misma empresa legal— y también es el síntoma de un cliente capturado dos
/// veces. **Sólo quien está capturando puede distinguirlo**, así que el servidor pregunta
/// después de guardar y se lo dice.
///
/// Por eso trae **los clientes con su folio y su nombre**: «ese RFC ya existe» sin decir
/// dónde obliga a buscarlo a mano en toda la cartera.
class AvisoDeRfc {
  const AvisoDeRfc({
    required this.codigo,
    required this.mensaje,
    required this.clientes,
  });

  factory AvisoDeRfc.deJson(Map<String, dynamic> json) => AvisoDeRfc(
    codigo: json['code'] as String,
    mensaje: json['message'] as String,
    clientes: [
      for (final c in json['clients'] as List)
        ClienteConEseRfc.deJson(c as Map<String, dynamic>),
    ],
  );

  final String codigo;

  /// El texto del servidor. **Se muestra tal cual**: explica las dos posibilidades mejor
  /// que una frase local, y es la misma en todas las pantallas.
  final String mensaje;

  final List<ClienteConEseRfc> clientes;
}

/// Un cliente que ya tiene ese RFC, **con su folio**, para poder ir a verlo.
class ClienteConEseRfc {
  const ClienteConEseRfc({required this.codigo, required this.nombreComercial});

  factory ClienteConEseRfc.deJson(Map<String, dynamic> json) => ClienteConEseRfc(
    codigo: json['code'] as String,
    nombreComercial: json['commercialName'] as String,
  );

  final String codigo;
  final String nombreComercial;

  String get etiqueta => '$codigo · $nombreComercial';
}

/// Lo que responden el alta y la corrección de una entidad fiscal: **la entidad y el
/// aviso**.
///
/// ## Por qué un sobre y no un campo más en la entidad
///
/// Es la decisión del servidor y vale igual aquí: el aviso **sólo existe cuando se acaba de
/// guardar algo**. Añadírselo a la entidad pondría un `warning: null` en cada fila de cada
/// listado, y un campo que casi siempre es nulo deja de leerse. Aquí **nulo dice algo**: se
/// comprobó y no hay nada.
class EntidadFiscalGuardada {
  const EntidadFiscalGuardada({required this.entidad, required this.aviso});

  factory EntidadFiscalGuardada.deJson(Map<String, dynamic> json) =>
      EntidadFiscalGuardada(
        entidad: EntidadFiscal.deJson(
          json['fiscalEntity'] as Map<String, dynamic>,
        ),
        aviso: json['warning'] == null
            ? null
            : AvisoDeRfc.deJson(json['warning'] as Map<String, dynamic>),
      );

  final EntidadFiscal entidad;

  /// Nulo significa **«se comprobó y no hay nada»**, no «no se comprobó».
  final AvisoDeRfc? aviso;
}
