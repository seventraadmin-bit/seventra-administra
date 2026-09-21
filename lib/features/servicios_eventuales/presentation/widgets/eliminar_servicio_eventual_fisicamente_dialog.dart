import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import '../servicios_eventuales_controller.dart';

/// Eliminación física extraordinaria de un Servicio Eventual — facultad
/// exclusiva del Usuario Maestro.
///
/// **No es cancelar.** Cancelar un evento es una operación que ocurrió
/// y se conserva; esto es para el registro de prueba o la captura
/// equivocada, lo que nunca debió existir. Por eso el evento
/// desaparece y lo único que queda es el asiento de auditoría central
/// (`EliminacionFisicaEvento`) con su snapshot y el motivo.
///
/// Reutiliza el caparazón compartido `mostrarDialogoEliminarFisicamente`
/// (motivo obligatorio + advertencia), como el resto de los dominios;
/// lo único propio es la advertencia, que nombra el folio y enumera
/// qué se va con él. La protección real vive en
/// `eliminarServicioEventualFisicamenteAutorizadoProvider`
/// (`exigirMaestro`), nunca en esta pantalla.
Future<bool> mostrarDialogoEliminarServicioEventualFisicamente(
  BuildContext context,
  WidgetRef ref, {
  required ServicioEventualData eventual,
}) async {
  final l10n = AppLocalizations.of(context)!;
  String? detalleBloqueo;

  final eliminado = await mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.servicioEventualAccionEliminarDefinitivamente} — ${eventual.folio}',
    advertencia: l10n.servicioEventualEliminarAdvertencia(eventual.folio, eventual.nombre),
    eliminar: (motivo) async {
      final resultado = await ref.read(serviciosEventualesControllerProvider.notifier).eliminarFisicamente(
            servicioEventualId: eventual.id,
            motivo: motivo,
          );
      switch (resultado) {
        case EliminarServicioEventualFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarServicioEventualFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarServicioEventualFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarServicioEventualFisicamenteTieneDependencias(:final detalle):
          // El caparazón no muestra nada para este caso, a propósito:
          // el detalle concreto es más útil que un aviso genérico.
          detalleBloqueo = detalle;
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarServicioEventualFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );

  final bloqueo = detalleBloqueo;
  if (bloqueo != null && context.mounted) RisegFeedback.showError(context, bloqueo);
  return eliminado;
}
