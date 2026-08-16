import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_egreso_fisicamente_usecase.dart';

import '../../../finanzas_providers.dart';

/// Eliminación física extraordinaria de un Egreso (Etapa 15) — facultad
/// exclusiva del Usuario Maestro; el ítem de menú que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en `eliminarEgresoFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. Un Egreso generado
/// automáticamente por una Compra o un Pago de Nómina siempre se
/// rechaza, con el folio real del origen — nunca un mensaje genérico.
Future<bool> mostrarDialogoEliminarEgresoFisicamente(BuildContext context, WidgetRef ref, String egresoId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.egresoDetalleDialogoTitulo}',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarEgresoFisicamenteAutorizadoProvider)(egresoId: egresoId, motivo: motivo);
      switch (resultado) {
        case EliminarEgresoFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarEgresoFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarEgresoFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarEgresoFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarEgresoFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
