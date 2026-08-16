import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_pago_fisicamente_usecase.dart';

import '../../../finanzas_providers.dart';

/// Eliminación física extraordinaria de un Pago (Etapa 15) — facultad
/// exclusiva del Usuario Maestro; el ítem de menú que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en `eliminarPagoFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. Un Pago activo, o con un
/// Complemento de pago real registrado, siempre se rechaza con el
/// motivo exacto — nunca un mensaje genérico.
Future<bool> mostrarDialogoEliminarPagoFisicamente(BuildContext context, WidgetRef ref, String pagoId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.pagoDetalleDialogoTitulo}',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarPagoFisicamenteAutorizadoProvider)(pagoId: pagoId, motivo: motivo);
      switch (resultado) {
        case EliminarPagoFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarPagoFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarPagoFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarPagoFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarPagoFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
