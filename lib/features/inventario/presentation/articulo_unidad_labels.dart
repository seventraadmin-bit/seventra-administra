import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../data/tables/articulo_unidad_table.dart';

/// Etiqueta y tono de un `EstatusArticuloUnidad`.
///
/// Única conversión código→texto de los estados de una unidad, para que
/// "En lavandería" se escriba igual en Inventario y en Reportes. Existe
/// desde que recuperar un bien dejó de significar automáticamente que
/// está disponible: los estados intermedios son parte de la lectura
/// operativa, no un detalle interno.
String estatusArticuloUnidadLabel(AppLocalizations l10n, String estatus) {
  final valor = EstatusArticuloUnidad.values.where((e) => e.name == estatus).firstOrNull;
  return switch (valor) {
    EstatusArticuloUnidad.disponible => l10n.unidadEstatusDisponible,
    EstatusArticuloUnidad.asignado => l10n.unidadEstatusAsignado,
    EstatusArticuloUnidad.enLavanderia => l10n.unidadEstatusEnLavanderia,
    EstatusArticuloUnidad.enReparacion => l10n.unidadEstatusEnReparacion,
    EstatusArticuloUnidad.pendienteDesecho => l10n.unidadEstatusPendienteDesecho,
    EstatusArticuloUnidad.danado => l10n.unidadEstatusDanado,
    EstatusArticuloUnidad.perdido => l10n.unidadEstatusPerdido,
    EstatusArticuloUnidad.baja => l10n.unidadEstatusBaja,
    // Un estatus desconocido se muestra crudo en vez de romper: es dato
    // real que alguien tiene que poder ver para corregirlo.
    null => estatus,
  };
}

/// Qué tan disponible está la unidad, en el vocabulario de tono del
/// Design System. No es decorativo: separa visualmente lo que se puede
/// asignar de lo que está fuera de circulación.
RisegStatusTone tonoArticuloUnidad(String estatus) {
  final valor = EstatusArticuloUnidad.values.where((e) => e.name == estatus).firstOrNull;
  return switch (valor) {
    EstatusArticuloUnidad.disponible => RisegStatusTone.success,
    EstatusArticuloUnidad.asignado => RisegStatusTone.info,
    EstatusArticuloUnidad.enLavanderia || EstatusArticuloUnidad.enReparacion => RisegStatusTone.warning,
    EstatusArticuloUnidad.pendienteDesecho ||
    EstatusArticuloUnidad.danado ||
    EstatusArticuloUnidad.perdido =>
      RisegStatusTone.error,
    EstatusArticuloUnidad.baja => RisegStatusTone.neutral,
    null => RisegStatusTone.neutral,
  };
}
