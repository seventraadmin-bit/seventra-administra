import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';

/// Diálogo "Asignar a servicio" (Etapa 5D) — solo cuando el Empleado no
/// tiene una asignación vigente. Registra Servicio/Turno/Fecha de
/// inicio/Observaciones, nada de horarios/incidencias (fuera de
/// alcance explícito).
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoAsignarServicioEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
  final l10n = AppLocalizations.of(context)!;

  String? servicioId;
  String? turnoId;
  DateTime? fecha = DateTime.now();
  final observacionesController = TextEditingController();
  String? errorServicio;
  String? errorFecha;

  final servicios = (await ref.read(servicioRepositoryProvider).listar())
      .where((item) => item.servicio.estatus == EstatusServicio.activo.name)
      .toList();
  final modalidadesTurno = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.asignarServicioEmpleadoDialogoTitulo,
    confirmLabel: l10n.asignarServicioEmpleadoBotonConfirmar,
    cancelLabel: l10n.asignarServicioEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegSelect<String?>(
              label: l10n.empleadoCampoServicio,
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
              label: l10n.empleadoCampoFechaInicioAsignacion,
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
        errorServicio = l10n.empleadoCampoServicio;
        return false;
      }
      if (fecha == null) {
        errorFecha = l10n.empleadoCampoFechaInicioAsignacion;
        return false;
      }

      final resultado = await ref.read(asignarEmpleadoServicioUseCaseProvider).ejecutar(
            empleadoId: empleado.id,
            servicioId: servicioId!,
            fechaInicio: fecha!,
            turnoId: turnoId,
            observaciones: observacionesController.text,
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case AsignarEmpleadoServicioExitoso():
          RisegFeedback.showSuccess(context, l10n.asignarServicioEmpleadoExito);
          return true;
        case AsignarEmpleadoServicioEmpleadoNoExiste():
        case AsignarEmpleadoServicioEmpleadoNoActivo():
        case AsignarEmpleadoServicioYaTieneAsignacionVigente():
        case AsignarEmpleadoServicioErrorInesperado():
          RisegFeedback.showError(context, l10n.asignarServicioEmpleadoErrorInesperado);
          return false;
        case AsignarEmpleadoServicioServicioNoExiste():
        case AsignarEmpleadoServicioServicioNoActivo():
          errorServicio = l10n.empleadoErrorServicioNoActivo;
          return false;
        case AsignarEmpleadoServicioFechaInvalida():
          errorFecha = l10n.asignarServicioEmpleadoErrorFechaInvalida;
          return false;
      }
    },
  );

  observacionesController.dispose();
  return resultado ?? false;
}
