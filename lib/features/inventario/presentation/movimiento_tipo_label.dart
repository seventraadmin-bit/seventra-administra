import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Etiqueta legible de `TipoMovimientoInventario` — compartida entre
/// `ArticuloExpedienteScreen` (7A) y `ReportesScreen` (7D). Cubre los 8
/// valores del enum (4 de 7A + 4 de 7B, ver el doc comment de
/// `MovimientoInventario`) — antes de este archivo, el helper
/// equivalente vivía privado en `articulo_expediente_screen.dart` y
/// solo cubría los 4 originales, mostrando el nombre crudo del enum
/// para cualquier movimiento generado por una Asignación.
String movimientoTipoLabel(AppLocalizations l10n, String tipo) {
  return switch (tipo) {
    'entrada' => l10n.movimientoTipoEntrada,
    'baja' => l10n.movimientoTipoBaja,
    'ajusteEntrada' => l10n.movimientoTipoAjusteEntrada,
    'ajusteSalida' => l10n.movimientoTipoAjusteSalida,
    'salidaAsignacion' => l10n.movimientoTipoSalidaAsignacion,
    'entradaDevolucion' => l10n.movimientoTipoEntradaDevolucion,
    'salidaDano' => l10n.movimientoTipoSalidaDano,
    'salidaPerdida' => l10n.movimientoTipoSalidaPerdida,
    _ => tipo,
  };
}
