/// Datos generales de la Empresa tal como llegan del formulario — sin
/// validar/normalizar todavía (eso lo hace `GuardarExpedienteEmpresaUseCase`).
class EmpresaDatosGeneralesInput {
  const EmpresaDatosGeneralesInput({
    required this.nombreComercial,
    this.razonSocial,
    this.rfc,
    this.representanteLegal,
    this.eslogan,
  });

  final String nombreComercial;
  final String? razonSocial;
  final String? rfc;
  final String? representanteLegal;
  final String? eslogan;
}

/// Dirección fiscal tal como llega del formulario — todos los campos son
/// cadenas sin validar (posiblemente vacías); `estaCompletamenteVacia`
/// es la única lógica que se le permite tener, para que la regla de
/// "vacía por completo = sin dirección" no se repita en cada llamador.
class DireccionFiscalBorrador {
  const DireccionFiscalBorrador({
    this.calle = '',
    this.numeroExterior = '',
    this.numeroInterior,
    this.colonia = '',
    this.municipioAlcaldia = '',
    this.ciudadLocalidad,
    this.estado = '',
    this.codigoPostal = '',
    this.pais = 'México',
    this.referencias,
  });

  final String calle;
  final String numeroExterior;
  final String? numeroInterior;
  final String colonia;
  final String municipioAlcaldia;
  final String? ciudadLocalidad;
  final String estado;
  final String codigoPostal;
  final String pais;
  final String? referencias;

  bool get estaCompletamenteVacia =>
      calle.trim().isEmpty &&
      numeroExterior.trim().isEmpty &&
      colonia.trim().isEmpty &&
      municipioAlcaldia.trim().isEmpty &&
      estado.trim().isEmpty &&
      codigoPostal.trim().isEmpty;
}

/// Medio de contacto principal tal como llega del formulario. La
/// etiqueta no es un campo de este borrador — el caso de uso siempre la
/// fija internamente en `'principal'`.
class MedioContactoBorrador {
  const MedioContactoBorrador({this.telefono, this.correo, this.sitioWeb});

  final String? telefono;
  final String? correo;
  final String? sitioWeb;

  bool get estaCompletamenteVacio =>
      (telefono == null || telefono!.trim().isEmpty) &&
      (correo == null || correo!.trim().isEmpty) &&
      (sitioWeb == null || sitioWeb!.trim().isEmpty);
}

/// Entrada completa de `GuardarExpedienteEmpresaUseCase` — un solo
/// objeto tipado en vez de una docena de parámetros sueltos.
class EmpresaExpedienteInput {
  const EmpresaExpedienteInput({
    required this.datosGenerales,
    this.direccionFiscal,
    this.medioContacto,
  });

  final EmpresaDatosGeneralesInput datosGenerales;
  final DireccionFiscalBorrador? direccionFiscal;
  final MedioContactoBorrador? medioContacto;
}
