import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_asignacion_vehiculo_usecase.dart';

import '../vehiculos_controller.dart';
import '../../vehiculos_providers.dart';

/// Diálogo "Cambiar asignación" (Etapa 8B) — cierra la vigente y crea
/// la nueva en una sola operación. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCambiarAsignacionVehiculo(
  BuildContext context,
  WidgetRef ref,
  AsignacionVehiculoData asignacionActual,
) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(vehiculosControllerProvider.notifier);
  final opciones = ref.read(obtenerOpcionesAsignacionVehiculoUseCaseProvider);

  final empleados = await opciones.obtenerEmpleados();
  final servicios = await opciones.obtenerServicios();
  if (!context.mounted) return false;

  String destinoTipo = 'empleado';
  String? empleadoId;
  String? servicioId;
  DateTime fecha = DateTime.now();
  final observacionesTerminoCtrl = TextEditingController();
  final observacionesNuevaCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoCambiarAsignacionDialogoTitulo,
    confirmLabel: l10n.vehiculoCambiarAsignacionBotonConfirmar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: l10n.vehiculoAsignarCampoDestinoTipo,
                value: destinoTipo,
                items: [
                  RisegSelectItem(value: 'empleado', label: l10n.vehiculoAsignarOpcionEmpleado),
                  RisegSelectItem(value: 'servicio', label: l10n.vehiculoAsignarOpcionServicio),
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
                  label: l10n.vehiculoAsignarCampoEmpleado,
                  value: empleadoId,
                  items: [for (final e in empleados) RisegSelectItem(value: e.id, label: e.nombre)],
                  onChanged: (valor) => setState(() => empleadoId = valor),
                )
              else
                RisegSelect<String?>(
                  label: l10n.vehiculoAsignarCampoServicio,
                  value: servicioId,
                  items: [for (final s in servicios) RisegSelectItem(value: s.id, label: s.nombre)],
                  onChanged: (valor) => setState(() => servicioId = valor),
                ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoCambiarAsignacionCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoCambiarAsignacionCampoObservacionesTermino,
                controller: observacionesTerminoCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoCambiarAsignacionCampoObservacionesNueva,
                controller: observacionesNuevaCtrl,
              ),
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
        errorGeneral = l10n.vehiculoAsignarErrorDestinoInvalido;
        return null;
      }

      final resultado = await notifier.cambiarAsignacion(
        asignacionVehiculoActualId: asignacionActual.id,
        fecha: fecha,
        observacionesTermino: observacionesTerminoCtrl.text.trim().isEmpty ? null : observacionesTerminoCtrl.text.trim(),
        nuevoEmpleadoId: destinoTipo == 'empleado' ? empleadoId : null,
        nuevoServicioId: destinoTipo == 'servicio' ? servicioId : null,
        observacionesNueva: observacionesNuevaCtrl.text.trim().isEmpty ? null : observacionesNuevaCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CambiarAsignacionVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoCambiarAsignacionExito);
          return true;
        case CambiarAsignacionVehiculoDestinoInvalido():
          errorGeneral = l10n.vehiculoAsignarErrorDestinoInvalido;
          return null;
        case CambiarAsignacionVehiculoNoExiste():
        case CambiarAsignacionVehiculoYaCerrada():
        case CambiarAsignacionVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
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
