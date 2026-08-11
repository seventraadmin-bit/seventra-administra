import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../data/tables/linea_telefonica_table.dart';

String operadorTelefonicoLabel(AppLocalizations l10n, String operador) {
  return switch (operador) {
    'telcel' => l10n.operadorTelefonicoTelcel,
    'att' => l10n.operadorTelefonicoAtt,
    'movistar' => l10n.operadorTelefonicoMovistar,
    'otro' => l10n.operadorTelefonicoOtro,
    _ => operador,
  };
}

/// Para `operador == otro`, usa `operadorOtroNombre` — sin eso, "Otro"
/// no distingue una línea de otra en el listado.
String operadorLineaTelefonicaLabel(AppLocalizations l10n, LineaTelefonicaData linea) {
  if (linea.operador == 'otro') return linea.operadorOtroNombre ?? l10n.operadorTelefonicoOtro;
  return operadorTelefonicoLabel(l10n, linea.operador);
}

String modalidadSimLabel(AppLocalizations l10n, String modalidad) {
  return switch (modalidad) {
    'fisica' => l10n.modalidadSimFisica,
    'esim' => l10n.modalidadSimEsim,
    _ => modalidad,
  };
}

String estatusLineaTelefonicaLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'activa' => l10n.estatusLineaTelefonicaActiva,
    'suspendida' => l10n.estatusLineaTelefonicaSuspendida,
    'baja' => l10n.estatusLineaTelefonicaBaja,
    _ => estatus,
  };
}

RisegStatusTone estatusLineaTelefonicaTono(String estatus) {
  return switch (estatus) {
    'activa' => RisegStatusTone.success,
    'suspendida' => RisegStatusTone.warning,
    'baja' => RisegStatusTone.error,
    _ => RisegStatusTone.neutral,
  };
}

String motivoBajaLineaTelefonicaLabel(AppLocalizations l10n, MotivoBajaLineaTelefonica motivo) {
  return switch (motivo) {
    MotivoBajaLineaTelefonica.cancelacion => l10n.motivoBajaLineaTelefonicaCancelacion,
    MotivoBajaLineaTelefonica.cambioOperador => l10n.motivoBajaLineaTelefonicaCambioOperador,
    MotivoBajaLineaTelefonica.perdidaDelNumero => l10n.motivoBajaLineaTelefonicaPerdidaDelNumero,
    MotivoBajaLineaTelefonica.otro => l10n.motivoBajaLineaTelefonicaOtro,
  };
}
