import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Cambiar asignación" (Etapa 9B) — cierra la vigente y crea
/// una nueva hacia otro Empleado/Servicio, una sola operación. Si
/// [tieneEquipoAsociado], expone "mover también el equipo asociado".
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCambiarAsignacionLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  AsignacionLineaTelefonicaData asignacionActual, {
  required bool tieneEquipoAsociado,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);

  final empleados = await opciones.obtenerEmpleados();
  final servicios = await opciones.obtenerServicios();
  if (!context.mounted) return false;

  String destinoTipo = asignacionActual.servicioId != null ? 'servicio' : 'empleado';
  String? empleadoId;
  String? servicioId;
  DateTime fecha = DateTime.now();
  final observacionesTerminoCtrl = TextEditingController();
  final observacionesNuevaCtrl = TextEditingController();
  bool moverEquipoAsociado = true;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaCambiarAsignacionDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaCambiarAsignacionBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: l10n.lineaTelefonicaAsignarCampoDestinoTipo,
                value: destinoTipo,
                items: [
                  RisegSelectItem(value: 'empleado', label: l10n.lineaTelefonicaAsignarOpcionEmpleado),
                  RisegSelectItem(value: 'servicio', label: l10n.lineaTelefonicaAsignarOpcionServicio),
                ],
                onChanged: (valor) => setState(() {
                  destinoTipo = valor ?? destinoTipo;
                  empleadoId = null;
                  servicioId = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              if (destinoTipo == 'empleado')
                RisegSelect<String?>(
                  label: l10n.lineaTelefonicaAsignarCampoEmpleado,
                  value: empleadoId,
                  items: [for (final e in empleados) RisegSelectItem(value: e.id, label: e.nombre)],
                  onChanged: (valor) => setState(() => empleadoId = valor),
                )
              else
                RisegSelect<String?>(
                  label: l10n.lineaTelefonicaAsignarCampoServicio,
                  value: servicioId,
                  items: [for (final s in servicios) RisegSelectItem(value: s.id, label: s.nombre)],
                  onChanged: (valor) => setState(() => servicioId = valor),
                ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaAsignarCampoFechaInicio,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.lineaTelefonicaCambiarAsignacionCampoObservacionesTermino,
                controller: observacionesTerminoCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.lineaTelefonicaCambiarAsignacionCampoObservacionesNueva,
                controller: observacionesNuevaCtrl,
              ),
              if (tieneEquipoAsociado) ...[
                const SizedBox(height: AppSpacing.xs),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.lineaTelefonicaCampoMoverEquipoAsociado),
                  value: moverEquipoAsociado,
                  onChanged: (valor) => setState(() => moverEquipoAsociado = valor ?? moverEquipoAsociado),
                ),
              ],
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      if (destinoTipo == 'empleado' ? empleadoId == null : servicioId == null) {
        errorGeneral = l10n.lineaTelefonicaAsignarErrorDestinoInvalido;
        return null;
      }

      final resultado = await ref.read(cambiarAsignacionLineaTelefonicaUseCaseProvider).ejecutar(
            asignacionLineaTelefonicaActualId: asignacionActual.id,
            fecha: fecha,
            observacionesTermino:
                observacionesTerminoCtrl.text.trim().isEmpty ? null : observacionesTerminoCtrl.text.trim(),
            nuevoEmpleadoId: destinoTipo == 'empleado' ? empleadoId : null,
            nuevoServicioId: destinoTipo == 'servicio' ? servicioId : null,
            observacionesNueva: observacionesNuevaCtrl.text.trim().isEmpty ? null : observacionesNuevaCtrl.text.trim(),
            moverEquipoAsociado: moverEquipoAsociado,
          );
      if (!context.mounted) return false;
      switch (resultado) {
        case CambiarAsignacionLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaCambiarAsignacionExito);
          return true;
        case CambiarAsignacionLineaTelefonicaDestinoInvalido():
          errorGeneral = l10n.lineaTelefonicaAsignarErrorDestinoInvalido;
          return null;
        case CambiarAsignacionLineaTelefonicaYaCerrada():
          errorGeneral = l10n.lineaTelefonicaCambiarAsignacionErrorYaCerrada;
          return null;
        case CambiarAsignacionLineaTelefonicaNoExiste():
        case CambiarAsignacionLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesTerminoCtrl.dispose();
    observacionesNuevaCtrl.dispose();
  });
  return resultado ?? false;
}
