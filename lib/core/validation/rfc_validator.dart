/// Validación conservadora de RFC mexicano — detecta errores evidentes,
/// no sustituye la validación fiscal del SAT.
///
/// Deliberadamente sin validar fecha interna, homoclave ni dígito
/// verificador: una regex más estricta basada en "3-4 letras + 6 números
/// + 3 alfanuméricos" rechazaría de forma incorrecta casos reales (RFC
/// genéricos como XAXX010101000/XEXX010101000, o letras poco comunes
/// como Ñ/& en la razón social).
abstract final class RfcValidator {
  static final _formato = RegExp(r'^[A-ZÑ&0-9]{12,13}$');

  /// Mayúsculas y sin espacios (internos o externos) — nunca cambia el
  /// contenido más allá de eso.
  static String normalizar(String rfc) {
    return rfc.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// Solo verifica longitud (12 o 13) y el conjunto de caracteres
  /// permitido. Se espera recibir el valor ya normalizado.
  static bool esFormatoValido(String rfcNormalizado) => _formato.hasMatch(rfcNormalizado);
}
