import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_documento_por_emitir_fisicamente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Arma el mensaje de confirmación dinámico (Etapa 15, ampliación
/// explícita de Marlon) — ej. "Este documento tiene una Cuenta por
/// Cobrar sin pagos y 2 archivos adjuntos. Se eliminarán junto con el
/// documento." Nunca un aviso genérico: el Maestro debe ver
/// exactamente qué se va a limpiar antes de confirmar.
String _mensajeConfirmacion(AppLocalizations l10n, ResumenEliminacionDocumentoPorEmitir resumen) {
  final partes = <String>[
    if (resumen.tieneCuentaPorCobrar) l10n.agendaDetalleEliminarResumenCuentaPorCobrar,
    if (resumen.cantidadAdjuntos > 0) l10n.agendaDetalleEliminarResumenAdjuntos(resumen.cantidadAdjuntos),
  ];
  if (partes.isEmpty) return l10n.agendaDetalleEliminarResumenSinDependencias;
  return l10n.agendaDetalleEliminarResumenMensaje(partes.join(' y '));
}

/// Eliminación física extraordinaria de un `DocumentoPorEmitir` (Etapa
/// 15) — facultad exclusiva del Usuario Maestro; el ítem de menú que
/// invoca esta función solo debe mostrarse cuando `sesion.esMaestro ==
/// true`, pero la protección real vive en
/// `eliminarDocumentoPorEmitirFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. El estatus y la sola existencia
/// de adjuntos/Cuenta por cobrar ya no bloquean — el único bloqueo real
/// (dinero real aplicado) se revisa ANTES de abrir el diálogo de
/// motivo, con un mensaje específico, nunca genérico.
Future<bool> mostrarDialogoEliminarDocumentoPorEmitirFisicamente(
  BuildContext context,
  WidgetRef ref,
  String documentoPorEmitirId,
) async {
  final l10n = AppLocalizations.of(context)!;

  final resumen =
      await ref.read(eliminarDocumentoPorEmitirFisicamenteUseCaseProvider).obtenerResumen(documentoPorEmitirId);
  if (!context.mounted) return false;
  if (!resumen.existe) {
    RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
    return false;
  }
  if (resumen.bloqueadoPorPago) {
    RisegFeedback.showError(context, resumen.detalleBloqueo!);
    return false;
  }

  var archivosNoEliminados = const <String>[];

  final eliminado = await mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.agendaDetalleDialogoTitulo}',
    advertencia: _mensajeConfirmacion(l10n, resumen),
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarDocumentoPorEmitirFisicamenteAutorizadoProvider)(
        documentoPorEmitirId: documentoPorEmitirId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarDocumentoPorEmitirFisicamenteExitoso(:final archivosNoEliminadosFisicamente):
          archivosNoEliminados = archivosNoEliminadosFisicamente;
          return ResultadoEliminacionFisica.exitoso;
        case EliminarDocumentoPorEmitirFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarDocumentoPorEmitirFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarDocumentoPorEmitirFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarDocumentoPorEmitirFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );

  // Advertencia explícita y separada del toast de éxito — nunca se
  // oculta un archivo físico que no se pudo borrar (Etapa 15,
  // instrucción explícita de Marlon: "no dejar una eliminación
  // silenciosamente incompleta").
  if (eliminado && archivosNoEliminados.isNotEmpty && context.mounted) {
    RisegFeedback.showError(
      context,
      l10n.agendaDetalleEliminarArchivosNoEliminados(archivosNoEliminados.length, archivosNoEliminados.join(', ')),
    );
  }

  return eliminado;
}
