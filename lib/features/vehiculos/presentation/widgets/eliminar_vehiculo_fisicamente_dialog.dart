import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/eliminar_vehiculo_fisicamente_usecase.dart';

import '../../vehiculos_providers.dart';

/// Eliminación física extraordinaria de un Vehículo (Etapa 11D) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true` (ver
/// `vehiculos_list_screen.dart`), pero la protección real vive en
/// `eliminarVehiculoFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI.
Future<bool> mostrarDialogoEliminarVehiculoFisicamente(BuildContext context, WidgetRef ref, String vehiculoId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Vehículo',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarVehiculoFisicamenteAutorizadoProvider)(
        vehiculoId: vehiculoId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarVehiculoFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarVehiculoFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarVehiculoFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarVehiculoFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarVehiculoFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
