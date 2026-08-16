import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_servicio_fisicamente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Eliminación física extraordinaria de un Servicio (Etapa 15) —
/// facultad exclusiva del Usuario Maestro; el ítem de menú que invoca
/// esta función solo debe mostrarse cuando `sesion.esMaestro == true`,
/// pero la protección real vive en
/// `eliminarServicioFisicamenteAutorizadoProvider` (`exigirMaestro`) —
/// nunca en la UI.
Future<bool> mostrarDialogoEliminarServicioFisicamente(BuildContext context, WidgetRef ref, String servicioId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Servicio',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado =
          await ref.read(eliminarServicioFisicamenteAutorizadoProvider)(servicioId: servicioId, motivo: motivo);
      switch (resultado) {
        case EliminarServicioFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarServicioFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarServicioFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarServicioFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarServicioFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
