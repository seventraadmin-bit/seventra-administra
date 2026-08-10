import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
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

String origenKilometrajeLabel(AppLocalizations l10n, String origen) {
  return switch (origen) {
    'lecturaManual' => l10n.origenKilometrajeLecturaManual,
    'entrega' => l10n.origenKilometrajeEntrega,
    'devolucion' => l10n.origenKilometrajeDevolucion,
    'mantenimiento' => l10n.origenKilometrajeMantenimiento,
    'correccion' => l10n.origenKilometrajeCorreccion,
    _ => origen,
  };
}

/// El "destino" de una `AsignacionVehiculo` ya resuelto para mostrar —
/// el llamador es responsable de pasar el nombre ya buscado
/// (`empleadosPorId`/`serviciosPorId`), esta función solo decide cuál
/// de los dos aplica. Mismo criterio que `ReportesController` en
/// Inventario (7D): mapas de resolución cargados una sola vez, nunca
/// N+1 por fila.
String destinoAsignacionVehiculoLabel(
  AsignacionVehiculoData asignacion, {
  required Map<String, String> empleadosPorId,
  required Map<String, String> serviciosPorId,
}) {
  if (asignacion.empleadoId != null) return empleadosPorId[asignacion.empleadoId] ?? asignacion.empleadoId!;
  if (asignacion.servicioId != null) return serviciosPorId[asignacion.servicioId] ?? asignacion.servicioId!;
  return '—';
}
