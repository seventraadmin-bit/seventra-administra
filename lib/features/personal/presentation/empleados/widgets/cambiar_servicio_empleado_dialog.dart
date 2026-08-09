import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_servicio_empleado_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';

/// Diálogo "Cambiar de servicio" (Etapa 5D) — solo cuando el Empleado
/// tiene una asignación vigente. Cierra la asignación anterior (motivo
/// automático `cambioServicio`) y crea la nueva en una sola transacción
/// — el usuario nunca tiene que retirar primero y asignar después
/// (Resolución explícita de Marlon).
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoCambiarServicioEmpleado(
  BuildContext context,
  WidgetRef ref,
  EmpleadoData empleado,
  String servicioActualId,
) async {
  final l10n = AppLocalizations.of(context)!;

  String? servicioId;
  String? turnoId;
  DateTime? fecha = DateTime.now();
  final observacionesController = TextEditingController();
  String? errorServicio;
  String? errorFecha;

  final servicios = (await ref.read(servicioRepositoryProvider).listar())
      .where((item) => item.servicio.estatus == EstatusServicio.activo.name && item.servicio.id != servicioActualId)
      .toList();
  final modalidadesTurno = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cambiarServicioEmpleadoDialogoTitulo,
    confirmLabel: l10n.cambiarServicioEmpleadoBotonConfirmar,
    cancelLabel: l10n.cambiarServicioEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegSelect<String?>(
              label: l10n.empleadoCampoServicioNuevo,
              value: servicioId,
              errorText: errorServicio,
              items: [
                for (final item in servicios) RisegSelectItem(value: item.servicio.id, label: item.servicio.nombre),
              ],
              onChanged: (valor) => setState(() {
                servicioId = valor;
                errorServicio = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.empleadoCampoTurno,
              value: turnoId,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final m in modalidadesTurno) RisegSelectItem(value: m.id, label: m.nombre),
              ],
              onChanged: (valor) => setState(() => turnoId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.empleadoCampoFechaCambioServicio,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoObservaciones, controller: observacionesController),
          ],
        );
      },
    ),
    onConfirm: () async {
      if (servicioId == null) {
        errorServicio = l10n.empleadoCampoServicioNuevo;
        return false;
      }
      if (fecha == null) {
        errorFecha = l10n.empleadoCampoFechaCambioServicio;
        return false;
      }

      final resultado = await ref.read(cambiarServicioEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleado.id,
            nuevoServicioId: servicioId!,
            fecha: fecha!,
            turnoId: turnoId,
            observaciones: observacionesController.text,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case CambiarServicioEmpleadoExitoso():
          RisegFeedback.showSuccess(context, l10n.cambiarServicioEmpleadoExito);
          return true;
        case CambiarServicioEmpleadoEmpleadoNoExiste():
        case CambiarServicioEmpleadoNoTieneAsignacionVigente():
        case CambiarServicioEmpleadoErrorInesperado():
          RisegFeedback.showError(context, l10n.cambiarServicioEmpleadoErrorInesperado);
          return false;
        case CambiarServicioEmpleadoServicioNoExiste():
        case CambiarServicioEmpleadoServicioNoActivo():
        case CambiarServicioEmpleadoMismoServicio():
          errorServicio = l10n.empleadoErrorServicioNoActivo;
          return false;
        case CambiarServicioEmpleadoFechaInvalida():
          errorFecha = l10n.cambiarServicioEmpleadoErrorFechaInvalida;
          return false;
      }
    },
  );

  observacionesController.dispose();
  return resultado ?? false;
}
