import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_puesto_fisicamente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Eliminación física extraordinaria de un Puesto (Etapa 11D) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en `eliminarPuestoFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI.
Future<bool> mostrarDialogoEliminarPuestoFisicamente(BuildContext context, WidgetRef ref, String puestoId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Puesto',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarPuestoFisicamenteAutorizadoProvider)(
        puestoId: puestoId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarPuestoFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarPuestoFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarPuestoFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarPuestoFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.errorInesperado;
        case EliminarPuestoFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
