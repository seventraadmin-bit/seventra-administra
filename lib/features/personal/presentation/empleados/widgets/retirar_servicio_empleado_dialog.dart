import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/asignacion_servicio_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/retirar_empleado_servicio_usecase.dart';

import '../../../personal_providers.dart';

String motivoTerminoAsignacionLabel(AppLocalizations l10n, String valor) {
  return switch (MotivoTerminoAsignacion.values.byName(valor)) {
    MotivoTerminoAsignacion.solicitudCliente => l10n.motivoTerminoAsignacionSolicitudCliente,
    MotivoTerminoAsignacion.reestructuracionOperativa => l10n.motivoTerminoAsignacionReestructuracionOperativa,
    MotivoTerminoAsignacion.bajoDesempeno => l10n.motivoTerminoAsignacionBajoDesempeno,
    MotivoTerminoAsignacion.otro => l10n.motivoTerminoAsignacionOtro,
    MotivoTerminoAsignacion.cambioServicio => l10n.motivoTerminoAsignacionCambioServicio,
    MotivoTerminoAsignacion.bajaEmpleado => l10n.motivoTerminoAsignacionBajaEmpleado,
    MotivoTerminoAsignacion.servicioTerminado => l10n.motivoTerminoAsignacionServicioTerminado,
  };
}

/// Diálogo "Retirar del servicio" (Etapa 5D) — el Empleado sigue activo,
/// solo deja de estar asignado. Únicamente ofrece los motivos
/// `seleccionableManualmente` — los automáticos los coloca el sistema.
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoRetirarServicioEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime? fecha = DateTime.now();
  MotivoTerminoAsignacion motivo = MotivoTerminoAsignacion.solicitudCliente;
  final observacionesController = TextEditingController();
  String? errorFecha;
  String? errorObservaciones;

  final motivosManuales = MotivoTerminoAsignacion.values.where((m) => m.seleccionableManualmente).toList();

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.retirarServicioEmpleadoDialogoTitulo,
    confirmLabel: l10n.retirarServicioEmpleadoBotonConfirmar,
    cancelLabel: l10n.retirarServicioEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: l10n.empleadoCampoFechaTerminoAsignacion,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<MotivoTerminoAsignacion>(
              label: l10n.empleadoCampoMotivoTerminoAsignacion,
              value: motivo,
              items: [
                for (final m in motivosManuales) RisegSelectItem(value: m, label: motivoTerminoAsignacionLabel(l10n, m.name)),
              ],
              onChanged: (valor) => setState(() {
                motivo = valor ?? motivo;
                errorObservaciones = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoObservaciones,
              controller: observacionesController,
              errorText: errorObservaciones,
              onChanged: (_) => setState(() => errorObservaciones = null),
            ),
          ],
        );
      },
    ),
    onConfirm: () async {
      if (fecha == null) {
        errorFecha = l10n.empleadoCampoFechaTerminoAsignacion;
        return false;
      }

      final resultado = await ref.read(retirarEmpleadoServicioAutorizadoProvider)(
            empleadoId: empleado.id,
            fechaTermino: fecha!,
            motivo: motivo,
            observaciones: observacionesController.text,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case RetirarEmpleadoServicioExitoso():
          RisegFeedback.showSuccess(context, l10n.retirarServicioEmpleadoExito);
          return true;
        case RetirarEmpleadoServicioEmpleadoNoExiste():
        case RetirarEmpleadoServicioNoTieneAsignacionVigente():
        case RetirarEmpleadoServicioMotivoNoSeleccionable():
        case RetirarEmpleadoServicioErrorInesperado():
          RisegFeedback.showError(context, l10n.retirarServicioEmpleadoErrorInesperado);
          return false;
        case RetirarEmpleadoServicioFechaInvalida():
          errorFecha = l10n.retirarServicioEmpleadoErrorFechaInvalida;
          return false;
        case RetirarEmpleadoServicioObservacionesRequeridas():
          errorObservaciones = l10n.retirarServicioEmpleadoErrorObservacionesRequeridas;
          return false;
      }
    },
  );

  observacionesController.dispose();
  return resultado ?? false;
}
