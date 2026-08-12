import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/eliminar_articulo_fisicamente_usecase.dart';

import '../../../inventario_providers.dart';

/// Eliminación física extraordinaria de un Artículo (Etapa 11D) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en
/// `eliminarArticuloFisicamenteAutorizadoProvider` (`exigirMaestro`)
/// — nunca en la UI.
Future<bool> mostrarDialogoEliminarArticuloFisicamente(BuildContext context, WidgetRef ref, String articuloId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Artículo',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarArticuloFisicamenteAutorizadoProvider)(
        articuloId: articuloId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarArticuloFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarArticuloFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarArticuloFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarArticuloFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarArticuloFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
