/// Dirección tal como llega de un formulario — todos los campos son
/// cadenas sin validar (posiblemente vacías). `estaCompletamenteVacia` es
/// la única lógica que se le permite tener, para que la regla de "vacía
/// por completo = sin dirección" no se repita en cada llamador.
class DireccionBorrador {
  const DireccionBorrador({
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

/// Dirección ya validada y normalizada (recortada, país resuelto) — lista
/// para que el llamador la convierta a su propio tipo de persistencia
/// (ej. `DireccionInput` de Organización).
class DireccionValidada {
  const DireccionValidada({
    required this.calle,
    required this.numeroExterior,
    required this.numeroInterior,
    required this.colonia,
    required this.municipioAlcaldia,
    required this.ciudadLocalidad,
    required this.estado,
    required this.codigoPostal,
    required this.pais,
    required this.referencias,
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

/// Campo de [DireccionBorrador] que puede fallar la validación.
enum CampoDireccion { calle, numeroExterior, colonia, municipioAlcaldia, estado, codigoPostal }

enum CodigoErrorCampoDireccion { requerido, formatoInvalido }

class ErrorCampoDireccion {
  const ErrorCampoDireccion({required this.campo, required this.codigo});

  final CampoDireccion campo;
  final CodigoErrorCampoDireccion codigo;
}

/// Busca el error (si existe) asociado a un campo específico de dirección
/// — para que cada `RisegTextField` muestre solo el suyo.
ErrorCampoDireccion? errorParaCampoDireccion(List<ErrorCampoDireccion> errores, CampoDireccion campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}

/// Valida y normaliza una [DireccionBorrador] — completamente
/// independiente de cualquier dominio de negocio (Empresa, Sucursal,
/// Servicio, ...). Cada módulo que la use mapea `CampoDireccion` a su
/// propio enum de campos de pantalla (ver `GuardarExpedienteEmpresaUseCase`
/// para el patrón de mapeo).
abstract final class DireccionValidator {
  static final _codigoPostalMexicoRegex = RegExp(r'^\d{5}$');

  /// `resultado` es no nulo únicamente cuando no hay errores. Una
  /// dirección completamente vacía es válida (significa "sin dirección")
  /// y devuelve `resultado: null` sin ningún error.
  static ({DireccionValidada? resultado, List<ErrorCampoDireccion> errores}) validar(
    DireccionBorrador borrador,
  ) {
    if (borrador.estaCompletamenteVacia) {
      return (resultado: null, errores: const []);
    }

    final errores = <ErrorCampoDireccion>[];

    void requerido(String valor, CampoDireccion campo) {
      if (valor.trim().isEmpty) {
        errores.add(ErrorCampoDireccion(campo: campo, codigo: CodigoErrorCampoDireccion.requerido));
      }
    }

    requerido(borrador.calle, CampoDireccion.calle);
    requerido(borrador.numeroExterior, CampoDireccion.numeroExterior);
    requerido(borrador.colonia, CampoDireccion.colonia);
    requerido(borrador.municipioAlcaldia, CampoDireccion.municipioAlcaldia);
    requerido(borrador.estado, CampoDireccion.estado);

    final cp = borrador.codigoPostal.trim();
    final paisNormalizado = borrador.pais.trim().isEmpty ? 'México' : borrador.pais.trim();
    final esMexico = paisNormalizado.toLowerCase() == 'méxico' || paisNormalizado.toLowerCase() == 'mexico';

    if (cp.isEmpty) {
      errores.add(
        const ErrorCampoDireccion(campo: CampoDireccion.codigoPostal, codigo: CodigoErrorCampoDireccion.requerido),
      );
    } else if (esMexico && !_codigoPostalMexicoRegex.hasMatch(cp)) {
      // La regla de 5 dígitos depende de `país` — si se selecciona otro
      // país, esta validación de formato no aplica.
      errores.add(
        const ErrorCampoDireccion(
          campo: CampoDireccion.codigoPostal,
          codigo: CodigoErrorCampoDireccion.formatoInvalido,
        ),
      );
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    return (
      resultado: DireccionValidada(
        calle: borrador.calle.trim(),
        numeroExterior: borrador.numeroExterior.trim(),
        numeroInterior: _vacioANull(borrador.numeroInterior),
        colonia: borrador.colonia.trim(),
        municipioAlcaldia: borrador.municipioAlcaldia.trim(),
        ciudadLocalidad: _vacioANull(borrador.ciudadLocalidad),
        estado: borrador.estado.trim(),
        codigoPostal: cp,
        pais: paisNormalizado,
        referencias: _vacioANull(borrador.referencias),
      ),
      errores: const [],
    );
  }

  static String? _vacioANull(String? valor) {
    if (valor == null) return null;
    final recortado = valor.trim();
    return recortado.isEmpty ? null : recortado;
  }
}
