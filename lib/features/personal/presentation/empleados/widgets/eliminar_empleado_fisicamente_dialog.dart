import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/domain/usecases/eliminar_empleado_fisicamente_usecase.dart';

import '../../../personal_providers.dart';

/// Arma el mensaje de confirmación dinámico (Etapa 15) — nombra
/// explícitamente cuántas Fichas técnicas y documentos se eliminarán
/// junto con el Empleado (decisión explícita de Marlon: la Ficha
/// técnica nunca bloquea, se limpia con el resto del expediente).
String _mensajeConfirmacion(AppLocalizations l10n, ResumenEliminacionEmpleado resumen) {
  final partes = <String>[
    if (resumen.cantidadFichasTecnicas > 0)
      l10n.empleadoDetalleEliminarResumenFichasTecnicas(resumen.cantidadFichasTecnicas),
    if (resumen.cantidadDocumentos > 0) l10n.empleadoDetalleEliminarResumenDocumentos(resumen.cantidadDocumentos),
  ];
  if (partes.isEmpty) return l10n.empleadoDetalleEliminarResumenSinDependencias;
  return l10n.empleadoDetalleEliminarResumenMensaje(partes.join(' y '));
}

/// Eliminación física extraordinaria de un `Empleado` (Etapa 15) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en `eliminarEmpleadoFisicamenteAutorizadoProvider`
/// (`exigirMaestro`) — nunca en la UI. El único bloqueo real (Nómina,
/// Asignación a Servicio, Inventario, Vehículo, Línea telefónica) se
/// revisa ANTES de abrir el diálogo de motivo, con un mensaje
/// específico, nunca genérico.
Future<bool> mostrarDialogoEliminarEmpleadoFisicamente(BuildContext context, WidgetRef ref, String empleadoId) async {
  final l10n = AppLocalizations.of(context)!;

  final resumen = await ref.read(eliminarEmpleadoFisicamenteUseCaseProvider).obtenerResumen(empleadoId);
  if (!context.mounted) return false;
  if (!resumen.existe) {
    RisegFeedback.showError(context, l10n.eliminacionFisicaErrorNoExiste);
    return false;
  }
  if (resumen.bloqueado) {
    RisegFeedback.showError(context, resumen.detalleBloqueo!);
    return false;
  }

  var archivosNoEliminados = const <String>[];

  final eliminado = await mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — ${l10n.empleadoExpedienteTitulo}',
    advertencia: _mensajeConfirmacion(l10n, resumen),
    eliminar: (motivo) async {
      final resultado =
          await ref.read(eliminarEmpleadoFisicamenteAutorizadoProvider)(empleadoId: empleadoId, motivo: motivo);
      switch (resultado) {
        case EliminarEmpleadoFisicamenteExitoso(:final archivosNoEliminadosFisicamente):
          archivosNoEliminados = archivosNoEliminadosFisicamente;
          return ResultadoEliminacionFisica.exitoso;
        case EliminarEmpleadoFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarEmpleadoFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarEmpleadoFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.tieneDependencias;
        case EliminarEmpleadoFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );

  // Advertencia explícita y separada del toast de éxito — nunca se
  // oculta un archivo físico que no se pudo borrar.
  if (eliminado && archivosNoEliminados.isNotEmpty && context.mounted) {
    RisegFeedback.showError(
      context,
      l10n.empleadoDetalleEliminarArchivosNoEliminados(archivosNoEliminados.length, archivosNoEliminados.join(', ')),
    );
  }

  return eliminado;
}
