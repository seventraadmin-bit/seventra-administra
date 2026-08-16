import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';

/// Traduce un [ErrorConfiguracionCobro] estructurado a un mensaje
/// localizado y específico — la única capa que conoce la relación
/// (campo, código) → texto (Etapa 15: antes de esto, cualquier error
/// de validación se mostraba como el mismo mensaje genérico, sin
/// importar cuál regla realmente fallaba).
String mensajeErrorConfiguracionCobro(AppLocalizations l10n, ErrorConfiguracionCobro error) {
  switch (error.codigo) {
    case CodigoErrorConfiguracionCobro.requerido:
      return l10n.servicioCobroErrorCampoRequerido;
    case CodigoErrorConfiguracionCobro.noExiste:
      return error.campo == CampoConfiguracionCobro.clientePortal
          ? l10n.servicioCobroErrorPortalNoExiste
          : l10n.servicioCobroErrorEntidadFiscalNoExiste;
    case CodigoErrorConfiguracionCobro.inactivo:
      return error.campo == CampoConfiguracionCobro.clientePortal
          ? l10n.servicioCobroErrorPortalInactivo
          : l10n.servicioCobroErrorEntidadFiscalInactiva;
    case CodigoErrorConfiguracionCobro.entidadFiscalRequeridaParaCfdi:
      return l10n.servicioCobroErrorEntidadFiscalRequeridaParaCfdi;
    case CodigoErrorConfiguracionCobro.metodoInvalidoParaRecibo:
      return l10n.servicioCobroErrorMetodoInvalidoParaRecibo;
    case CodigoErrorConfiguracionCobro.complementoRequeridoParaPpd:
      return l10n.servicioCobroErrorComplementoRequeridoParaPpd;
    case CodigoErrorConfiguracionCobro.cfdiIncompatibleConIvaNoAplica:
      return l10n.servicioCobroErrorCfdiIncompatibleConIvaNoAplica;
    case CodigoErrorConfiguracionCobro.reciboRequiereIvaNoAplica:
      return l10n.servicioCobroErrorReciboRequiereIvaNoAplica;
    case CodigoErrorConfiguracionCobro.fechaAnteriorInicioServicio:
      return l10n.servicioCobroErrorFechaAnteriorInicioServicio;
    case CodigoErrorConfiguracionCobro.fechaDuplicada:
      return l10n.servicioCobroErrorFechaDuplicada;
    case CodigoErrorConfiguracionCobro.correoInvalido:
      return l10n.servicioCobroErrorCorreoInvalido;
  }
}

/// Busca el error (si existe) asociado a un campo específico — para que
/// cada control del formulario muestre solo el suyo.
ErrorConfiguracionCobro? errorParaCampoConfiguracionCobroForm(
  List<ErrorConfiguracionCobro> errores,
  CampoConfiguracionCobro campo,
) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
