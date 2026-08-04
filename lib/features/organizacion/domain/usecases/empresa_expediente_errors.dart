/// Campo del expediente de Empresa al que se asocia un error de
/// validación — la pantalla nunca debe inferir esto analizando texto de
/// mensaje, por eso es un valor estructurado.
enum CampoExpediente {
  rfc,
  calle,
  numeroExterior,
  colonia,
  municipioAlcaldia,
  estado,
  codigoPostal,
  correo,
  sitioWeb,
}

/// Tipo de error, independiente del campo — la combinación (campo,
/// código) es lo que la capa de presentación traduce a un mensaje
/// localizado concreto.
enum CodigoErrorCampo { requerido, formatoInvalido }

class ErrorCampoExpediente {
  const ErrorCampoExpediente({required this.campo, required this.codigo});

  final CampoExpediente campo;
  final CodigoErrorCampo codigo;

  @override
  String toString() => 'ErrorCampoExpediente(${campo.name}, ${codigo.name})';
}
