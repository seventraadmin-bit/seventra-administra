/// Un domicilio. **La misma forma en los seis sitios** que la usan, a propósito.
///
/// Siete campos obligatorios y cuatro opcionales, y la frontera la impone el motor:
/// «cuatro direcciones del mismo sistema que validaran distinto serían un defecto, no
/// una flexibilidad».
///
/// ## Por qué vive en `core/direcciones/` y no en el modelo del expediente
///
/// Porque **no es del expediente de nadie**: es la forma que comparten el domicilio de
/// una empresa, el de una sucursal, el de referencia de un cliente, el fiscal de una
/// entidad y el operativo de un servicio. Nació dentro de
/// `features/organizacion/web/modelos/expediente.dart` porque los dos primeros fueron
/// los primeros en mudarse, y en C1 el expediente de un cliente necesitó la misma
/// forma **y el mismo formulario**. Con el tipo dentro de Organización, Comercial sólo
/// tenía dos salidas: importar de otra feature, o escribir su propia `Direccion` — y la
/// segunda es la que el motor prohíbe.
library;

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
