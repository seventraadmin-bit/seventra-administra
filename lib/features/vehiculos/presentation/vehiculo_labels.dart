import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../data/tables/vehiculo_table.dart';
import '../domain/usecases/calcular_estado_vigencia_documento.dart';

final _formatoFechaDocumento = DateFormat('dd/MM/yyyy');

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

/// Etiqueta fija del catálogo — para `otro`, el nombre genérico
/// ("Otro"), sin una descripción concreta todavía (útil para el
/// selector de un diálogo, donde `otro` es apenas una opción, no un
/// documento real ya descrito). Ver `tipoDocumentoVehiculoLabel` para
/// la etiqueta de una fila real, que sí resuelve la descripción.
String tipoDocumentoVehiculoCatalogoLabel(AppLocalizations l10n, String tipo) {
  return switch (tipo) {
    'tarjetaCirculacion' => l10n.tipoDocumentoVehiculoTarjetaCirculacion,
    'seguro' => l10n.tipoDocumentoVehiculoSeguro,
    'verificacion' => l10n.tipoDocumentoVehiculoVerificacion,
    'tenenciaRefrendo' => l10n.tipoDocumentoVehiculoTenenciaRefrendo,
    'facturaCartaFactura' => l10n.tipoDocumentoVehiculoFacturaCartaFactura,
    'poliza' => l10n.tipoDocumentoVehiculoPoliza,
    'otro' => l10n.tipoDocumentoVehiculoOtro,
    _ => tipo,
  };
}

/// Para `tipo == otro`, usa `tipoOtroDescripcion` (sin eso el
/// documento sería indistinguible de cualquier otro "Otro" en la
/// lista) — para el resto, la etiqueta fija del catálogo.
String tipoDocumentoVehiculoLabel(AppLocalizations l10n, VehiculoDocumentoData documento) {
  if (documento.tipo == 'otro') return documento.tipoOtroDescripcion ?? l10n.tipoDocumentoVehiculoOtro;
  return tipoDocumentoVehiculoCatalogoLabel(l10n, documento.tipo);
}

String estadoVigenciaDocumentoLabel(AppLocalizations l10n, EstadoVigenciaDocumento estado) {
  return switch (estado) {
    EstadoVigenciaDocumento.sinVencimiento => l10n.estadoVigenciaDocumentoSinVencimiento,
    EstadoVigenciaDocumento.vigente => l10n.estadoVigenciaDocumentoVigente,
    EstadoVigenciaDocumento.proximoAVencer => l10n.estadoVigenciaDocumentoProximoAVencer,
    EstadoVigenciaDocumento.vencido => l10n.estadoVigenciaDocumentoVencido,
  };
}

RisegStatusTone estadoVigenciaDocumentoTono(EstadoVigenciaDocumento estado) {
  return switch (estado) {
    EstadoVigenciaDocumento.sinVencimiento => RisegStatusTone.neutral,
    EstadoVigenciaDocumento.vigente => RisegStatusTone.success,
    EstadoVigenciaDocumento.proximoAVencer => RisegStatusTone.warning,
    EstadoVigenciaDocumento.vencido => RisegStatusTone.error,
  };
}

/// El detalle junto al estado — "Vigente hasta 31/12/2026"/"Vence en
/// 12 días"/"Venció el 15/03/2026" — exactamente el formato que Marlon
/// pidió ver en el expediente (punto 7).
String detalleVigenciaDocumentoLabel(
  AppLocalizations l10n,
  EstadoVigenciaDocumento estado,
  DateTime? fechaVencimiento, {
  DateTime? hoy,
}) {
  if (fechaVencimiento == null) return '';
  return switch (estado) {
    EstadoVigenciaDocumento.sinVencimiento => '',
    EstadoVigenciaDocumento.vigente => l10n.vehiculoDocumentoDetalleVigenteHasta(_formatoFechaDocumento.format(fechaVencimiento)),
    EstadoVigenciaDocumento.proximoAVencer => l10n.vehiculoDocumentoDetalleVenceEnDias(_diasRestantes(fechaVencimiento, hoy)),
    EstadoVigenciaDocumento.vencido => l10n.vehiculoDocumentoDetalleVencidoDesde(_formatoFechaDocumento.format(fechaVencimiento)),
  };
}

int _diasRestantes(DateTime fechaVencimiento, DateTime? hoy) {
  final referencia = hoy ?? DateTime.now();
  final hoySoloFecha = DateTime(referencia.year, referencia.month, referencia.day);
  final vencimientoSoloFecha = DateTime(fechaVencimiento.year, fechaVencimiento.month, fechaVencimiento.day);
  return vencimientoSoloFecha.difference(hoySoloFecha).inDays;
}
