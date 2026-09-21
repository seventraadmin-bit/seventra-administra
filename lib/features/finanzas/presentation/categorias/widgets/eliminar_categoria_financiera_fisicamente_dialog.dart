import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_categoria_financiera_fisicamente_usecase.dart';

import '../../../finanzas_providers.dart';

/// Eliminación física extraordinaria de una Categoría financiera
/// (Etapa 18) — facultad exclusiva del Usuario Maestro; el ítem de
/// menú que invoca esta función solo debe mostrarse cuando
/// `sesion.esMaestro == true`, pero la protección real vive en
/// `eliminarCategoriaFinancieraFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. Una categoría con Ingresos u
/// Egresos reales que la referencian siempre se rechaza, con las
/// cantidades reales — Archivar sigue disponible como alternativa.
Future<bool> mostrarDialogoEliminarCategoriaFinancieraFisicamente(
  BuildContext context,
  WidgetRef ref,
  String categoriaFinancieraId,
) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.categoriaEliminarFisicamenteTitulo}',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarCategoriaFinancieraFisicamenteAutorizadoProvider)(
        categoriaFinancieraId: categoriaFinancieraId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarCategoriaFinancieraFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarCategoriaFinancieraFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarCategoriaFinancieraFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarCategoriaFinancieraFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarCategoriaFinancieraFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
