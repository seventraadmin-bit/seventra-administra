import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/eliminar_categoria_articulo_fisicamente_usecase.dart';

import '../../../inventario_providers.dart';

/// Eliminación física extraordinaria de una CategoriaArticulo (Etapa
/// 11D) — facultad exclusiva del Usuario Maestro; el botón que invoca
/// esta función solo debe mostrarse cuando `sesion.esMaestro == true`,
/// pero la protección real vive en
/// `eliminarCategoriaArticuloFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI.
Future<bool> mostrarDialogoEliminarCategoriaArticuloFisicamente(
  BuildContext context,
  WidgetRef ref,
  String categoriaArticuloId,
) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Categoría de artículo',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarCategoriaArticuloFisicamenteAutorizadoProvider)(
        categoriaArticuloId: categoriaArticuloId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarCategoriaArticuloFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarCategoriaArticuloFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarCategoriaArticuloFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarCategoriaArticuloFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarCategoriaArticuloFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
