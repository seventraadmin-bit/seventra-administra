import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/compras/domain/usecases/eliminar_compra_fisicamente_usecase.dart';

import '../../compras_providers.dart';

/// Eliminación física extraordinaria de una Compra (Etapa 15) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en `eliminarCompraFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. Elimina, en la misma
/// transacción, la Compra, sus renglones, las integraciones de
/// Inventario que generó y su propio Egreso — el único rechazo real es
/// historia posterior verificada (unidad asignada/vinculada, o
/// movimientos adicionales).
Future<bool> mostrarDialogoEliminarCompraFisicamente(BuildContext context, WidgetRef ref, String compraId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.compraExpedienteSeccionDatos}',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarCompraFisicamenteAutorizadoProvider)(compraId: compraId, motivo: motivo);
      switch (resultado) {
        case EliminarCompraFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarCompraFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarCompraFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarCompraFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarCompraFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
