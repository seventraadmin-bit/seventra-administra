import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/asignar_vehiculo_usecase.dart';

import '../vehiculos_controller.dart';
import '../../vehiculos_providers.dart';

/// Diálogo "Asignar" (Etapa 8B) — entrega un Vehículo `disponible` a
/// un Empleado o a un Servicio. Kilometraje de entrega opcional (punto
/// 10 de Marlon). Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoAsignarVehiculo(BuildContext context, WidgetRef ref, String vehiculoId) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(vehiculosControllerProvider.notifier);
  final opciones = ref.read(obtenerOpcionesAsignacionVehiculoUseCaseProvider);

  final empleados = await opciones.obtenerEmpleados();
  final servicios = await opciones.obtenerServicios();
  if (!context.mounted) return false;

  String destinoTipo = 'empleado';
  String? empleadoId;
  String? servicioId;
  DateTime fechaInicio = DateTime.now();
  final observacionesCtrl = TextEditingController();
  final kilometrajeCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoAsignarDialogoTitulo,
    confirmLabel: l10n.vehiculoAsignarBotonConfirmar,
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
                label: l10n.vehiculoAsignarCampoFechaInicio,
                value: fechaInicio,
                onChanged: (valor) => setState(() => fechaInicio = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoAsignarCampoKilometrajeEntrega,
                controller: kilometrajeCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoAsignarCampoObservaciones, controller: observacionesCtrl),
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
      final kilometrajeTexto = kilometrajeCtrl.text.trim();
      final kilometraje = kilometrajeTexto.isEmpty ? null : int.tryParse(kilometrajeTexto);
      if (kilometrajeTexto.isNotEmpty && kilometraje == null) {
        errorGeneral = l10n.vehiculoRegistrarKilometrajeErrorInvalido;
        return null;
      }

      final resultado = await notifier.asignar(
        vehiculoId: vehiculoId,
        empleadoId: destinoTipo == 'empleado' ? empleadoId : null,
        servicioId: destinoTipo == 'servicio' ? servicioId : null,
        fechaInicio: fechaInicio,
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
        kilometrajeEntrega: kilometraje,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case AsignarVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoAsignarExito);
          return true;
        case AsignarVehiculoDestinoInvalido():
          errorGeneral = l10n.vehiculoAsignarErrorDestinoInvalido;
          return null;
        case AsignarVehiculoNoDisponible(:final estatusActual):
          errorGeneral = l10n.vehiculoAsignarErrorNoDisponible(estatusActual);
          return null;
        case AsignarVehiculoKilometrajeMenorAlActual(:final actual):
          errorGeneral = l10n.vehiculoAsignarErrorKilometrajeMenor(actual);
          return null;
        case AsignarVehiculoNoExiste():
        case AsignarVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
          return false;
      }
    },
  );

  // Un frame después, no de inmediato — el diálogo todavía está
  // animando su cierre en este instante (ver el doc comment
  // equivalente en `mostrarDialogoGestionarVehiculo`).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesCtrl.dispose();
    kilometrajeCtrl.dispose();
  });
  return resultado ?? false;
}
