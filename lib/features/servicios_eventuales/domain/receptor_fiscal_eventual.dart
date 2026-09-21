import 'package:riseg_one/core/validation/codigo_postal_fiscal_validator.dart';
import 'package:riseg_one/core/validation/rfc_validator.dart';

/// A nombre de quién se emite el CFDI de un Servicio Eventual.
///
/// **No es el solicitante.** Quien pide el servicio ("Juan del comité")
/// y quien aparece en la factura ("Administradora Bosques S.A. de
/// C.V.") son dos datos distintos, y tratarlos como uno era el hueco
/// real que encontró la prueba manual: el alta pedía nombre, contacto,
/// teléfono y correo, ninguno de los cuales identifica a un receptor
/// fiscal.
///
/// Hay exactamente dos caminos, y ninguno inventa un tercero:
///
///  * **Cliente** → se apunta a una `EntidadFiscal` suya, que ya tiene
///    razón social, RFC y domicilio fiscal registrados. No se
///    recaptura nada (§1: "no duplicar captura").
///  * **Solicitante ocasional** → se captura este mínimo a mano y se
///    guarda como snapshot en el propio eventual. **Nunca** se crea un
///    `Cliente` ni una `EntidadFiscal` permanente: facturarle una vez a
///    alguien no lo convierte en cartera.
class DatosFiscalesEventual {
  const DatosFiscalesEventual({
    required this.razonSocial,
    required this.rfc,
    required this.codigoPostalFiscal,
  });

  final String razonSocial;

  /// Ya normalizado por [RfcValidator] — mayúsculas y sin espacios.
  final String rfc;

  /// Cinco dígitos. Obligatorio en un CFDI 4.0, no un extra.
  final String codigoPostalFiscal;
}

/// Qué le falta o qué está mal en la captura manual. Un enum y no un
/// texto: la pantalla decide cómo decirlo, el dominio sólo dice qué es.
enum ErrorReceptorFiscalEventual {
  razonSocialRequerida,
  rfcRequerido,
  rfcInvalido,
  codigoPostalRequerido,
  codigoPostalInvalido,
}

/// Valida y normaliza el receptor fiscal capturado a mano.
///
/// Reutiliza los validadores que ya existen —[RfcValidator] y
/// [CodigoPostalFiscalValidator]— en vez de escribir un tercer criterio
/// de "RFC válido" o de "CP válido" dentro de este módulo.
({DatosFiscalesEventual? datos, ErrorReceptorFiscalEventual? error}) validarReceptorFiscalEventual({
  String? razonSocial,
  String? rfc,
  String? codigoPostalFiscal,
}) {
  final razon = (razonSocial ?? '').trim();
  if (razon.isEmpty) return (datos: null, error: ErrorReceptorFiscalEventual.razonSocialRequerida);

  final rfcNormalizado = RfcValidator.normalizar((rfc ?? '').trim());
  if (rfcNormalizado.isEmpty) return (datos: null, error: ErrorReceptorFiscalEventual.rfcRequerido);
  if (!RfcValidator.esFormatoValido(rfcNormalizado)) {
    return (datos: null, error: ErrorReceptorFiscalEventual.rfcInvalido);
  }

  final cp = (codigoPostalFiscal ?? '').trim();
  if (cp.isEmpty) return (datos: null, error: ErrorReceptorFiscalEventual.codigoPostalRequerido);
  if (!CodigoPostalFiscalValidator.esFormatoValido(cp)) {
    return (datos: null, error: ErrorReceptorFiscalEventual.codigoPostalInvalido);
  }

  return (
    datos: DatosFiscalesEventual(razonSocial: razon, rfc: rfcNormalizado, codigoPostalFiscal: cp),
    error: null,
  );
}
