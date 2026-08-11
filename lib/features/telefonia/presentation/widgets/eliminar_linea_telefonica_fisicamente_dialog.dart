import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/eliminar_linea_telefonica_fisicamente_usecase.dart';

import '../../telefonia_providers.dart';

/// Eliminación física extraordinaria de una LineaTelefonica (Etapa
/// 11D) — facultad exclusiva del Usuario Maestro; el botón que invoca
/// esta función solo debe mostrarse cuando `sesion.esMaestro == true`,
/// pero la protección real vive en
/// `eliminarLineaTelefonicaFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI.
Future<bool> mostrarDialogoEliminarLineaTelefonicaFisicamente(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Línea telefónica',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarLineaTelefonicaFisicamenteAutorizadoProvider)(
        lineaTelefonicaId: lineaTelefonicaId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarLineaTelefonicaFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarLineaTelefonicaFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarLineaTelefonicaFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarLineaTelefonicaFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.errorInesperado;
        case EliminarLineaTelefonicaFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
