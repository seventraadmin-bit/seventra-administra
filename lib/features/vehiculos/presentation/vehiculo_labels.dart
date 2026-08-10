import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../data/tables/vehiculo_table.dart';

String tipoVehiculoLabel(AppLocalizations l10n, String tipo) {
  return switch (tipo) {
    'sedan' => l10n.tipoVehiculoSedan,
    'pickup' => l10n.tipoVehiculoPickup,
    'van' => l10n.tipoVehiculoVan,
    'suv' => l10n.tipoVehiculoSuv,
    'motocicleta' => l10n.tipoVehiculoMotocicleta,
    'otro' => l10n.tipoVehiculoOtro,
    _ => tipo,
  };
}

String estatusVehiculoLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'disponible' => l10n.estatusVehiculoDisponible,
    'asignado' => l10n.estatusVehiculoAsignado,
    'enMantenimiento' => l10n.estatusVehiculoEnMantenimiento,
    'fueraDeServicio' => l10n.estatusVehiculoFueraDeServicio,
    'baja' => l10n.estatusVehiculoBaja,
    _ => estatus,
  };
}

RisegStatusTone estatusVehiculoTono(String estatus) {
  return switch (estatus) {
    'disponible' => RisegStatusTone.success,
    'asignado' => RisegStatusTone.info,
    'enMantenimiento' => RisegStatusTone.warning,
    'fueraDeServicio' => RisegStatusTone.warning,
    'baja' => RisegStatusTone.error,
    _ => RisegStatusTone.neutral,
  };
}

String motivoBajaVehiculoLabel(AppLocalizations l10n, MotivoBajaVehiculo motivo) {
  return switch (motivo) {
    MotivoBajaVehiculo.venta => l10n.motivoBajaVehiculoVenta,
    MotivoBajaVehiculo.perdidaTotal => l10n.motivoBajaVehiculoPerdidaTotal,
    MotivoBajaVehiculo.robo => l10n.motivoBajaVehiculoRobo,
    MotivoBajaVehiculo.finVidaUtil => l10n.motivoBajaVehiculoFinVidaUtil,
    MotivoBajaVehiculo.otro => l10n.motivoBajaVehiculoOtro,
  };
}
