import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_errors.dart';

/// Traduce un [ErrorCampoExpediente] estructurado a un mensaje
/// localizado — la única capa que conoce la relación (campo, código) →
/// texto. La pantalla nunca infiere esto de un mensaje de texto plano.
String mensajeErrorCampoExpediente(AppLocalizations l10n, ErrorCampoExpediente error) {
  switch (error.campo) {
    case CampoExpediente.rfc:
      return l10n.empresaErrorRfcFormato;
    case CampoExpediente.correo:
      return l10n.empresaErrorCorreoFormato;
    case CampoExpediente.sitioWeb:
      return l10n.empresaErrorSitioWebFormato;
    case CampoExpediente.codigoPostal:
      return error.codigo == CodigoErrorCampo.formatoInvalido
          ? l10n.empresaErrorCodigoPostalFormato
          : l10n.empresaErrorCampoRequerido;
    case CampoExpediente.calle:
    case CampoExpediente.numeroExterior:
    case CampoExpediente.colonia:
    case CampoExpediente.municipioAlcaldia:
    case CampoExpediente.estado:
      return l10n.empresaErrorCampoRequerido;
  }
}

/// Busca el error (si existe) asociado a un campo específico — para que
/// cada `RisegTextField` muestre solo el suyo.
ErrorCampoExpediente? errorParaCampo(List<ErrorCampoExpediente> errores, CampoExpediente campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
