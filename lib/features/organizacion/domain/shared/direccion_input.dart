/// Campos de una dirección física ya validada y lista para persistir —
/// compartida entre Servicio (dirección operativa) y Empresa (dirección
/// fiscal) porque es exactamente el mismo objeto de valor en ambos
/// casos; duplicarla en dos clases casi idénticas no aportaría nada.
class DireccionInput {
  const DireccionInput({
    required this.calle,
    required this.numeroExterior,
    required this.colonia,
    required this.municipioAlcaldia,
    required this.estado,
    required this.codigoPostal,
    this.numeroInterior,
    this.ciudadLocalidad,
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
}
