import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../domain/tipo_evento_equipo_telefonico.dart';

/// Estatus de la `ArticuloUnidad` subyacente — reutiliza las mismas
/// claves l10n que `ArticuloExpedienteScreen` (`estatusArticuloUnidad*`,
/// Etapa 7A), nunca duplica el texto en un namespace propio de
/// Telefonía: es literalmente el mismo dato de Inventario, solo
/// mostrado en un expediente distinto.
String estatusEquipoTelefonicoLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'disponible' => l10n.estatusArticuloUnidadDisponible,
    'asignado' => l10n.estatusArticuloUnidadAsignado,
    'danado' => l10n.estatusArticuloUnidadDanado,
    'perdido' => l10n.estatusArticuloUnidadPerdido,
    'baja' => l10n.estatusArticuloUnidadBaja,
    _ => estatus,
  };
}

RisegStatusTone estatusEquipoTelefonicoTono(String estatus) {
  return switch (estatus) {
    'disponible' => RisegStatusTone.success,
    'asignado' => RisegStatusTone.info,
    'danado' => RisegStatusTone.warning,
    'perdido' => RisegStatusTone.error,
    'baja' => RisegStatusTone.neutral,
    _ => RisegStatusTone.neutral,
  };
}

String tipoEventoEquipoTelefonicoLabel(AppLocalizations l10n, String tipoEvento) {
  final tipo = TipoEventoEquipoTelefonico.values.where((t) => t.name == tipoEvento).firstOrNull;
  return switch (tipo) {
    TipoEventoEquipoTelefonico.equipoConfigurado => l10n.equipoTelefonicoEventoEquipoConfigurado,
    TipoEventoEquipoTelefonico.correoActualizado => l10n.equipoTelefonicoEventoCorreoActualizado,
    TipoEventoEquipoTelefonico.contrasenaActualizada => l10n.equipoTelefonicoEventoContrasenaActualizada,
    TipoEventoEquipoTelefonico.contrasenaRevelada => l10n.equipoTelefonicoEventoContrasenaRevelada,
    TipoEventoEquipoTelefonico.contrasenaCopiada => l10n.equipoTelefonicoEventoContrasenaCopiada,
    null => tipoEvento,
  };
}

String estatusDescuentoEquipoTelefonicoLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'pendiente' => l10n.equipoTelefonicoDescuentoEstatusPendiente,
    'aplicado' => l10n.equipoTelefonicoDescuentoEstatusAplicado,
    'cancelado' => l10n.equipoTelefonicoDescuentoEstatusCancelado,
    _ => estatus,
  };
}

/// El "destino" de una `Asignacion` de Inventario ya resuelto para
/// mostrar — mismo criterio que `destinoAsignacionVehiculoLabel`/
/// `destinoAsignacionLineaTelefonicaLabel`: el llamador ya buscó los
/// nombres, esta función solo decide cuál de los dos aplica.
String destinoAsignacionEquipoTelefonicoLabel(
  AsignacionData asignacion, {
  required Map<String, String> empleadosPorId,
  required Map<String, String> serviciosPorId,
}) {
  if (asignacion.empleadoId != null) return empleadosPorId[asignacion.empleadoId] ?? asignacion.empleadoId!;
  if (asignacion.servicioId != null) return serviciosPorId[asignacion.servicioId] ?? asignacion.servicioId!;
  return '—';
}
