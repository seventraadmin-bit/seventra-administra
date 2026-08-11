import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_sucursal_fisicamente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Eliminación física extraordinaria de una Sucursal (Etapa 11D) —
/// facultad exclusiva del Usuario Maestro; el botón que invoca esta
/// función solo debe mostrarse cuando `sesion.esMaestro == true`, pero
/// la protección real vive en
/// `eliminarSucursalFisicamenteAutorizadoProvider` (`exigirMaestro`)
/// — nunca en la UI.
///
/// Nota operativa: toda Sucursal creada por
/// `SucursalRepositoryImpl.crear` inserta transaccionalmente una
/// `Ubicacion` raíz, así que en la práctica esta acción siempre
/// devuelve `TieneDependencias` — se deja disponible por si en el
/// futuro existe una Sucursal sin esa Ubicación (p. ej. capturada por
/// otra vía), no porque hoy sea alcanzable en el flujo normal.
Future<bool> mostrarDialogoEliminarSucursalFisicamente(BuildContext context, WidgetRef ref, String sucursalId) async {
  final l10n = AppLocalizations.of(context)!;

  return mostrarDialogoEliminarFisicamente(
    context,
    titulo: '${l10n.eliminacionFisicaAccionMenu} — Sucursal',
    advertencia: l10n.eliminacionFisicaAdvertenciaGenerica,
    eliminar: (motivo) async {
      final resultado = await ref.read(eliminarSucursalFisicamenteAutorizadoProvider)(
        sucursalId: sucursalId,
        motivo: motivo,
      );
      switch (resultado) {
        case EliminarSucursalFisicamenteExitoso():
          return ResultadoEliminacionFisica.exitoso;
        case EliminarSucursalFisicamenteMotivoRequerido():
          return ResultadoEliminacionFisica.motivoRequerido;
        case EliminarSucursalFisicamenteNoExiste():
          return ResultadoEliminacionFisica.noExiste;
        case EliminarSucursalFisicamenteTieneDependencias(:final detalle):
          if (context.mounted) RisegFeedback.showError(context, detalle);
          return ResultadoEliminacionFisica.errorInesperado;
        case EliminarSucursalFisicamenteErrorInesperado():
          return ResultadoEliminacionFisica.errorInesperado;
      }
    },
  );
}
