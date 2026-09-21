import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../data/tables/tiempo_extra_table.dart';

String motivoAusenciaTiempoExtraLabel(AppLocalizations l10n, MotivoAusenciaTiempoExtra motivo) {
  return switch (motivo) {
    MotivoAusenciaTiempoExtra.problemasMedicos => l10n.motivoAusenciaProblemasMedicos,
    MotivoAusenciaTiempoExtra.faltaInjustificada => l10n.motivoAusenciaFaltaInjustificada,
    MotivoAusenciaTiempoExtra.faltaJustificada => l10n.motivoAusenciaFaltaJustificada,
    MotivoAusenciaTiempoExtra.permisoOtorgado => l10n.motivoAusenciaPermisoOtorgado,
  };
}

String tiempoExtraEstatusLabel(AppLocalizations l10n, String estatus) {
  return switch (EstatusTiempoExtra.values.byName(estatus)) {
    EstatusTiempoExtra.registrado => l10n.tiemposExtraEstatusRegistrado,
    EstatusTiempoExtra.cancelado => l10n.tiemposExtraEstatusCancelado,
  };
}

RisegStatusTone tiempoExtraEstatusTono(String estatus) {
  return switch (EstatusTiempoExtra.values.byName(estatus)) {
    EstatusTiempoExtra.registrado => RisegStatusTone.success,
    EstatusTiempoExtra.cancelado => RisegStatusTone.neutral,
  };
}

/// Nombre UX del origen de la cobertura (Etapa "origen de cobertura").
String origenCoberturaTiempoExtraLabel(AppLocalizations l10n, OrigenCoberturaTiempoExtra origen) {
  return switch (origen) {
    OrigenCoberturaTiempoExtra.ausenciaEmpleado => l10n.origenCoberturaAusenciaEmpleado,
    OrigenCoberturaTiempoExtra.vacante => l10n.origenCoberturaVacante,
    OrigenCoberturaTiempoExtra.otro => l10n.origenCoberturaOtro,
  };
}

/// Versión compacta para la tabla — "Ausencia" en vez de "Ausencia de
/// empleado", que no cabe sin saturar la columna.
String origenCoberturaTiempoExtraLabelCorto(AppLocalizations l10n, String origen) {
  return switch (OrigenCoberturaTiempoExtra.values.asNameMap()[origen]) {
    OrigenCoberturaTiempoExtra.ausenciaEmpleado => l10n.origenCoberturaAusenciaCorto,
    OrigenCoberturaTiempoExtra.vacante => l10n.origenCoberturaVacante,
    OrigenCoberturaTiempoExtra.otro => l10n.origenCoberturaOtro,
    // Un origen desconocido nunca se inventa como "Ausencia": se ve tal
    // cual, que es señal de que algo lo escribió fuera del dominio.
    null => origen,
  };
}
