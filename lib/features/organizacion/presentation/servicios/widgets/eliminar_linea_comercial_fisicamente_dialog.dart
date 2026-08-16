import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_linea_comercial_fisicamente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Eliminación física extraordinaria de una línea comercial (Etapa 15)
/// — facultad exclusiva del Usuario Maestro. El ítem de menú que invoca
/// esta función se ofrece a cualquier línea (nunca se oculta según
/// `esCorregible` — Etapa 15, hallazgo real de Marlon: una línea con
/// historia real debe seguir siendo administrable); la elegibilidad
/// real (línea con exactamente 1 vigencia y sin documentos de Agenda
/// generados) la decide `ServicioComercialRepositoryImpl.eliminarFisicamente`,
/// que devuelve `EliminarLineaComercialFisicamenteTieneDependencias`
/// con un mensaje claro cuando no aplica — mostrado abajo como error.
/// La facultad Maestro-only vive en
/// `eliminarLineaComercialFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI.
Future<bool> mostrarDialogoEliminarLineaComercialFisicamente(
  BuildContext context,
  WidgetRef ref,
  String lineaComercialId,
) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.servicioSeccionConfiguracionComercialTitulo}',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarLineaComercialFisicamenteAutorizadoProvider)(
        lineaComercialId: lineaComercialId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarLineaComercialFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarLineaComercialFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarLineaComercialFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarLineaComercialFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarLineaComercialFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
