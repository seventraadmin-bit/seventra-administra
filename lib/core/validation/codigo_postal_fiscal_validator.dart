/// Código postal mexicano — cinco dígitos, nada más.
///
/// Existe porque el mismo concepto ya vivía escrito dos veces: dentro
/// de `DireccionValidator` (como parte de un domicilio completo) y
/// dentro de `EmpleadoValidator` (como el CP suelto de la Constancia de
/// Situación Fiscal). Ambos comprobaban exactamente `^[0-9]{5}$`. Al
/// necesitarlo un tercer dominio —el receptor fiscal de un Servicio
/// Eventual— la alternativa era escribirlo una tercera vez; se extrajo
/// aquí en su lugar, y los dos originales delegan.
///
/// **Sólo formato.** No verifica que el CP exista en el catálogo del
/// SAT ni que corresponda al domicilio: mismo criterio que
/// [RfcValidator], que tampoco valida homoclave ni dígito verificador.
abstract final class CodigoPostalFiscalValidator {
  static final _formato = RegExp(r'^[0-9]{5}$');

  /// Tolera espacios alrededor; nunca los de en medio.
  static bool esFormatoValido(String codigoPostal) => _formato.hasMatch(codigoPostal.trim());
}
