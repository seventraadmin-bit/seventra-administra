import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/puesto_errors.dart';

/// Traduce un [ErrorCampoPuesto] estructurado a un mensaje localizado —
/// la única capa que conoce la relación (campo, código) → texto, mismo
/// patrón que `campo_error_l10n.dart` de Empresa.
String mensajeErrorCampoPuesto(AppLocalizations l10n, ErrorCampoPuesto error) {
  switch (error.campo) {
    case CampoPuesto.nombre:
      return l10n.puestoErrorNombreRequerido;
    case CampoPuesto.area:
      switch (error.codigo) {
        case CodigoErrorPuesto.noExiste:
          return l10n.puestoErrorAreaNoExiste;
        case CodigoErrorPuesto.inactiva:
          return l10n.puestoErrorAreaInactiva;
        case CodigoErrorPuesto.requerido:
        case CodigoErrorPuesto.fueraDeRango:
          return l10n.puestoErrorAreaRequerida;
      }
    case CampoPuesto.tipo:
      return l10n.puestoErrorTipoRequerido;
    case CampoPuesto.nivelJerarquico:
      return error.codigo == CodigoErrorPuesto.fueraDeRango
          ? l10n.puestoErrorNivelJerarquicoFueraDeRango
          : l10n.puestoErrorNivelJerarquicoRequerido;
  }
}

/// Busca el error (si existe) asociado a un campo específico.
ErrorCampoPuesto? errorParaCampoPuesto(List<ErrorCampoPuesto> errores, CampoPuesto campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
