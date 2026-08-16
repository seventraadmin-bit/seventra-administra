import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_cliente_fisicamente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Eliminación física extraordinaria de un Cliente (Etapa 15) —
/// facultad exclusiva del Usuario Maestro; el ítem de menú que invoca
/// esta función solo debe mostrarse cuando `sesion.esMaestro == true`,
/// pero la protección real vive en
/// `eliminarClienteFisicamenteAutorizadoProvider` (`exigirMaestro`) —
/// nunca en la UI.
Future<bool> mostrarDialogoEliminarClienteFisicamente(BuildContext context, WidgetRef ref, String clienteId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Cliente',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarClienteFisicamenteAutorizadoProvider)(clienteId: clienteId, motivo: motivo);
      switch (resultado) {
        case EliminarClienteFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarClienteFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarClienteFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarClienteFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarClienteFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
