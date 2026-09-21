import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'coherencia_linea_equipo_mensajes.dart';

/// Lo que el expediente debe hacer al cerrarse el diálogo.
enum ResultadoResolucionInconsistencia {
  /// No se tocó nada.
  cancelado,

  /// La línea quedó alineada con la custodia del equipo.
  resuelto,

  /// Quien opera pidió ir al expediente del equipo para resolver la
  /// custodia desde ahí (Inventario manda: esta pantalla no la mueve).
  irAlEquipo,
}

/// "Resolver inconsistencia" (§21) — ofrece **sólo** las salidas que
/// corresponden al estado real, y ninguna de ellas modifica Inventario.
///
/// - `lineaSinAsignacion`: asignar la línea al destino que ya tiene el
///   equipo. Es el caso MILOYILE.
/// - `destinosDistintos`: alinear la línea con la custodia vigente.
/// - `equipoSinCustodia`: no hay nada que Telefonía pueda arreglar sola
///   — se explica y se ofrece ir al equipo.
///
/// Las dos primeras son correcciones administrativas de historia, así
/// que exigen motivo (§22). El propio caso de uso lo vuelve a exigir:
/// aquí no vive una segunda regla, sólo el campo.
Future<ResultadoResolucionInconsistencia> mostrarDialogoResolverInconsistenciaLineaEquipo(
  BuildContext context,
  WidgetRef ref, {
  required String lineaTelefonicaId,
  required AsignacionLineaTelefonicaData? asignacionVigente,
  required CoherenciaLineaEquipo coherencia,
  required NombresDestinoTelefonia nombres,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final custodia = coherencia.destinoEquipo;
  final puedeAlinear = custodia != null &&
      (coherencia.estado == EstadoCoherenciaLineaEquipo.lineaSinAsignacion ||
          coherencia.estado == EstadoCoherenciaLineaEquipo.destinosDistintos);

  final explicacion = switch (coherencia.estado) {
    EstadoCoherenciaLineaEquipo.lineaSinAsignacion =>
      l10n.lineaTelefonicaResolverInconsistenciaExplicacionLineaSinAsignacion(nombres.etiqueta(custodia, l10n)),
    EstadoCoherenciaLineaEquipo.equipoSinCustodia =>
      l10n.lineaTelefonicaResolverInconsistenciaExplicacionSinCustodia(
        nombres.etiqueta(coherencia.destinoLinea, l10n),
      ),
    _ => l10n.lineaTelefonicaCoherenciaDestinosDistintos(
        nombres.etiqueta(coherencia.destinoLinea, l10n),
        nombres.etiqueta(custodia, l10n),
      ),
  };

  var irAlEquipo = false;

  final resuelto = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaResolverInconsistenciaTitulo,
    confirmLabel: puedeAlinear
        ? l10n.lineaTelefonicaResolverInconsistenciaConfirmar
        : l10n.lineaTelefonicaResolverInconsistenciaIrAInventario,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final colors = dialogContext.colors;
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(explicacion, style: AppTypography.body),
              if (puedeAlinear) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.lineaTelefonicaResolverInconsistenciaAsignarLinea(nombres.etiqueta(custodia, l10n)),
                  style: AppTypography.label.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('resolver_inconsistencia_campo_motivo'),
                  label: l10n.lineaTelefonicaResolverInconsistenciaCampoMotivo,
                  controller: motivoCtrl,
                ),
              ],
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      if (!puedeAlinear) {
        irAlEquipo = true;
        return false;
      }

      final empleadoId = custodia.tipo == TipoDestinoTelefonia.empleado ? custodia.id : null;
      final servicioId = custodia.tipo == TipoDestinoTelefonia.servicio ? custodia.id : null;

      if (asignacionVigente == null) {
        final r = await ref.read(asignarLineaTelefonicaAutorizadoProvider)(
          lineaTelefonicaId: lineaTelefonicaId,
          empleadoId: empleadoId,
          servicioId: servicioId,
          fechaInicio: DateTime.now(),
          motivo: motivoCtrl.text,
        );
        if (!context.mounted) return false;
        switch (r) {
          case AsignarLineaTelefonicaExitoso():
            RisegFeedback.showSuccess(context, l10n.lineaTelefonicaResolverInconsistenciaExito);
            return true;
          case AsignarLineaTelefonicaMotivoRequerido():
            errorGeneral = l10n.lineaTelefonicaCoherenciaMotivoRequerido;
            return null;
          case AsignarLineaTelefonicaIncoherenteConEquipo(:final coherencia):
            errorGeneral = mensajeIncoherenciaLineaEquipo(l10n, coherencia, nombres);
            return null;
          default:
            RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
            return false;
        }
      }

      final r = await ref.read(cambiarAsignacionLineaTelefonicaAutorizadoProvider)(
        asignacionLineaTelefonicaActualId: asignacionVigente.id,
        fecha: DateTime.now(),
        nuevoEmpleadoId: empleadoId,
        nuevoServicioId: servicioId,
        motivo: motivoCtrl.text,
      );
      if (!context.mounted) return false;
      switch (r) {
        case CambiarAsignacionLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaResolverInconsistenciaExito);
          return true;
        case CambiarAsignacionLineaTelefonicaMotivoRequerido():
          errorGeneral = l10n.lineaTelefonicaCoherenciaMotivoRequerido;
          return null;
        case CambiarAsignacionLineaTelefonicaIncoherenteConEquipo(:final coherencia):
          errorGeneral = mensajeIncoherenciaLineaEquipo(l10n, coherencia, nombres);
          return null;
        default:
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());

  if (resuelto == true) return ResultadoResolucionInconsistencia.resuelto;
  if (irAlEquipo) return ResultadoResolucionInconsistencia.irAlEquipo;
  return ResultadoResolucionInconsistencia.cancelado;
}
