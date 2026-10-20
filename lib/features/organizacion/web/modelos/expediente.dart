/// Los dos expedientes —empresa y sucursal— tal como los devuelve la API.
///
/// **LO QUE EL SERVIDOR YA DERIVÓ, AQUÍ NO SE VUELVE A CALCULAR.** Son tres cosas y
/// cada una tiene su razón:
///
///  · `fiscalCardReady` —si la tarjeta fiscal se puede generar— la decide el servidor,
///    porque la lista de indispensables es una regla del dominio y el producto local la
///    tiene «en un solo sitio, nunca duplicada en la UI». Dos listas discreparían, y la
///    tarjeta luciría completa sin estarlo;
///  · `crossesMidnight` de un tramo, por lo mismo: la pantalla no debe equivocarse
///    restando minutos;
///  · `selectable` de un régimen en vez de su `status`: la pantalla no tiene que saber
///    qué significa «inactiva», sólo si puede ofrecerlo.
library;

/// Un domicilio. **La misma forma en los seis sitios** que la usan, a propósito.
///
/// Siete campos obligatorios y cuatro opcionales, y la frontera la impone el motor:
/// «cuatro direcciones del mismo sistema que validaran distinto serían un defecto, no
/// una flexibilidad».
class Direccion {
  const Direccion({
    required this.calle,
    required this.numeroExterior,
    required this.colonia,
    required this.municipio,
    required this.estado,
    required this.codigoPostal,
    this.numeroInterior,
    this.ciudad,
    this.pais,
    this.referencias,
  });

  factory Direccion.deJson(Map<String, dynamic> json) => Direccion(
    calle: json['street'] as String,
    numeroExterior: json['exteriorNumber'] as String,
    colonia: json['neighborhood'] as String,
    municipio: json['municipality'] as String,
    estado: json['state'] as String,
    codigoPostal: json['postalCode'] as String,
    numeroInterior: json['interiorNumber'] as String?,
    ciudad: json['city'] as String?,
    pais: json['country'] as String?,
    referencias: json['landmarks'] as String?,
  );

  final String calle;
  final String numeroExterior;
  final String colonia;
  final String municipio;
  final String estado;
  final String codigoPostal;
  final String? numeroInterior;
  final String? ciudad;
  final String? pais;
  final String? referencias;

  Map<String, dynamic> aJson() => {
    'street': calle,
    'exteriorNumber': numeroExterior,
    'interiorNumber': numeroInterior,
    'neighborhood': colonia,
    'municipality': municipio,
    'city': ciudad,
    'state': estado,
    'postalCode': codigoPostal,
    'country': pais,
    'landmarks': referencias,
  };

  /// En una línea, para la tarjeta de resumen. **El interior sólo si existe**: un
  /// «Int. » suelto se lee como un dato que falta.
  String get enUnaLinea {
    final interior = (numeroInterior ?? '').trim();
    final numero = interior.isEmpty
        ? numeroExterior
        : '$numeroExterior Int. $interior';

    return '$calle $numero, $colonia, $municipio, $estado, C.P. $codigoPostal';
  }
}

/// Teléfono, correo y sitio. Los tres opcionales.
class Contacto {
  const Contacto({this.telefono, this.correo, this.sitio});

  factory Contacto.deJson(Map<String, dynamic> json) => Contacto(
    telefono: json['phone'] as String?,
    correo: json['email'] as String?,
    sitio: json['website'] as String?,
  );

  final String? telefono;
  final String? correo;
  final String? sitio;

  Map<String, dynamic> aJson() => {
    'phone': telefono,
    'email': correo,
    'website': sitio,
  };

  /// ¿Está vacío del todo? El servidor **no guarda** un contacto así, y la pantalla
  /// necesita saberlo para no decir «guardado» de algo que no se escribió.
  bool get estaVacio => [telefono, correo, sitio].every(
    (x) => x == null || x.trim().isEmpty,
  );
}

/// Un tramo del horario semanal: «el martes de 9 a 14».
///
/// **`fin` LLEGA A 1440 Y NUNCA ES 0.** «Cierra a medianoche» son 1440 minutos; un 0
/// significaría un tramo de duración cero. El producto local guardaba `fin = 0` y lo
/// infería — aquí se guarda lo que es.
class TramoDeHorario {
  const TramoDeHorario({
    required this.dia,
    required this.inicio,
    required this.fin,
    required this.cruzaMedianoche,
  });

  factory TramoDeHorario.deJson(Map<String, dynamic> json) => TramoDeHorario(
    dia: json['dayOfWeek'] as int,
    inicio: json['startMinute'] as int,
    fin: json['endMinute'] as int,
    cruzaMedianoche: json['crossesMidnight'] as bool,
  );

  /// El que viene de la pantalla. Dos cosas pasan aquí **y en ningún otro sitio**:
  ///
  ///  · **el fin `0` se convierte en 1440.** El selector de hora del escritorio
  ///    devuelve un `TimeOfDay`, que no puede valer 24:00; cuando alguien elige las
  ///    00:00 como cierre, lo que quiere decir es medianoche. Y no es ambiguo: un
  ///    tramo de 22:00 a 00:00 son dos horas, y «hasta las 00:00 de pasado mañana» no
  ///    significa nada. El servidor **rechaza** un fin de 0 con un mensaje que nombra
  ///    el 24:00, así que sin esta conversión la pantalla ofrecería una hora imposible;
  ///  · el cruce se calcula **sólo para pintar**. Al mandar no se envía: lo deriva el
  ///    servidor, que es quien manda.
  factory TramoDeHorario.nuevo({
    required int dia,
    required int inicio,
    required int fin,
  }) {
    final cierre = fin == 0 ? 1440 : fin;

    return TramoDeHorario(
      dia: dia,
      inicio: inicio,
      fin: cierre,
      cruzaMedianoche: cierre != 1440 && cierre <= inicio,
    );
  }

  /// 1 = lunes … 7 = domingo.
  final int dia;
  final int inicio;
  final int fin;

  /// Lo **derivó el servidor**. Un tramo de 22:00 a 06:00 cruza; uno de 00:00 a 24:00
  /// no, aunque termine en medianoche.
  final bool cruzaMedianoche;

  Map<String, dynamic> aJson() => {
    'dayOfWeek': dia,
    'startMinute': inicio,
    'endMinute': fin,
  };

  /// `9:00` · `14:30` · y **`24:00` para el 1440**, que es el único valor que no se
  /// puede mostrar como hora del reloj sin mentir.
  static String comoHora(int minuto) {
    final h = (minuto ~/ 60).toString().padLeft(2, '0');
    final m = (minuto % 60).toString().padLeft(2, '0');

    return '$h:$m';
  }

  String get horario => '${comoHora(inicio)} – ${comoHora(fin)}';

  static const nombresDeDia = [
    '',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  String get nombreDelDia =>
      dia >= 1 && dia <= 7 ? nombresDeDia[dia] : 'Día $dia';
}

/// Un régimen fiscal del catálogo del SAT.
class RegimenFiscal {
  const RegimenFiscal({
    required this.codigo,
    required this.nombre,
    required this.personaFisica,
    required this.personaMoral,
    required this.seleccionable,
  });

  factory RegimenFiscal.deJson(Map<String, dynamic> json) => RegimenFiscal(
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    personaFisica: json['personaFisica'] as bool,
    personaMoral: json['personaMoral'] as bool,
    seleccionable: json['selectable'] as bool,
  );

  final String codigo;
  final String nombre;
  final bool personaFisica;
  final bool personaMoral;

  /// ¿Se puede elegir hoy? Un régimen **retirado por el SAT** llega con `false`, y la
  /// empresa que ya lo tenía **lo conserva**: su tarjeta fiscal sigue diciendo la
  /// verdad. Lo que no se puede es elegirlo para algo nuevo.
  final bool seleccionable;

  String get etiqueta => '$codigo · $nombre';
}

/// El expediente de la empresa.
class ExpedienteDeEmpresa {
  const ExpedienteDeEmpresa({
    required this.empresaId,
    required this.nombre,
    required this.version,
    required this.tarjetaFiscalLista,
    this.razonSocial,
    this.rfc,
    this.representanteLegal,
    this.eslogan,
    this.regimenFiscal,
    this.direccion,
    this.contacto,
  });

  factory ExpedienteDeEmpresa.deJson(Map<String, dynamic> json) =>
      ExpedienteDeEmpresa(
        empresaId: json['companyId'] as String,
        nombre: json['name'] as String,
        razonSocial: json['legalName'] as String?,
        rfc: json['taxId'] as String?,
        representanteLegal: json['legalRep'] as String?,
        eslogan: json['slogan'] as String?,
        regimenFiscal: json['fiscalRegimeCode'] as String?,
        direccion: json['address'] == null
            ? null
            : Direccion.deJson(json['address'] as Map<String, dynamic>),
        contacto: json['contact'] == null
            ? null
            : Contacto.deJson(json['contact'] as Map<String, dynamic>),
        version: json['profileVersion'] as int,
        tarjetaFiscalLista: json['fiscalCardReady'] as bool,
      );

  final String empresaId;

  /// El nombre comercial, que **ya existía** y no es parte del expediente: se edita en
  /// otro sitio y aquí sólo se muestra.
  final String nombre;

  final String? razonSocial;
  final String? rfc;
  final String? representanteLegal;
  final String? eslogan;
  final String? regimenFiscal;
  final Direccion? direccion;
  final Contacto? contacto;

  /// El contador del **control optimista**. Se lee al abrir y se devuelve al guardar;
  /// si no coincide, el servidor contesta 409 y nadie pierde su trabajo.
  final int version;

  /// **Lo decide el servidor.** Razón social + RFC + domicilio.
  final bool tarjetaFiscalLista;
}

/// El expediente de una sucursal: domicilio y horario.
class ExpedienteDeSucursal {
  const ExpedienteDeSucursal({
    required this.sucursalId,
    required this.codigo,
    required this.nombre,
    required this.horario,
    required this.version,
    this.direccion,
  });

  factory ExpedienteDeSucursal.deJson(Map<String, dynamic> json) =>
      ExpedienteDeSucursal(
        sucursalId: json['branchId'] as String,
        codigo: json['code'] as String,
        nombre: json['name'] as String,
        direccion: json['address'] == null
            ? null
            : Direccion.deJson(json['address'] as Map<String, dynamic>),
        horario: [
          for (final t in json['schedule'] as List)
            TramoDeHorario.deJson(t as Map<String, dynamic>),
        ],
        version: json['profileVersion'] as int,
      );

  final String sucursalId;
  final String codigo;
  final String nombre;
  final Direccion? direccion;

  /// **Varios tramos por día**, y esto el escritorio no podía expresarlo: allá el
  /// horario es siempre exactamente siete días, uno por cada valor de `diaSemana`, así
  /// que una oficina que abre 9–14 y 16–20 no caía en el modelo.
  ///
  /// **Un día cerrado es la AUSENCIA de tramos**, no un tramo con ceros.
  final List<TramoDeHorario> horario;

  final int version;

  /// Los tramos de un día, en orden. Vacío = cerrado.
  List<TramoDeHorario> tramosDe(int dia) =>
      [for (final t in horario) if (t.dia == dia) t]
        ..sort((a, b) => a.inicio.compareTo(b.inicio));
}
