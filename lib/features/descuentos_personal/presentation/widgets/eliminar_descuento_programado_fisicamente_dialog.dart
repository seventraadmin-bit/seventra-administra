import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';

import '../../descuentos_personal_providers.dart';

/// Eliminación física extraordinaria de un descuento programado (pedido
/// explícito: dar al Maestro una forma de borrar por pruebas un
/// descuento ya cancelado) — facultad exclusiva del Usuario Maestro; el
/// botón que invoca esta función solo debe mostrarse cuando
/// `sesion.esMaestro == true` y el descuento ya está `cancelado`, pero
/// la protección real vive en
/// `eliminarDescuentoProgramadoFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI.
Future<bool> mostrarDialogoEliminarDescuentoProgramadoFisicamente(
  BuildContext context,
  WidgetRef ref,
  String descuentoProgramadoId,
) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: l10n.eliminarDescuentoProgramadoFisicamenteDialogoTitulo,
    advertencia: l10n.eliminarDescuentoProgramadoFisicamenteAdvertencia,
    eliminar: (motivo) async {
      final resultado = await ref.read(
        eliminarDescuentoProgramadoFisicamenteAutorizadoProvider,
      )(descuentoProgramadoId: descuentoProgramadoId, motivo: motivo);
      switch (resultado) {
        case EliminarDescuentoProgramadoFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarDescuentoProgramadoFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarDescuentoProgramadoFisicamenteNoPermitido():
          if (context.mounted) {
            RisegFeedback.showError(
              context,
              l10n.eliminarDescuentoProgramadoFisicamenteAdvertencia,
            );
          }
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarDescuentoProgramadoFisicamenteTieneDependencias(
          :final detalle,
        ):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarDescuentoProgramadoFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
